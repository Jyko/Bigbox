# METADATA du module
MODULE_NAME="system"
MODULE_PRIORITY=-100

# Version minimale d'Ubuntu compatible avec la BigBox
BB_SYSTEM_UBUNTU_MIN_VERSION=24

# Vérification des basiques
system_install() {

    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_major_version=${ubuntu_version%%.*}

    # Vérification de la version Ubuntu
    if (( ubuntu_major_version < BB_SYSTEM_UBUNTU_MIN_VERSION )); then

        cat >&2 \
<<-EOF
    ❌ Une version majeure d'Ubuntu $BB_SYSTEM_UBUNTU_MIN_VERSION+ est requise

    ℹ️ La version majeure actuelle est $ubuntu_major_version
        
    🔄 Mettez à jour la version de la distribution Ubuntu
    sudo do-release-upgrade

    👍 Après la mise à jour, relancez ce script d'installation
EOF

        return 1
    fi

    return 0

}

# Pas de désinstallation système
# system_uninstall() { }

# TODO : Je propose un do-upgrade-version ? C'est tendax quand même, bcp de bordel à gérer.
# system_upgrade() { }