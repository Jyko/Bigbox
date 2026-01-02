#!/usr/bin/env bash
# shellcheck shell=bash

BB_CORE_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_CORE_MODULE_DOTFILES_DIR="$BB_CORE_MODULE_BASE_DIR/dotfiles"
BB_CORE_GO_PATH="$HOME/go/bin"

# Liste des packages obligatoires pour le fonctionnement de la Bigbox
BB_CORE_PACKAGES=(
    bash-completion
    ca-certificates
    curl
    golang-go
    jq
    shellcheck
    yq
    wget
)

core_install() {

    _core_bigbox_configuration_install

    apt_wrapper install "${BB_CORE_PACKAGES[@]}"

    _core_go_configuration_install
}

core_uninstall() {
    # Les packages ne sont pas désinstallés, seulement les configurations
    _core_go_configuration_uninstall
    _core_bigbox_configuration_uninstall
}

_core_bigbox_configuration_install() {

    # Assurer la création des répertoires de configuration de la Bigbox
    mkdir -p "$BB_CFG_DIR"
    mkdir -p "$BB_CFG_DOTFILES_DIR"

    cat > "$BB_CFG_ENTRYPOINT_FILE" <<EOF
#!/usr/bin/env bash
# shellcheck shell=bash

# Exporter les variables d'environnement de la Bigbox (pas de ses outils)
export BIGBOX_HOME="$BB_CFG_DIR"
export BIGBOX_DOTFILES_DIR="$BB_CFG_DOTFILES_DIR"

# Charger les configurations de la Bigbox :
# - Alias
# - Completions
# - Variables d'environnement
if [[ -d "\$BIGBOX_DOTFILES_DIR" ]]; then
    for dotfile in \$BIGBOX_DOTFILES_DIR/*.sh; do
        [[ -r "\$dotfile" ]] || continue
        [[ -f "\$dotfile" ]] || continue
        [[ -L "\$dotfile" ]] && continue
        source "\$dotfile"
    done
fi
EOF

    chmod 644 "$BB_CFG_ENTRYPOINT_FILE"

    # Mise à disposition des variables d'environnement pour les modules suivants
    export BIGBOX_HOME="$BB_CFG_DIR"
    export BIGBOX_DOTFILES_DIR="$BB_CFG_DOTFILES_DIR"

    # Injecter l'instruction de source de l'entrypoint Bigbox dans le .bashrc utilisateur
    # Nous supprimons et recréons la ligne dans le .bashrc à chaque fois, pour éviter de contaminer la configuration utilisateur avec des doublons
    # Nous échappons le nom de l'entrypoint pour en faire un pattern de regex (transformer le '.' en '\.')
    cfg_set_line \
        -p="${BB_CFG_ENTRYPOINT_FILENAME//./\\.}" \
        -l="[[ -f \"$BB_CFG_ENTRYPOINT_FILE\" ]] && source \"$BB_CFG_ENTRYPOINT_FILE\"" \
        -f="$HOME/.bashrc"

}

_core_bigbox_configuration_uninstall() {

    # Suppresion de toute la configuration Bigbox initiale !
    # FIXME: Les désinstallations de modules devraient se jouer dans l'ordre inverse.
    # Actuellement, je détruis les configurations des modules avant qu'ils aient eu le temps de clean tout correctement.
    sudo rm -rf "$BB_CFG_DIR"

    # Suppression de l'instruction de source de l'entrypoint Bigbox dans le .bashrc utilisateur
    cfg_set_line \
        -p="${BB_CFG_ENTRYPOINT_FILENAME//./\\.}" \
        -f="$HOME/.bashrc"
}

_core_go_configuration_install() {
    
    cfg_copy_dotfile "$BB_CORE_MODULE_DOTFILES_DIR/core_env.sh"
    
    # L'export permet de rendre Go et ses binaires disponibles aux modules suivants
    export PATH="$PATH:$BB_CORE_GO_PATH"
}

_core_go_configuration_uninstall() {
    # Supprimer l'entrée dans le PATH
    cfg_delete_dotfile "core_env.sh"
}