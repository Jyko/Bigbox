#!/usr/bin/env bash
# shellcheck shell=bash

BB_K8S_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_K8S_MODULE_DOTFILES_DIR="$BB_K8S_MODULE_BASE_DIR/dotfiles"

BB_K8S_BIGBOX_FILE="$BB_K8S_CONFIG_DIR/bigbox.yaml"
BB_K8S_BACKUP_FILE="$BB_K8S_CONFIG_DIR/backup-config.yaml"
BB_K8S_STANDARD_FILE="$BB_K8S_CONFIG_DIR/config"
BB_K8S_UNIFIED_FILE="$BB_K8S_CONFIG_DIR/unified-configs.yaml"

# Gaffe avec ces trois propriétés, çà contrôle les noms attendus des contextes, users et clusters dans le fichier de configuration K8S.
BB_K8S_CONTEXT_NAME="bigbox"
BB_K8S_USER_NAME=bigbox
BB_K8S_CLUSTER_NAME=bigbox

BB_K8S_K3S_UNINSTALL_SCRIPT="/usr/local/bin/k3s-uninstall.sh"
BB_K8S_K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

# Versions épinglées (kubectl doit rester à une version mineure près de celle de k3s)
BB_K8S_K3S_VERSION="v1.37.2+k3s1"
BB_K8S_KUBECTL_MINOR_VERSION="v1.37"
BB_K8S_KUBECOLOR_VERSION="0.8.0"

BB_K8S_KUBERNETES_APT_KEY_FILE="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
BB_K8S_KUBERNETES_APT_SOURCE_FILE="/etc/apt/sources.list.d/kubernetes.list"
BB_K8S_HELM_APT_KEY_FILE="/usr/share/keyrings/helm.gpg"
BB_K8S_HELM_APT_SOURCE_FILE="/etc/apt/sources.list.d/helm-stable-debian.list"

k8s_install() {

    _k8s_k3s_install
    _k8s_tools_install
    _k8s_configuration_install
    _k8s_namespace_install
    _k8s_dotfiles_install
    
}

k8s_uninstall() {

    _k8s_dotfiles_uninstall
    _k8s_namespace_uninstall
    _k8s_configuration_uninstall
    _k8s_tools_uninstall
    _k8s_k3s_uninstall
}

# --------------------
# K3S
# --------------------
_k8s_k3s_verify() {
    command -v k3s >/dev/null 2>&1 && [[ -f "$BB_K8S_K3S_UNINSTALL_SCRIPT" ]]
}

_k8s_k3s_install() {

    if _k8s_k3s_verify; then
        _k8s_k3s_remove_kubectl_symlink
        return 0
    fi

    # Le script est téléchargé puis exécuté, sans pipe vers sh : un téléchargement interrompu
    # ne peut pas exécuter un script tronqué. La version de k3s est épinglée, le script vérifie
    # lui-même la somme SHA256 du binaire.
    # K3S_KUBECONFIG_MODE=600 : le kubeconfig admin du cluster n'est lisible que par root.
    # INSTALL_K3S_SYMLINK=skip : pas de /usr/local/bin/kubectl -> k3s, prioritaire dans le PATH sur le kubectl
    # installé par la Bigbox et qui, sans KUBECONFIG, lit /etc/rancher/k3s/k3s.yaml au lieu de ~/.kube/config.
    local tmp
    tmp=$(mktemp -d)
    run_cmd curl "${BB_CURL_OPTS[@]}" -o "$tmp/k3s-install.sh" https://get.k3s.io
    run_cmd env \
        INSTALL_K3S_VERSION="$BB_K8S_K3S_VERSION" \
        INSTALL_K3S_SYMLINK=skip \
        K3S_KUBECONFIG_MODE=600 \
        sh "$tmp/k3s-install.sh"
    rm -rf "${tmp:?}"

    state_mark_owned "k3s"

}

# Supprimer le lien kubectl -> k3s laissé par une installation antérieure de k3s (voir INSTALL_K3S_SYMLINK)
_k8s_k3s_remove_kubectl_symlink() {
    local link="/usr/local/bin/kubectl"
    if [[ -L "$link" && "$(readlink "$link")" == *k3s ]]; then
        sudo rm -f "$link"
    fi
}

