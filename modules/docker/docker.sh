# METADATA du module
MODULE_NAME="docker"
MODULE_PRIORITY=100

# Installer Docker
docker_install() {

    snap_wrapper install docker

    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"

}

docker_uninstall() {
    
    snap_wrapper remove docker

    # Supprimer le group docker
    if getent group docker >/dev/null 2>&1; then
        sudo groupdel docker
    fi

}

docker_upgrade() {

    snap_wrapper refresh docker
    
}