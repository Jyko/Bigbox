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

# Packages conflictuels désinstallés
BB_DOCKER_CONFLICT_PACKAGES=(
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    podman-docker
    containerd
    runc
)

# Installer Docker
docker_install() {

    # Désinstaller les paquets qui pourraient entrer en conflit
    apt_wrapper purge "${BB_DOCKER_CONFLICT_PACKAGES[@]}" || true

    # Nous vérifions après la purge des packages conflictuels si docker est bien installé
    if _docker_verify; then
        return 0
    fi

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

    # Pas besoin de verify, tout est idempotent dans les commandes de suppression

    # Nous supprimons les packages installés et les potentiels packages à conflit pour qu'une future installation se fasse sur des bases saines
    apt_wrapper purge "${BB_DOCKER_PACKAGES[@]}" "${BB_DOCKER_CONFLICT_PACKAGES[@]}" || true

    # Suppression des images, conteneurs, volumes ...
    sudo rm -rf /var/lib/docker
    sudo rm -rf /var/lib/containerd

    # Suppression du repository et de la GPG Docker
    sudo rm -f /etc/apt/sources.list.d/docker.sources
    sudo rm -f /etc/apt/keyrings/docker.asc
    apt_wrapper update

    # Supprimer le groupe docker
    if getent group docker >/dev/null 2>&1; then
        sudo groupdel docker
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