_k8s_k3s_uninstall() {

    # Un k3s présent avant la Bigbox n'est jamais désinstallé
    if ! state_is_owned "k3s"; then
        log_debug "k3s n'a pas été installé par la Bigbox, il est conservé \n"
        return 0
    fi

    # Désinstaller k3s via le script fourni par son installeur (binaires, services, données du cluster)
    if _k8s_k3s_verify; then
        run_cmd sudo "$BB_K8S_K3S_UNINSTALL_SCRIPT"
    fi

    # Restes laissés par le script : cgroups vides des pods, mot de passe du noeud, répertoires parents.
    # rmdir --ignore-fail-on-non-empty : on ne supprime /etc/rancher et /var/lib/rancher que s'ils sont vides.
    sudo systemctl stop kubepods.slice >/dev/null 2>&1 || true
    sudo rm -rf /etc/rancher/node
    sudo rmdir --ignore-fail-on-non-empty /etc/rancher /var/lib/rancher 2>/dev/null || true

    state_unmark "k3s"
}

# --------------------
# Kubernetes tools
# --------------------
_k8s_tools_verify() {
    local cmd
    for cmd in kubectl kubens kubectx helm kubecolor; do
        command -v "$cmd" >/dev/null 2>&1 || return 1
    done
}

_k8s_tools_install() {

    if _k8s_tools_verify; then
        return 0
    fi

    # Ajouter les dépôts officiels Kubernetes et Helm (conservés en l'état s'ils existent déjà)
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl "${BB_CURL_OPTS[@]}" "https://pkgs.k8s.io/core:/stable:/$BB_K8S_KUBECTL_MINOR_VERSION/deb/Release.key" \
        | gpg --batch --dearmor | state_create_file "$BB_K8S_KUBERNETES_APT_KEY_FILE"
    echo "deb [signed-by=$BB_K8S_KUBERNETES_APT_KEY_FILE] https://pkgs.k8s.io/core:/stable:/$BB_K8S_KUBECTL_MINOR_VERSION/deb/ /" \
        | state_create_file "$BB_K8S_KUBERNETES_APT_SOURCE_FILE"

    curl "${BB_CURL_OPTS[@]}" https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
        | gpg --batch --dearmor | state_create_file "$BB_K8S_HELM_APT_KEY_FILE"
    echo "deb [signed-by=$BB_K8S_HELM_APT_KEY_FILE] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
        | state_create_file "$BB_K8S_HELM_APT_SOURCE_FILE"
    sudo chmod 644 "$BB_K8S_KUBERNETES_APT_KEY_FILE" "$BB_K8S_KUBERNETES_APT_SOURCE_FILE" "$BB_K8S_HELM_APT_KEY_FILE" "$BB_K8S_HELM_APT_SOURCE_FILE"

    # Mettre à jour la liste des répos avant d'installer les outils
    apt_wrapper update

    # Kubectl, Kubectx et Helm
    apt_install kubectl kubectx helm

    # Kubecolor : version épinglée, téléchargée dans un répertoire temporaire privé
    # (et non dans /tmp/kubecolor.deb, un chemin prévisible exposé aux attaques par lien symbolique)
    local tmp arch
    arch=$(dpkg --print-architecture)
    tmp=$(mktemp -d)
    run_cmd curl "${BB_CURL_OPTS[@]}" -o "$tmp/kubecolor.deb" \
        "https://github.com/kubecolor/kubecolor/releases/download/v$BB_K8S_KUBECOLOR_VERSION/kubecolor_${BB_K8S_KUBECOLOR_VERSION}_linux_${arch}.deb"
    apt_install "$tmp/kubecolor.deb"
    rm -rf "${tmp:?}"
}

_k8s_tools_uninstall() {
    # La purge de kubecolor retire aussi son dépôt (kubecolor.sources appartient au paquet)
    apt_purge_owned kubectl kubectx helm kubecolor || true

    state_remove_owned_files \
        "$BB_K8S_KUBERNETES_APT_SOURCE_FILE" "$BB_K8S_KUBERNETES_APT_KEY_FILE" \
        "$BB_K8S_HELM_APT_SOURCE_FILE" "$BB_K8S_HELM_APT_KEY_FILE"
}

