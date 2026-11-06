#!/usr/bin/env bash
# shellcheck shell=bash

BB_STARSHIP_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_STARSHIP_DOTFILES_DIR="$BB_STARSHIP_BASE_DIR/dotfiles"

starship_install() {

    apt_wrapper install starship

    # Nous ne générons la configuration par défaut que si l'utilisateur n'en a pas déjà une.
    # Pas de run_cmd ici : il capture stdout et le fichier serait vide.
    if [[ ! -f "$BB_STARSHIP_CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$BB_STARSHIP_CONFIG_FILE")"
        starship print-config > "$BB_STARSHIP_CONFIG_FILE"
    fi

    cfg_copy_dotfile "$BB_STARSHIP_DOTFILES_DIR/starship_env.sh"

}

starship_uninstall() {

    cfg_delete_dotfile "starship_env.sh"

    rm -f "$BB_STARSHIP_CONFIG_FILE"
    apt_wrapper purge starship || true

}