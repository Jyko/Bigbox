#!/usr/bin/env bash
# shellcheck shell=bash

BB_DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
    docker-ce-rootless-extras
)

# Installer Docker
docker_install() {

    # Désinstaller les paquets qui pourraient entrer en conflit
    apt_wrapper remove docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc

    # Ajout de la clef GPG Docker
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    # Installation des packages
    apt_wrapper update
    apt_wrapper install "${BB_DOCKER_PACKAGES[@]}"

    # Ajouter l'utilisateur au groupe Docker, ne sera pris en compte qu'au prochain redémarrage du conteneur WSL2
    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"

    # Enregistrer le service Docker et le démarrer avec le conteneur WSL2 (et tout de suite :D)
    run_cmd sudo systemctl enable --now docker.service
    run_cmd sudo systemctl enable --now containerd.service

}

docker_uninstall() {

    apt_wrapper purge "${BB_DOCKER_PACKAGES[@]}"

    # Suppression des images, conteneurs, volumes ...
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd

    # Suppression du repository et de la GPG Docker
    sudo rm -f /etc/apt/sources.list.d/docker.sources
    sudo rm -f /etc/apt/keyrings/docker.asc

    # Supprimer le groupe docker
    if getent group docker >/dev/null 2>&1; then
        sudo groupdel docker
    fi

}

docker_stop() {
    run_cmd sudo systemctl stop docker.service
}

docker_start() {
    run_cmd sudo systemctl start docker
}

docker_upgrade() {

    if ! docker_verify; then
        docker_install
    else
        apt_wrapper update && \
            apt_wrapper install --only-upgrade "${BB_DOCKER_PACKAGES[@]}"
    fi
}

docker_verify() {

    command -v docker >/dev/null 2>&1

}