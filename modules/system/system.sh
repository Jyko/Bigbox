# METADATA du module
MODULE_NAME="system"
MODULE_PRIORITY=-100

# Version minimale d'Ubuntu compatible avec la BigBox
BB_SYSTEM_UBUNTU_MIN_VERSION=24
BB_SYSTEM_WSL_CONF_PATH="/etc/wsl.conf"

# Vérification des basiques
system_verify() {

    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_major_version=${ubuntu_version%%.*}

    # Vérification de la version Ubuntu
    if (( ubuntu_major_version < BB_SYSTEM_UBUNTU_MIN_VERSION )); then

        log_error "
        ❌ Une version majeure d'Ubuntu $BB_SYSTEM_UBUNTU_MIN_VERSION+ est requise

        ℹ️ La version majeure actuelle est $ubuntu_major_version
        
        🔄 Mettez à jour la version de la distribution Ubuntu
        \tsudo do-release-upgrade

        👍 Après la mise à jour, relancez ce script d'installation
        "

        return 1

    else
        log_debug "
        La version actuelle d'Ubuntu $ubuntu_major_version est supérieure à celle nécessaire $BB_SYSTEM_UBUNTU_MIN_VERSION
        "
    fi

}

system_install() {

    system_verify

    # Crée le fichier s'il n'existe pas
    if [[ ! -f "$BB_SYSTEM_WSL_CONF_PATH" ]]; then
        run_cmd sudo touch "$BB_SYSTEM_WSL_CONF_PATH"
    fi

    # Vérifie si systemd est déjà activé
    if ! grep -q "systemd *= *true" "$BB_SYSTEM_WSL_CONF_PATH"; then

        file_append $BB_SYSTEM_WSL_CONF_PATH <<EOF
# Activer systemd pour certains outils de la Bigbox
[boot]
systemd=true
EOF

        log_success "
        Systemd est activé
        "
        log_warn "
        Redémarrage WSL nécessaire en fin d'installation
        "
    else
        log_debug "
        Systemd est déjà activé
        "
    fi

}

