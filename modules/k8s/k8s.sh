#!/usr/bin/env bash
# shellcheck shell=bash

BB_K8S_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_K8S_MODULE_DOTFILES_DIR="$BB_K8S_MODULE_BASE_DIR/dotfiles"

BB_K8S_KUBECTL_TIMEOUT="30"

BB_K8S_BIGBOX_FILE="$BB_K8S_CONFIG_DIR/bigbox.yaml"
BB_K8S_BACKUP_FILE="$BB_K8S_CONFIG_DIR/backup-config.yaml"
BB_K8S_STANDARD_FILE="$BB_K8S_CONFIG_DIR/config"
BB_K8S_UNIFIED_FILE="$BB_K8S_CONFIG_DIR/unified-configs.yaml"

# Gaffe avec ces trois propriétés, çà contrôle les noms attendus des contextes, users et clusters dans le fichier de configuration K8S.
BB_K8S_CONTEXT_NAME="bigbox"
BB_K8S_USER_NAME=bigbox
BB_K8S_CLUSTER_NAME=bigbox

BB_K8S_K3S_UNINSTALL_SCRIPT="/usr/local/bin/k3s-uninstall.sh"

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
        return 0
    fi

    run_cmd bash -c "curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE=644 sh -"

}

_k8s_k3s_uninstall() {

    # Désinstaller k3s via son script, me demandez pas ce que çà fait, j'en sais rien :DDD
    if _k8s_k3s_verify; then
        run_cmd sudo "$BB_K8S_K3S_UNINSTALL_SCRIPT"
    fi
}

# --------------------
# Kubernetes tools
# --------------------
_k8s_tools_verify() {
    for cmd in kubectl kubens kubectx helm kubecolor; do
        command -v $cmd >/dev/null 2>&1
    done
}

_k8s_tools_install() {

    if _k8s_tools_verify; then
        return 0
    fi

    # Kubectl, Kubectx et Helm
    apt_wrapper install kubectl kubectx helm

    # Kubecolor
    run_cmd wget -O /tmp/kubecolor.deb "https://kubecolor.github.io/packages/deb/pool/main/k/kubecolor/kubecolor_$(wget -q -O- https://kubecolor.github.io/packages/deb/version)_$(dpkg --print-architecture).deb"
    apt_wrapper install /tmp/kubecolor.deb
    rm -f /tmp/kubecolor.deb
}

_k8s_tools_uninstall() {
    apt_wrapper purge kubectl kubectx helm kubecolor || true
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
    if [ -f "$BB_K8S_STANDARD_FILE" ]; then
        cp -L "$BB_K8S_STANDARD_FILE" "$BB_K8S_BACKUP_FILE"
        rm -f "$BB_K8S_STANDARD_FILE"
    fi

    # Génération de la configuration unifiée
    # On appelle kubectl nature, sans wrapper.
    # En cas de contexte identique, le dernier chargé prend la précédence, d'où l'ordre de passage en argument des fichiers dans KUBECONFIG.
    # Kubectl considère un chemin de fichier null comme un fichier vide
    KUBECONFIG="$BB_K8S_STANDARD_FILE:$BB_K8S_BIGBOX_FILE" kubectl config view --merge --flatten > "$BB_K8S_UNIFIED_FILE"

    # Symlink sur config.yaml, comme çà c'est propre et portable 👍
    ln -sf "$BB_K8S_UNIFIED_FILE" "$BB_K8S_STANDARD_FILE"

    # Pour que les commandes kubectl, kubens, kubectx et helm suivantes rechargent la bonne configuration unifiée
    export KUBECONFIG="$BB_K8S_STANDARD_FILE"

}

_k8s_configuration_install() {

    # Créer le répertoire de configuration K8S ($HOME/.kube) et rendre $USER propriétaire
    mkdir -p "$BB_K8S_CONFIG_DIR"
    sudo chown -f -R "$USER" "$BB_K8S_CONFIG_DIR"

    # Copier le fichier de config de base k3s vers le dossier de conf $HOME/.kube
    sudo cp "/etc/rancher/k3s/k3s.yaml" "$BB_K8S_BIGBOX_FILE"
    sudo chown "$USER":"$USER" "$BB_K8S_BIGBOX_FILE"
    
    # Renommer le contexte, le user et le cluster k3s par défault pour éviter les conflits et effet de bord
    # TODO: C'est pas le plus solide ou le plus joli, mais çà fait le taff'.
    # Si les noms des clusters, users et contexts sont différents entre eux, il faut changer la méthode de modification et passer par JQ ou équivalent.
    sed -i "s/\bdefault\b/$BB_K8S_CONTEXT_NAME/g" "$BB_K8S_BIGBOX_FILE"

    # Maintenant que le fichier de configuration bigbox est prêt et idempotent, nous générons une nouvelle configuration unifiée
    _k8s_generate_unified_configuration
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
    sudo rm -f "$BB_K8S_BIGBOX_FILE"

    # Maintenant que la configuration actuelle et les fichiers la reflétant ne contiennent plus de trace de la Bigbox, nous recréons une configuration unifiée propre.
    _k8s_generate_unified_configuration

    # Nous ne supprimons rien d'autre dans le $HOME/.kube, pour laisser les confs ajoutées par l'utilisateur.
}

# --------------------
# Namespace Bigbox
# --------------------
_k8s_namespace_verify() {
    kutils_kubectl_wrapper get namespace "$BB_K8S_NAMESPACE" >/dev/null 2>&1 
    return $?
}

_k8s_namespace_install() {

    # Attendre que l'API Kubernetes soit prête avant de tenter des appels.
    if ! kutils_wait_api_available; then
        log_error "Le cluster Kubernetes et son API n'ont pas démarré correctement \n"
        return 2
    fi

    # Créer le namespace et switch dedans afin d'éviter les conflits et petit accident (coucou la PRD :D)
    if ! _k8s_namespace_verify; then
        kutils_kubectl_wrapper create namespace "$BB_K8S_NAMESPACE"
    fi

    kutils_verify_kube_context
}

_k8s_namespace_uninstall() {
    if _k8s_namespace_verify; then
        # Détruit le reste des ressources persistantes que les stacks auraient laissés (PVC, PV, ...)
        kutils_kubectl_wrapper delete namespace "$BB_K8S_NAMESPACE"
    fi
}

# --------------------
# Dotfiles
# --------------------
_k8s_dotfiles_install() {

    cfg_copy_dotfile "$BB_K8S_MODULE_DOTFILES_DIR/k8s_alias.sh"
    cfg_copy_dotfile "$BB_K8S_MODULE_DOTFILES_DIR/k8s_completion.sh"

}

_k8s_dotfiles_uninstall() {

    cfg_delete_dotfile "k8s_alias.sh"
    cfg_delete_dotfile "k8s_completion.sh"

}


# A refléchir, çà à l'air tricky
# k8s_upgrade() { return 0 ; }

# Trop d'effet de bord à arrêter k3s et ses services, c'est ultra-galère à redémarrer à la main.
# k8s_stop() { return 0 ; }
# k8s_start() { return 0 ; }