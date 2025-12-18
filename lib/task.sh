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

    # Des alias et de l'autocomplétion parce que sinon on s'emmerde !
    create_configuration_file "$BB_CFG_FILE_ALIAS" "$SCRIPT_DIR/lib/.config/$BB_CFG_FILE_ALIAS"
    create_configuration_file "$BB_CFG_FILE_AUTOCOMPLETION" "$SCRIPT_DIR/lib/.config/$BB_CFG_FILE_AUTOCOMPLETION"

    add_to_bashrc "$BB_CFG_FILE_ALIAS"
    add_to_bashrc "$BB_CFG_FILE_AUTOCOMPLETION"

    source "$HOME/.bashrc"

}