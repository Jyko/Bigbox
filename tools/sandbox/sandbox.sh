#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

#################################################################################
# Sandbox QEMU/KVM pour développer et tester la Bigbox sans toucher au poste hôte.
#
# La Bigbox modifie réellement la machine sur laquelle elle tourne (.bashrc, .config,
# apt, systemd ...). Ce script crée une VM Ubuntu jetable dans laquelle la lancer.
#
# Une VM par release Ubuntu (ex. 24.04 et 26.04), utilisables en parallèle.
#
# Usage : tools/sandbox/sandbox.sh [-r <release>] <commande> [arguments ...]
#################################################################################

BB_SANDBOX_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BB_SANDBOX_REPO_DIR="$(cd -- "$BB_SANDBOX_SCRIPT_DIR/../.." && pwd)"
readonly BB_SANDBOX_SCRIPT_DIR BB_SANDBOX_REPO_DIR

# Réutilisation des logs de la Bigbox, la librairie est autonome
# shellcheck source=SCRIPTDIR/../../core/log.sh
source "$BB_SANDBOX_REPO_DIR/core/log.sh"

# --------------------
# Configuration (surchargeable par variables d'environnement)
# --------------------
BB_SANDBOX_DIR="${BB_SANDBOX_DIR:-$HOME/.cache/bigbox-sandbox}"
BB_SANDBOX_RELEASE="${BB_SANDBOX_RELEASE:-24.04}"
# Dimensionné pour faire tourner 2 à 3 VM en parallèle. Le disque qcow2 est alloué à l'usage :
# la taille est un maximum, pas une réservation.
BB_SANDBOX_CPUS="${BB_SANDBOX_CPUS:-2}"
BB_SANDBOX_MEMORY="${BB_SANDBOX_MEMORY:-4G}"
BB_SANDBOX_DISK_SIZE="${BB_SANDBOX_DISK_SIZE:-20G}"
BB_SANDBOX_USER="bigbox"
BB_SANDBOX_SNAPSHOT="pristine"
BB_SANDBOX_BOOT_TIMEOUT=300
BB_SANDBOX_SSH_TARGET="$BB_SANDBOX_USER@127.0.0.1"

# Chemins et port propres à l'instance de la release choisie (voir _sandbox_configure)
BB_SANDBOX_VM_DIR=""
BB_SANDBOX_OVERLAY=""
BB_SANDBOX_SSH_KEY=""
BB_SANDBOX_PID_FILE=""
BB_SANDBOX_CONSOLE_LOG=""
BB_SANDBOX_SEED_DIR=""
BB_SANDBOX_SSH_PORT=""
BB_SANDBOX_SSH_OPTS=()

# Sélectionner l'instance d'une release
# $1 : La release Ubuntu (ex. 24.04)
_sandbox_configure() {
    local release="$1"

    if [[ ! "$release" =~ ^[0-9]{2}\.(04|10)$ ]]; then
        log_error "Release Ubuntu invalide : $release (attendu : 24.04, 26.04 ...)\n"
        return 1
    fi

    BB_SANDBOX_RELEASE="$release"
    BB_SANDBOX_VM_DIR="$BB_SANDBOX_DIR/vm-$release"
    BB_SANDBOX_OVERLAY="$BB_SANDBOX_VM_DIR/overlay.qcow2"
    BB_SANDBOX_SSH_KEY="$BB_SANDBOX_VM_DIR/id_ed25519"
    BB_SANDBOX_PID_FILE="$BB_SANDBOX_VM_DIR/qemu.pid"
    BB_SANDBOX_CONSOLE_LOG="$BB_SANDBOX_VM_DIR/console.log"
    BB_SANDBOX_SEED_DIR="$BB_SANDBOX_VM_DIR/seed"
    # Port SSH unique et stable par release : 24.04 -> 22404, 26.04 -> 22604
    BB_SANDBOX_SSH_PORT="${BB_SANDBOX_SSH_PORT_OVERRIDE:-2${release/./}}"
    BB_SANDBOX_SSH_OPTS=(
        -i "$BB_SANDBOX_SSH_KEY"
        -p "$BB_SANDBOX_SSH_PORT"
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -o ConnectTimeout=5
    )
}

