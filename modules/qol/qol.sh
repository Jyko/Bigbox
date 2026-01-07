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
    ripgrep
)

qol_install() {

    

    apt_wrapper install "${BB_QOL_PACKAGES[@]}"

    # Générer le fichier de configuration de bat
    if command -v batcat >/dev/null 2>&1 && [[ ! -f "$(batcat --config-file)" ]]; then
        run_cmd batcat --generate-config-file
    fi

    _qol_lazygit_install
    
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

    _qol_lazygit_uninstall

    apt_wrapper purge "${BB_QOL_PACKAGES[@]}" || true

}

_qol_lazygit_install() {

    # Sur les ancienns versions, lazygit n'est pas publié sur les répos universe.
    # On vérifie donc sur quelle version d'Ubuntu nous sommes.
    . /etc/os-release

    local actual_version
    actual_version=$(( ${VERSION_ID/./} ))

    if [[ $actual_version -ge 2510 ]]; then
        apt_wrapper install lazygit
    else
        lazygit_latest_version=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')

        local tmp="$(mktemp -d)"

        curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${lazygit_latest_version}/lazygit_${lazygit_latest_version}_Linux_x86_64.tar.gz" | \
            tar -xz -C "$tmp"

        sudo install "$tmp/lazygit" -D -t "/usr/local/bin"

        rm -rf "$tmp"
    fi
}

_qol_lazygit_uninstall() {
    # On supprime en silence les deux possibilités
    sudo rm -f "/usr/local/bin/lazygit"
    apt_wrapper purge lazygit || true
}