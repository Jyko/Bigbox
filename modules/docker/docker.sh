#!/usr/bin/env bash
# shellcheck shell=bash

# Packages gérés
BB_DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
    docker-ce-rootless-extras
)

# Packages en conflit avec docker-ce, désinstallés avant son installation
BB_DOCKER_CONFLICT_PACKAGES=(
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    podman-docker
    containerd
    runc
)

BB_DOCKER_APT_KEY_FILE="/etc/apt/keyrings/docker.asc"
BB_DOCKER_APT_SOURCE_FILE="/etc/apt/sources.list.d/docker.sources"

# Installer Docker
docker_install() {

    # Un Docker déjà présent (docker.io, Docker Desktop ...) est respecté : ni purge, ni réinstallation
    if _docker_verify; then
        return 0
    fi

    # Désinstaller les paquets en conflit avec docker-ce (containerd, runc ... installés sans Docker)
    local conflict
    for conflict in "${BB_DOCKER_CONFLICT_PACKAGES[@]}"; do
        if apt_is_installed "$conflict"; then
            apt_wrapper purge "$conflict"
        fi
    done

    # Ajout de la clef GPG et du dépôt Docker (conservés en l'état s'ils existent déjà)
    sudo install -m 0755 -d /etc/apt/keyrings
    curl "${BB_CURL_OPTS[@]}" https://download.docker.com/linux/ubuntu/gpg | state_create_file "$BB_DOCKER_APT_KEY_FILE"
    sudo chmod a+r "$BB_DOCKER_APT_KEY_FILE"

    local codename
    codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    printf '%s\n' \
        "Types: deb" \
        "URIs: https://download.docker.com/linux/ubuntu" \
        "Suites: $codename" \
        "Components: stable" \
        "Signed-By: $BB_DOCKER_APT_KEY_FILE" \
        | state_create_file "$BB_DOCKER_APT_SOURCE_FILE"

    # Le groupe docker est créé par le paquet docker-ce : son absence se constate AVANT l'install
    if ! getent group docker >/dev/null 2>&1; then
        state_mark_owned "group:docker"
    fi

    # Installation des packages
    apt_wrapper update
    apt_install "${BB_DOCKER_PACKAGES[@]}"

    # Ajouter l'utilisateur au groupe Docker, ne sera pris en compte qu'au prochain redémarrage du conteneur WSL2
    if ! getent group docker >/dev/null 2>&1; then
        sudo groupadd docker
    fi
    sudo usermod -aG docker "$USER"

    # Enregistrer le service Docker et le démarrer avec le conteneur WSL2 (et tout de suite :D)
    run_cmd sudo systemctl enable --now docker.service
    run_cmd sudo systemctl enable --now containerd.service

}

docker_uninstall() {

    # Rien n'est touché si Docker n'a pas été installé par la Bigbox (Docker préexistant)
    if ! state_is_owned "apt:docker-ce"; then
        log_debug "Docker n'a pas été installé par la Bigbox, il est conservé \n"
        return 0
    fi

    apt_purge_owned "${BB_DOCKER_PACKAGES[@]}" || true

    # Suppression des images, conteneurs, volumes ... du Docker installé par la Bigbox
    sudo rm -rf /var/lib/docker /var/lib/containerd

    state_remove_owned_files "$BB_DOCKER_APT_SOURCE_FILE" "$BB_DOCKER_APT_KEY_FILE"

    if state_is_owned "group:docker"; then
        if getent group docker >/dev/null 2>&1; then
            sudo groupdel docker
        fi
        state_unmark "group:docker"
    fi

}

_docker_verify() {
    command -v docker >/dev/null 2>&1
}

# Les upgrades sont à réfléchir, les stratégies de verify/upgrade ou de uninstall/install sont à méditer
# docker_upgrade() { return 0 ;}

# Trop d'effet de bord à arrêter les services docker et containerd, c'est ultra-galère à redémarrer à la main.
# Pour les quelques Mo de RAM que çà bouffe, on va pas pinailler. Et çà permet d'éviter l'overhead lors d'un réveil de docker.
# docker_stop() { return 0 ; }
# docker_start() { return 0 ; }
