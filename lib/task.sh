# Installer Snapd
install_snapd() {

    apt_wrapper install -y snapd
    snap version
    
}

# Installer Docker
install_docker() {

    snap_wrapper install docker

}

# Configurer Docker
configure_docker() {

    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"

    sudo snap restart docker

}

# Installer microk8s et kubectx
install_microk8s() {

    snap_wrapper install microk8s --classic

    # Ajouter le $USER au groupe pour ne plus avoir à sudo
    sudo usermod -a -G microk8s $USER

    # Créer le répertoire de configuration K8S et rendre $USER propriétaire
    mkdir -p ~/.kube
    sudo chown -f -R $USER ~/.kube

}

install_k8s_tools() {

    snap_wrapper install kubectl --classic

    # Kubectx pour les switch context facile
    apt_wrapper install -y kubectx

    # Helm, meme si je le déteste
    snap_wrapper install helm --classic

    # Kubecolor parce qu'on aime la couleur ici !
    if ! command -v kubecolor >/dev/null 2>&1; then
        wget -O /tmp/kubecolor.deb https://kubecolor.github.io/packages/deb/pool/main/k/kubecolor/kubecolor_$(wget -q -O- https://kubecolor.github.io/packages/deb/version)_$(dpkg --print-architecture).deb
        sudo dpkg -i /tmp/kubecolor.deb
        apt_wrapper update
    fi

}

configure_k8s_tools() {

    local category="kubernetes"

    local k8s_aliases_fn="kubernetes_aliases.sh"
    install_dotfile "$k8s_aliases_fn" "$category" 
    source_dotfile "$k8s_aliases_fn" "$category" 

    local k8s_autocompletion_fn="kubernetes_autocompletion.sh"
    install_dotfile "$k8s_autocompletion_fn" "$category" 
    source_dotfile "$k8s_autocompletion_fn" "$category" 

    ############################################
    # CONFIGURATION du $HOME/.kube/config.yaml #
    ############################################
    local kube_dir="$HOME/.kube"
    local standard_file="$kube_dir/config"
    local unified_file="$kube_dir/unified-configs.yaml"
    local backup_file="$kube_dir/backup-config.yaml"
    local bigbox_file="$kube_dir/bigbox.yaml"

    # Backup des anciennes configurations et des symlinks si il en existe
    if [ -f "$standard_file" ] && [ ! -L "$standard_file" ]; then
        mv "$standard_file" "$backup_file"
    fi

    # Est-ce qu'il existe déjà un contexte BigBox dans l'ancienne configuration ?
    local need_merge=1
    local bigbox_context="bigbox"

    if sudo kubectl --kubeconfig="$backup_file" config get-contexts -o name 2>&1 \
        | grep -q "^$bigbox_context$"; then

        # Pas besoin de merge l'ancienne configuration avec une nouvelle, le contexte bigbox est déjà configuré
        echo "▬ Le contexte $bigbox_context est déjà présent dans l'ancienne configuration Kubenertes"
        need_merge=1
    else
        # Il va falloir merge l'ancienne configuration avec une nouvelle pour y ajouter le contexte bigbox
        echo "✚ Le contexte $bigbox_context n'existe pas dans l'ancienne configuration Kubenertes"
        need_merge=0

        # Générer le fichier de configuration
        sudo microk8s config > "$bigbox_file"
        # Renommer le contexte pour éviter les conflits et éviter les duplicats
        sudo kubectl --kubeconfig="$bigbox_file" config rename-context microk8s "$bigbox_context"
    fi

    # Génération de la configuration unifiée avec ou sans merge
    KUBECONFIG="$backup_file${need_merge:+:$bigbox_file}" kubectl config view --merge --flatten > "$unified_file"

    # Symlink sur config.yaml, comme çà c'est propre et portable 👍
    ln -sf "$unified_file" "$standard_file"

}