# Ancienne disposition (une seule VM dans vm/) : déplacée dans vm-<release>
_sandbox_migrate_legacy() {
    local legacy="$BB_SANDBOX_DIR/vm" release

    [[ -f "$legacy/release" ]] || return 0
    release=$(<"$legacy/release")
    if [[ -e "$BB_SANDBOX_DIR/vm-$release" ]]; then
        return 0
    fi
    if [[ -f "$legacy/qemu.pid" ]] && kill -0 "$(<"$legacy/qemu.pid")" 2>/dev/null; then
        log_warn "\tL'ancienne sandbox ($legacy) tourne encore, arrêtez-la avant migration\n"
        return 0
    fi
    mv "$legacy" "$BB_SANDBOX_DIR/vm-$release"
    log_info "\tSandbox $release déplacée dans $BB_SANDBOX_DIR/vm-$release\n"
}

# --------------------
# Utilitaires
# --------------------
_sandbox_require_tools() {
    local missing=()
    local tool

    for tool in qemu-system-x86_64 qemu-img ssh ssh-keygen rsync python3 curl sha256sum; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    if (( ${#missing[@]} > 0 )); then
        log_error "Outils manquants sur l'hôte : ${missing[*]}\n"
        return 1
    fi

    if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
        log_error "/dev/kvm n'est pas accessible en lecture/écriture pour $USER\n"
        return 1
    fi
}

_sandbox_is_created() {
    [[ -f "$BB_SANDBOX_OVERLAY" ]]
}

_sandbox_assert_created() {
    if ! _sandbox_is_created; then
        log_error "Aucune sandbox $BB_SANDBOX_RELEASE, lancez d'abord : $0 -r $BB_SANDBOX_RELEASE create\n"
        return 1
    fi
}

_sandbox_is_running() {
    [[ -f "$BB_SANDBOX_PID_FILE" ]] && kill -0 "$(<"$BB_SANDBOX_PID_FILE")" 2>/dev/null
}

_sandbox_ssh() {
    # shellcheck disable=SC2029 # La commande est volontairement construite côté hôte
    ssh "${BB_SANDBOX_SSH_OPTS[@]}" "$BB_SANDBOX_SSH_TARGET" "$@"
}

_sandbox_wait_ssh() {
    local start
    start=$(date +%s)

    log_info "\t⏳ Attente de la connexion SSH à la sandbox"
    until _sandbox_ssh true 2>/dev/null; do
        if ! _sandbox_is_running; then
            log_error "\r\t❌ La VM s'est arrêtée, voir $BB_SANDBOX_CONSOLE_LOG\n"
            return 1
        fi
        if (( $(date +%s) - start >= BB_SANDBOX_BOOT_TIMEOUT )); then
            log_error "\r\t❌ Pas de connexion SSH après ${BB_SANDBOX_BOOT_TIMEOUT}s, voir $BB_SANDBOX_CONSOLE_LOG\n"
            return 1
        fi
        sleep 2
    done
    log_success "\r\t✅ Sandbox $BB_SANDBOX_RELEASE joignable en SSH (port $BB_SANDBOX_SSH_PORT)\n"
}

# Lancer la VM en arrière-plan
# $@ : Arguments QEMU supplémentaires
_sandbox_boot() {
    if _sandbox_is_running; then
        log_info "\tLa sandbox tourne déjà\n"
        return 0
    fi

    qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -smp "$BB_SANDBOX_CPUS" \
        -m "$BB_SANDBOX_MEMORY" \
        -drive "file=$BB_SANDBOX_OVERLAY,if=virtio,format=qcow2" \
        -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$BB_SANDBOX_SSH_PORT-:22" \
        -display none \
        -serial "file:$BB_SANDBOX_CONSOLE_LOG" \
        -pidfile "$BB_SANDBOX_PID_FILE" \
        -daemonize \
        "$@"

    _sandbox_wait_ssh
}

_sandbox_download_image() {
    local release="$1"
    local base_url="https://cloud-images.ubuntu.com/releases/$release/release"
    local image_name="ubuntu-$release-server-cloudimg-amd64.img"
    local image_path="$BB_SANDBOX_DIR/$image_name"

    if [[ ! -f "$image_path" ]]; then
        log_info "\t⏳ Téléchargement de l'image cloud Ubuntu $release\n"
        curl -fL --progress-bar -o "$image_path.part" "$base_url/$image_name"
        mv "$image_path.part" "$image_path"
    fi

    # Vérification de l'intégrité de l'image via les sommes publiées par Canonical
    local expected
    expected=$(curl -fsSL "$base_url/SHA256SUMS" | awk -v f="*$image_name" '$2 == f || $2 == substr(f, 2) { print $1 }')

    if [[ -z "$expected" ]]; then
        log_error "Somme SHA256 introuvable pour $image_name\n"
        return 1
    fi

    if ! sha256sum --quiet -c <<< "$expected  $image_path"; then
        log_error "La somme SHA256 de $image_path ne correspond pas, image supprimée\n"
        rm -f "$image_path"
        return 1
    fi

    log_success "\t✅ Image $image_name vérifiée\n"
    echo "$image_path"
}

_sandbox_write_seed() {
    mkdir -p "$BB_SANDBOX_SEED_DIR"

    cat > "$BB_SANDBOX_SEED_DIR/meta-data" <<EOF
instance-id: bigbox-sandbox-${BB_SANDBOX_RELEASE/./}
local-hostname: bigbox-sandbox-${BB_SANDBOX_RELEASE/./}
EOF

    cat > "$BB_SANDBOX_SEED_DIR/user-data" <<EOF
#cloud-config
users:
  - name: $BB_SANDBOX_USER
    shell: /bin/bash
    # Pas de groupe sudo : sa règle "%sudo ALL=(ALL:ALL) ALL" ferait demander un mot de passe à "sudo -v"
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - $(<"$BB_SANDBOX_SSH_KEY.pub")
package_update: true
packages:
  - rsync
  - qemu-guest-agent
EOF

    : > "$BB_SANDBOX_SEED_DIR/vendor-data"
}

# --------------------
# Commandes
# --------------------
sandbox_create() {
    local release="$BB_SANDBOX_RELEASE"

    _sandbox_require_tools

    if _sandbox_is_created; then
        log_error "La sandbox $release existe déjà, lancez \`$0 -r $release destroy\` avant de la recréer\n"
        return 1
    fi

    mkdir -p "$BB_SANDBOX_VM_DIR"
    chmod 700 "$BB_SANDBOX_DIR" "$BB_SANDBOX_VM_DIR"

    local image_path
    image_path=$(_sandbox_download_image "$release")

    # Overlay jetable : l'image de base n'est jamais modifiée
    qemu-img create -q -f qcow2 -F qcow2 -b "$image_path" "$BB_SANDBOX_OVERLAY" "$BB_SANDBOX_DISK_SIZE"
    echo "$release" > "$BB_SANDBOX_VM_DIR/release"

    ssh-keygen -q -t ed25519 -N "" -C "bigbox-sandbox-$release" -f "$BB_SANDBOX_SSH_KEY"

    _sandbox_write_seed

    # Serveur HTTP éphémère pour le datasource NoCloud de cloud-init.
    # Dans le réseau user de QEMU, l'hôte (127.0.0.1) est joignable depuis la VM via 10.0.2.2.
    local seed_port
    seed_port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    python3 -m http.server --bind 127.0.0.1 --directory "$BB_SANDBOX_SEED_DIR" "$seed_port" >/dev/null 2>&1 &
    local seed_pid=$!
    # shellcheck disable=SC2064 # Le PID doit être figé maintenant
    trap "kill $seed_pid 2>/dev/null || true" EXIT

    log_info "\t⏳ Premier démarrage et configuration cloud-init (quelques minutes)\n"
    _sandbox_boot -smbios "type=1,serial=ds=nocloud;s=http://10.0.2.2:$seed_port/"

    _sandbox_ssh cloud-init status --wait >/dev/null || {
        log_error "cloud-init a échoué, voir \`$0 -r $release ssh\` puis /var/log/cloud-init-output.log\n"
        return 1
    }

    sandbox_stop

    qemu-img snapshot -c "$BB_SANDBOX_SNAPSHOT" "$BB_SANDBOX_OVERLAY"
    log_success "\t✅ Sandbox Ubuntu $release créée (snapshot \"$BB_SANDBOX_SNAPSHOT\")\n"
}

sandbox_start() {
    _sandbox_assert_created
    _sandbox_boot
}

sandbox_stop() {
    if ! _sandbox_is_running; then
        return 0
    fi

    local pid
    pid=$(<"$BB_SANDBOX_PID_FILE")

    _sandbox_ssh sudo systemctl poweroff 2>/dev/null || true

    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if (( waited >= 60 )); then
            log_warn "\tArrêt propre trop long, arrêt forcé de la VM\n"
            kill "$pid" 2>/dev/null || true
        fi
        sleep 1
        (( waited += 1 ))
    done

    rm -f "$BB_SANDBOX_PID_FILE"
    log_success "\t✅ Sandbox $BB_SANDBOX_RELEASE arrêtée\n"
}

sandbox_sync() {
    _sandbox_assert_created
    _sandbox_is_running || _sandbox_boot

    rsync -a --delete \
        --exclude ".idea/" \
        --exclude "/bin/" \
        -e "ssh ${BB_SANDBOX_SSH_OPTS[*]}" \
        "$BB_SANDBOX_REPO_DIR/" "$BB_SANDBOX_SSH_TARGET:Bigbox/"

    _sandbox_install_go
}

# Construire la Bigbox Go SUR L'HÔTE (binaire statique linux/amd64, jamais exécuté sur l'hôte)
# et l'installer dans ~/bin/bigbox de la VM. Sans Go sur l'hôte, seule la Bigbox Bash est
# disponible dans la VM.
_sandbox_install_go() {
    local binary="$BB_SANDBOX_REPO_DIR/bin/bigbox-linux-amd64" commit

    if ! command -v go >/dev/null 2>&1; then
        log_debug "\tGo absent de l'hôte : Bigbox Go non installée dans la sandbox\n"
        return 0
    fi
    commit=$(git -C "$BB_SANDBOX_REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo dev)
    if ! (cd "$BB_SANDBOX_REPO_DIR" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
            go build -trimpath -ldflags "-s -w -X main.version=sandbox-$commit" -o "$binary" ./cmd/bigbox); then
        log_error "Construction de la Bigbox Go impossible\n"
        return 1
    fi
    _sandbox_ssh mkdir -p bin
    rsync -a -e "ssh ${BB_SANDBOX_SSH_OPTS[*]}" "$binary" "$BB_SANDBOX_SSH_TARGET:bin/bigbox"
}

# Exécuter la Bigbox DANS la sandbox
# $@ : [--impl bash|go] puis arguments de la Bigbox
sandbox_run() {
    local impl=bash
    if [[ "${1:-}" == --impl ]]; then
        impl="${2:?implémentation attendue après --impl (bash ou go)}"
        shift 2
    fi
    sandbox_sync
    case "$impl" in
        bash) _sandbox_exec "cd ~/Bigbox && ./bigbox $(printf '%q ' "$@")" ;;
        go)   _sandbox_exec "cd ~/Bigbox && ~/bin/bigbox $(printf '%q ' "$@")" ;;
        *)    log_error "Implémentation inconnue : $impl (bash ou go)\n"; return 2 ;;
    esac
}

# Exécuter une commande arbitraire dans la sandbox (dépôt synchronisé dans ~/Bigbox)
# $@ : La commande
sandbox_exec() {
    sandbox_sync
    _sandbox_exec "cd ~/Bigbox && $*"
}

_sandbox_exec() {
    local tty_opt=()
    [[ -t 0 ]] && tty_opt=(-t)

    # shellcheck disable=SC2029 # La commande est déjà échappée via printf %q
    ssh "${BB_SANDBOX_SSH_OPTS[@]}" "${tty_opt[@]}" "$BB_SANDBOX_SSH_TARGET" "bash -lc $(printf '%q' "$1")"
}

sandbox_ssh() {
    _sandbox_assert_created
    _sandbox_is_running || _sandbox_boot
    ssh "${BB_SANDBOX_SSH_OPTS[@]}" -t "$BB_SANDBOX_SSH_TARGET"
}

sandbox_reset() {
    _sandbox_assert_created
    sandbox_stop
    qemu-img snapshot -a "$BB_SANDBOX_SNAPSHOT" "$BB_SANDBOX_OVERLAY"
    log_success "\t✅ Sandbox $BB_SANDBOX_RELEASE revenue au snapshot \"$BB_SANDBOX_SNAPSHOT\"\n"
}

sandbox_destroy() {
    sandbox_stop
    # Les images de base téléchargées sont conservées pour une prochaine création
    rm -rf "${BB_SANDBOX_VM_DIR:?}"
    log_success "\t✅ Sandbox $BB_SANDBOX_RELEASE supprimée\n"
}

# État de l'instance choisie (-r), ou de toutes les instances
# $1 : "all" pour lister toutes les instances
sandbox_status() {
    if [[ "${1:-}" == all ]]; then
        local dir found=false
        for dir in "$BB_SANDBOX_DIR"/vm-*/; do
            [[ -f "$dir/overlay.qcow2" ]] || continue
            found=true
            _sandbox_configure "$(basename "$dir" | sed 's/^vm-//')"
            sandbox_status
        done
        [[ "$found" == true ]] || log_info "\tAucune sandbox\n"
        return 0
    fi

    if ! _sandbox_is_created; then
        log_info "\tAucune sandbox $BB_SANDBOX_RELEASE\n"
    elif _sandbox_is_running; then
        log_info "\tSandbox Ubuntu $BB_SANDBOX_RELEASE démarrée (ssh -p $BB_SANDBOX_SSH_PORT $BB_SANDBOX_SSH_TARGET)\n"
    else
        log_info "\tSandbox Ubuntu $BB_SANDBOX_RELEASE arrêtée\n"
    fi
}

sandbox_help() {
    log_info "\tUsage: $0 [-r <release>] <commande> [arguments ...]

    \t  -r <release>            Instance visée (défaut $BB_SANDBOX_RELEASE). Une VM par release,
    \t                          utilisables en parallèle (port SSH 2<release> : 24.04 -> 22404)

    \t  create [<release>]      Créer la VM (image cloud vérifiée, cloud-init, snapshot \"$BB_SANDBOX_SNAPSHOT\")
    \t  start | stop            Démarrer / arrêter la VM
    \t  status                  Afficher l'état de la VM (de toutes les VM sans -r)
    \t  sync                    Copier le dépôt dans ~/Bigbox de la VM
    \t  run [--impl go] <args>  Synchroniser puis lancer ./bigbox <args> dans la VM ; avec --impl go,
    \t                          la Bigbox Go (construite sur l'hôte, installée en ~/bin/bigbox)
    \t  exec <commande>         Synchroniser puis lancer une commande dans ~/Bigbox de la VM
    \t  ssh                     Ouvrir un shell dans la VM
    \t  reset                   Revenir au snapshot \"$BB_SANDBOX_SNAPSHOT\" (Ubuntu vierge)
    \t  destroy                 Supprimer la VM (les images téléchargées sont conservées)

    \tVariables : BB_SANDBOX_DIR, BB_SANDBOX_RELEASE, BB_SANDBOX_CPUS (2), BB_SANDBOX_MEMORY (4G),
    \t            BB_SANDBOX_DISK_SIZE (20G), BB_SANDBOX_SSH_PORT_OVERRIDE\n"
}

main() {
    local release="" status_scope=all

    while [[ "${1:-}" == -r || "${1:-}" == --release ]]; do
        release="${2:?release attendue après -r}"
        status_scope=one
        shift 2
    done

    local command="${1:-help}"
    shift || true

    # Compatibilité : create <release>
    if [[ "$command" == create && -n "${1:-}" ]]; then
        release="$1"
        shift
    fi

    _sandbox_migrate_legacy
    _sandbox_configure "${release:-$BB_SANDBOX_RELEASE}"

    case "$command" in
        create)  sandbox_create ;;
        start)   sandbox_start ;;
        stop)    sandbox_stop ;;
        status)  sandbox_status "$status_scope" ;;
        sync)    sandbox_sync ;;
        run)     sandbox_run "$@" ;;
        exec)    sandbox_exec "$@" ;;
        ssh)     sandbox_ssh ;;
        reset)   sandbox_reset ;;
        destroy) sandbox_destroy ;;
        help|-h|--help) sandbox_help ;;
        *) log_error "Commande inconnue : $command\n"; sandbox_help; return 1 ;;
    esac
}

main "$@"
