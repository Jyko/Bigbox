#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

#################################################################################
# Sandbox QEMU/KVM pour développer et tester la Bigbox sans toucher au poste hôte.
#
# La Bigbox modifie réellement la machine sur laquelle elle tourne (.bashrc, .config,
# apt, systemd ...). Ce script crée une VM Ubuntu jetable dans laquelle la lancer.
#
# Usage : tools/sandbox/sandbox.sh <commande> [arguments ...]
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
BB_SANDBOX_SSH_PORT="${BB_SANDBOX_SSH_PORT:-2222}"
BB_SANDBOX_CPUS="${BB_SANDBOX_CPUS:-4}"
BB_SANDBOX_MEMORY="${BB_SANDBOX_MEMORY:-8G}"
BB_SANDBOX_DISK_SIZE="${BB_SANDBOX_DISK_SIZE:-40G}"
BB_SANDBOX_DEFAULT_RELEASE="24.04"
BB_SANDBOX_USER="bigbox"
BB_SANDBOX_SNAPSHOT="pristine"
BB_SANDBOX_BOOT_TIMEOUT=300

BB_SANDBOX_VM_DIR="$BB_SANDBOX_DIR/vm"
BB_SANDBOX_OVERLAY="$BB_SANDBOX_VM_DIR/overlay.qcow2"
BB_SANDBOX_SSH_KEY="$BB_SANDBOX_VM_DIR/id_ed25519"
BB_SANDBOX_PID_FILE="$BB_SANDBOX_VM_DIR/qemu.pid"
BB_SANDBOX_CONSOLE_LOG="$BB_SANDBOX_VM_DIR/console.log"
BB_SANDBOX_SEED_DIR="$BB_SANDBOX_VM_DIR/seed"

BB_SANDBOX_SSH_OPTS=(
    -i "$BB_SANDBOX_SSH_KEY"
    -p "$BB_SANDBOX_SSH_PORT"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=5
)
BB_SANDBOX_SSH_TARGET="$BB_SANDBOX_USER@127.0.0.1"

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
        log_error "Aucune sandbox, lancez d'abord : $0 create\n"
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
    log_success "\r\t✅ Sandbox joignable en SSH\n"
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
instance-id: bigbox-sandbox
local-hostname: bigbox-sandbox
EOF

    cat > "$BB_SANDBOX_SEED_DIR/user-data" <<EOF
#cloud-config
users:
  - name: $BB_SANDBOX_USER
    shell: /bin/bash
    groups: [sudo]
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
    local release="${1:-$BB_SANDBOX_DEFAULT_RELEASE}"

    _sandbox_require_tools

    if _sandbox_is_created; then
        log_error "Une sandbox existe déjà, lancez \`$0 destroy\` avant d'en recréer une\n"
        return 1
    fi

    mkdir -p "$BB_SANDBOX_VM_DIR"
    chmod 700 "$BB_SANDBOX_DIR" "$BB_SANDBOX_VM_DIR"

    local image_path
    image_path=$(_sandbox_download_image "$release")

    # Overlay jetable : l'image de base n'est jamais modifiée
    qemu-img create -q -f qcow2 -F qcow2 -b "$image_path" "$BB_SANDBOX_OVERLAY" "$BB_SANDBOX_DISK_SIZE"
    echo "$release" > "$BB_SANDBOX_VM_DIR/release"

    ssh-keygen -q -t ed25519 -N "" -C "bigbox-sandbox" -f "$BB_SANDBOX_SSH_KEY"

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
        log_error "cloud-init a échoué, voir \`$0 ssh\` puis /var/log/cloud-init-output.log\n"
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
    log_success "\t✅ Sandbox arrêtée\n"
}

sandbox_sync() {
    _sandbox_assert_created
    _sandbox_is_running || _sandbox_boot

    rsync -a --delete \
        --exclude ".idea/" \
        -e "ssh ${BB_SANDBOX_SSH_OPTS[*]}" \
        "$BB_SANDBOX_REPO_DIR/" "$BB_SANDBOX_SSH_TARGET:Bigbox/"
}

# Exécuter la Bigbox DANS la sandbox
# $@ : Arguments de la Bigbox
sandbox_run() {
    sandbox_sync
    _sandbox_exec "cd ~/Bigbox && ./bigbox $(printf '%q ' "$@")"
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
    log_success "\t✅ Sandbox revenue au snapshot \"$BB_SANDBOX_SNAPSHOT\"\n"
}

sandbox_destroy() {
    sandbox_stop
    # Les images de base téléchargées sont conservées pour une prochaine création
    rm -rf "${BB_SANDBOX_VM_DIR:?}"
    log_success "\t✅ Sandbox supprimée\n"
}

sandbox_status() {
    if ! _sandbox_is_created; then
        log_info "\tAucune sandbox\n"
    elif _sandbox_is_running; then
        log_info "\tSandbox Ubuntu $(<"$BB_SANDBOX_VM_DIR/release") démarrée (ssh -p $BB_SANDBOX_SSH_PORT $BB_SANDBOX_SSH_TARGET)\n"
    else
        log_info "\tSandbox Ubuntu $(<"$BB_SANDBOX_VM_DIR/release") arrêtée\n"
    fi
}

sandbox_help() {
    log_info "\tUsage: $0 <commande> [arguments ...]

    \t  create [24.04|26.04]    Créer la VM (image cloud vérifiée, cloud-init, snapshot \"$BB_SANDBOX_SNAPSHOT\")
    \t  start | stop            Démarrer / arrêter la VM
    \t  status                  Afficher l'état de la VM
    \t  sync                    Copier le dépôt dans ~/Bigbox de la VM
    \t  run <args ...>          Synchroniser puis lancer ./bigbox <args> dans la VM
    \t  exec <commande>         Synchroniser puis lancer une commande dans ~/Bigbox de la VM
    \t  ssh                     Ouvrir un shell dans la VM
    \t  reset                   Revenir au snapshot \"$BB_SANDBOX_SNAPSHOT\" (Ubuntu vierge)
    \t  destroy                 Supprimer la VM (les images téléchargées sont conservées)

    \tVariables : BB_SANDBOX_DIR, BB_SANDBOX_SSH_PORT, BB_SANDBOX_CPUS, BB_SANDBOX_MEMORY, BB_SANDBOX_DISK_SIZE\n"
}

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        create)  sandbox_create "$@" ;;
        start)   sandbox_start ;;
        stop)    sandbox_stop ;;
        status)  sandbox_status ;;
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
