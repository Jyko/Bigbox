#!/usr/bin/env bash
# shellcheck shell=bash

BB_CORE_GO_PATH="$HOME/go/bin"

# Liste des packages obligatoires pour le fonctionnement de la Bigbox
BB_CORE_PACKAGES=(
    ca-certificates
    curl
    golang-go
    jq
    shellcheck
)

_core_bigbox_configuration() {

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
    for dotfile in "\$BIGBOX_DOTFILES_DIR/*.sh"; do
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

_core_bigbox_unconfiguration() {

    # Suppresion de toute la configuration Bigbox initiale !
    # FIXME: Les désinstallations de modules devraient se jouer dans l'ordre inverse.
    # Actuellement, je détruis les configurations des modules avant qu'ils aient eu le temps de clean tout correctement.
    sudo rm -rf "$BB_CFG_DIR"

    # Suppression de l'instruction de source de l'entrypoint Bigbox dans le .bashrc utilisateur
    cfg_set_line \
        -p="${BB_CFG_ENTRYPOINT_FILENAME//./\\.}" \
        -f="$HOME/.bashrc"
}

_core_go_configuration() {
    # S'assurer de la présence de l'entrée dans le PATH1
    # L'export permet de rendre Go et ses binaires disponibles aux modules suivants
    cfg_modify_env -k="PATH" -v="PATH" -a
    cfg_modify_env -k="PATH" -v="$BB_CORE_GO_PATH" -a
    export PATH="$PATH:$BB_CORE_GO_PATH"
}

_core_go_unconfiguration() {
    # Supprimer l'entrée dans le PATH
    cfg_modify_env -k="PATH" -v="PATH" -d
    cfg_modify_env -k="PATH" -v="$BB_CORE_GO_PATH" -d
}

core_install() {

    _core_bigbox_configuration

    apt_wrapper install "${BB_CORE_PACKAGES[@]}"

    _core_go_configuration
}

core_uninstall() {

    # Nous ne désinstallons pas les packages Cores à date
    # On conserve Golang et sa configuration
    # apt_wrapper remove "${BB_CORE_PACKAGES[@]}"
    # _core_go_unconfiguration

    _core_bigbox_unconfiguration
}

core_upgrade() {

    _core_bigbox_configuration

    apt_wrapper update && apt_wrapper install --only-upgrade "${BB_CORE_PACKAGES[@]}"

    _core_go_configuration
}
