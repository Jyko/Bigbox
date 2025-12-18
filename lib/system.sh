verify_ubuntu_version() {
    
    UBUNTU_MINI_VERSION=24
    UBUNTU_VERSION=$(lsb_release -rs)
    UBUNTU_MAJOR_VERSION=${UBUNTU_VERSION%%.*}

    # Vérification de la version Ubuntu
    if (( UBUNTU_MAJOR_VERSION < UBUNTU_MINI_VERSION )); then

        cat >&2 \
<<-EOF
    ❌ Une version majeure d'Ubuntu $UBUNTU_MINI_VERSION+ est requise

    ℹ️ La version majeure actuelle est $UBUNTU_VERSION
        
    🔄 Mettez à jour la version de la distribution Ubuntu
    sudo do-release-upgrade

    👍 Après la mise à jour, relancez ce script d'installation
EOF

        return 1
    fi

    return 0

}