# --------------------
# Kube configuration
# --------------------
_k8s_generate_unified_configuration() {

    # Sans kubectl, impossible de générer une nouvelle configuration unifié, nous laissons donc en l'état
    # FIXME : Ce cas n'arrive que si nous jouons deux uninstall d'affilés, donc on devrait être couvert, mais sait-on jamais.
    if ! command -v kubectl >/dev/null 2>&1; then
        return 0
    fi

    # Petit backup des familles avant toute chose
    if [[ -f "$BB_K8S_STANDARD_FILE" ]]; then
        cp -L "$BB_K8S_STANDARD_FILE" "$BB_K8S_BACKUP_FILE"
        chmod 600 "$BB_K8S_BACKUP_FILE"
        rm -f "$BB_K8S_STANDARD_FILE"
    fi

    # Génération de la configuration unifiée
    # On appelle kubectl nature, sans wrapper.
    # En cas de contexte identique, le dernier chargé prend la précédence, d'où l'ordre de passage en argument des fichiers dans KUBECONFIG.
    # Kubectl considère un chemin de fichier null comme un fichier vide
    # umask 077 : la configuration unifiée contient les identifiants de tous les clusters de l'utilisateur
    (umask 077 && KUBECONFIG="$BB_K8S_BACKUP_FILE:$BB_K8S_BIGBOX_FILE" kubectl config view --merge --flatten > "$BB_K8S_UNIFIED_FILE")

    # Symlink sur config.yaml, comme çà c'est propre et portable 👍
    ln -sf "$BB_K8S_UNIFIED_FILE" "$BB_K8S_STANDARD_FILE"

    # Pour que les commandes kubectl, kubens, kubectx et helm suivantes rechargent la bonne configuration unifiée
    export KUBECONFIG="$BB_K8S_STANDARD_FILE"

}

_k8s_configuration_install() {

    # Créer le répertoire de configuration K8S ($HOME/.kube) et rendre $USER propriétaire
    mkdir -p "$BB_K8S_CONFIG_DIR"
    chmod 700 "$BB_K8S_CONFIG_DIR"
    sudo chown -f -R "$USER" "$BB_K8S_CONFIG_DIR"

    # Renommer le contexte, le user et le cluster k3s par défaut ("default") pour éviter les conflits et effets de bord.
    # kubectl convertit le kubeconfig de k3s en JSON, et jq ne modifie que les champs concernés,
    # contrairement à un sed qui remplacerait tous les mots "default" du fichier.
    # (Le yq des dépôts Ubuntu est le wrapper Python de jq, pas celui de mikefarah : nous ne nous en servons pas ici.)
    # kubectl lit indifféremment un kubeconfig YAML ou JSON. umask 077 : fichier lisible uniquement par $USER.
    (
        umask 077
        sudo cat "$BB_K8S_K3S_KUBECONFIG" \
            | KUBECONFIG=/dev/stdin kubectl config view --raw -o json \
            | jq \
                --arg cluster "$BB_K8S_CLUSTER_NAME" \
                --arg user "$BB_K8S_USER_NAME" \
                --arg context "$BB_K8S_CONTEXT_NAME" '
                (.clusters[] | select(.name == "default") | .name) = $cluster |
                (.users[] | select(.name == "default") | .name) = $user |
                (.contexts[] | select(.name == "default") | .context.cluster) = $cluster |
                (.contexts[] | select(.name == "default") | .context.user) = $user |
                (.contexts[] | select(.name == "default") | .name) = $context |
                .["current-context"] = $context
            ' > "$BB_K8S_BIGBOX_FILE"
    )
    chmod 600 "$BB_K8S_BIGBOX_FILE"

    # Maintenant que le fichier de configuration bigbox est prêt et idempotent, nous générons une nouvelle configuration unifiée
    _k8s_generate_unified_configuration

    kubectx "$BB_K8S_CONTEXT"
}

