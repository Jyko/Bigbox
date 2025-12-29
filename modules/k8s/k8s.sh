#!/usr/bin/env bash
# shellcheck shell=bash

# METADATA du module
MODULE_NAME="k8s"
MODULE_PRIORITY=200

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

_k8s_generate_unified_configuration() {

    # Petit backup des familles avant toute chose
    if [ -f "$BB_K8S_STANDARD_FILE" ]; then
        cp -L "$BB_K8S_STANDARD_FILE" "$BB_K8S_BACKUP_FILE"
        rm -f "$BB_K8S_STANDARD_FILE"
    fi

    # Génération de la configuration unifiée
    # En cas de contexte identique, le dernier chargé prend la précédence, d'où l'ordre de passage en argument des fichiers dans KUBECONFIG.
    # Faut savoir que kubectl s'en bat les couilles des fichiers inexistants, pour lui c'est l'équivalent de config vide. Bien codé les outils de DEVOPS, on voit que c'est fait par des professionnels :+1:
    KUBECONFIG="$BB_K8S_STANDARD_FILE:$BB_K8S_BIGBOX_FILE" kutils_kubectl_wrapper config view --merge --flatten > "$BB_K8S_UNIFIED_FILE"

    # Symlink sur config.yaml, comme çà c'est propre et portable 👍
    ln -sf "$BB_K8S_UNIFIED_FILE" "$BB_K8S_STANDARD_FILE"

}

_k8s_configuration() {

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

    _k8s_generate_unified_configuration

}

_k8s_unconfiguration() {

    

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

# Installer microk8s et kubectx
k8s_install() {

    # --------------------
    # Installation de K3S
    # --------------------

    # Installation du noeud k3s via script officiel
    # Se reporter à https://docs.k3s.io/quick-start pour plus de détails, je suis pas venu pour souffrir.
    if ! command -v k3s >/dev/null 2>&1; then
        curl -sfL https://get.k3s.io | sudo sh -
    fi

    # --------------------
    # Installation des outils Kubernetes
    # --------------------

    # Kubectx
    apt_wrapper install kubectl kubectx helm

    # Kubecolor
    if ! command -v kubecolor >/dev/null 2>&1; then
        wget -O /tmp/kubecolor.deb "https://kubecolor.github.io/packages/deb/pool/main/k/kubecolor/kubecolor_$(wget -q -O- https://kubecolor.github.io/packages/deb/version)_$(dpkg --print-architecture).deb"
        sudo dpkg -i /tmp/kubecolor.deb
        apt_wrapper update
    fi

    # --------------------
    # Génération de la configuration unique et idempotent Kubernetes
    # --------------------
    _k8s_configuration

    # --------------------
    # Préparation du noeud Kubernetes
    # --------------------

    # Créer le namespace si celui-ci n'existe pas afin d'éviter les conflits et petit accident (coucou la PRD :D),
    # puis switch dedans (même si le wrapper forcera l'utilisation de ce dernier partout)
    kutils_kubectl_wrapper get namespace "$BB_K8S_NAMESPACE" >/dev/null 2>&1 || kutils_kubectl_wrapper create namespace "$BB_K8S_NAMESPACE"
    kutils_verify_kube_context

    # --------------------
    # Génération de la configuration des outils Kubernetes
    # --------------------

    # Installer et sourcer les aliases et de l'autocomplétion
    # install_dotfile "kubernetes_aliases.sh" "$BB_K8S_MODULE_NAME" "$BB_K8S_MODULE_DOTFILES_DIR"
    # install_dotfile "kubernetes_autocompletion.sh" "$BB_K8S_MODULE_NAME" "$BB_K8S_MODULE_DOTFILES_DIR"

    
}

k8s_uninstall() {

    _k8s_unconfiguration

    # Désinstaller le noeud k3s via son script, me demandez pas ce que çà fait, j'en sais rien.
    if [[ -f /usr/local/bin/k3s-uninstall.sh ]]; then
        sudo . /usr/local/bin/k3s-uninstall.sh
    fi
}

# A refléchir
# k8s_upgrade() { return 0 }

# k8s_start() { }

# k8s_stop() { }