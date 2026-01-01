#!/usr/bin/env bash
# shellcheck shell=bash

BB_QOL_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_QOL_DOTFILES_DIR="$BB_QOL_BASE_DIR/dotfiles"

BB_QOL_PACKAGES=(
    bat
    eza
    fd-find
    fzf
    htop
    lazygit
    ripgrep
)

qol_install() {

    apt_wrapper install "${BB_QOL_PACKAGES[@]}"

    # Générer le fichier de configuration de bat
    if [[ ! -f "$(batcat --config-file)" ]]; then
        run_cmd batcat --generate-config-file
    fi
    
    cfg_copy_dotfile "$BB_QOL_DOTFILES_DIR/qol_alias.sh"
    cfg_copy_dotfile "$BB_QOL_DOTFILES_DIR/qol_completion.sh"
    cfg_copy_dotfile "$BB_QOL_DOTFILES_DIR/qol_env.sh"
    cfg_copy_dotfile "$BB_QOL_DOTFILES_DIR/qol_keybinding.sh"

}

qol_uninstall() {

    cfg_delete_dotfile "qol_alias.sh"
    cfg_delete_dotfile "qol_completion.sh"
    cfg_delete_dotfile "qol_env.sh"
    cfg_delete_dotfile "qol_keybinding.sh"

    apt_wrapper purge "${BB_QOL_PACKAGES[@]}" || true

}