# Désinstaller la configuration bigbox mais conserver les autres
_k8s_configuration_uninstall() {

    # Supprimer ces entrées dans la configuration courante (unified-configs.yaml) via l'outil le plus propre pour la tâche : kubectl config.
    if kubectl config get-contexts "$BB_K8S_CONTEXT_NAME" >/dev/null 2>&1; then
        kutils_kubectl_wrapper config delete-context "$BB_K8S_CONTEXT_NAME"
        kutils_kubectl_wrapper config delete-cluster "$BB_K8S_CLUSTER_NAME"
        kutils_kubectl_wrapper config delete-user "$BB_K8S_USER_NAME"
    fi

    # Supprimer le fichier de configuration Bigbox
    rm -f "$BB_K8S_BIGBOX_FILE"

    # Maintenant que la configuration actuelle et les fichiers la reflétant ne contiennent plus de trace de la Bigbox, nous recréons une configuration unifiée propre.
    _k8s_generate_unified_configuration

    # S'il ne reste aucun contexte, l'utilisateur n'avait pas de configuration Kubernetes avant la Bigbox :
    # nous retirons les fichiers que nous avons créés. Sinon nous laissons ses configurations en l'état.
    if [[ -z "$(KUBECONFIG="$BB_K8S_STANDARD_FILE" kubectl config get-contexts -o name 2>/dev/null)" ]]; then
        rm -f "$BB_K8S_STANDARD_FILE" "$BB_K8S_UNIFIED_FILE" "$BB_K8S_BACKUP_FILE"
    fi
}

# --------------------
# Namespace Bigbox
# --------------------
_k8s_namespace_verify() {
    kutils_kubectl_wrapper get namespace "$BB_K8S_NAMESPACE" >/dev/null 2>&1
}

_k8s_namespace_install() {

    # Attendre que l'API Kubernetes soit prête avant de tenter des appels.
    if ! kutils_wait_api_available; then
        log_error "Le cluster Kubernetes et son API n'ont pas démarré correctement \n"
        return 2
    fi

    # Créer le namespace et switch dedans afin d'éviter les conflits et petit accident (coucou la PRD :D)
    if ! _k8s_namespace_verify; then
        run_cmd kutils_kubectl_wrapper create namespace "$BB_K8S_NAMESPACE"
        state_mark_owned "k8s-namespace:$BB_K8S_NAMESPACE"
    fi

    run_cmd kutils_verify_kube_context
}

_k8s_namespace_uninstall() {
    if state_is_owned "k8s-namespace:$BB_K8S_NAMESPACE" && _k8s_namespace_verify; then
        # --wait=false : kubectl attend sinon (sans limite) la finalisation de tout le contenu du namespace,
        # y compris l'arrêt des pods des releases tout juste désinstallées. Inutile : si k3s appartient à la
        # Bigbox, il est détruit juste après par k3s-uninstall.sh ; sinon le cluster finit la suppression seul.
        run_cmd kutils_kubectl_wrapper delete namespace "$BB_K8S_NAMESPACE" --wait=false
    fi
    state_unmark "k8s-namespace:$BB_K8S_NAMESPACE"
}

# --------------------
# Dotfiles
# --------------------
_k8s_dotfiles_install() {

    cfg_copy_dotfile "$BB_K8S_MODULE_DOTFILES_DIR/k8s_alias.sh"
    cfg_copy_dotfile "$BB_K8S_MODULE_DOTFILES_DIR/k8s_completion.sh"
    cfg_copy_dotfile "$BB_K8S_MODULE_DOTFILES_DIR/k8s_env.sh"

}

_k8s_dotfiles_uninstall() {

    cfg_delete_dotfile "k8s_alias.sh"
    cfg_delete_dotfile "k8s_completion.sh"
    cfg_delete_dotfile "k8s_env.sh"

}


# À réfléchir, ça a l'air tricky
# k8s_upgrade() { return 0 ; }

k8s_start() {
    run_cmd sudo systemctl start k3s
    if ! kutils_wait_api_available; then
        log_error "Le cluster Kubernetes et son API n'ont pas démarré correctement \n"
        return 2
    fi
}

k8s_stop() {
    run_cmd sudo systemctl stop k3s
}
