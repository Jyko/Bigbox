#!/usr/bin/env bash
# shellcheck shell=bash

BB_QOL_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_QOL_DOTFILES_DIR="$BB_QOL_BASE_DIR/dotfiles"

# Versions épinglées des outils qui ne sont pas (ou pas partout) dans les dépôts Ubuntu
BB_QOL_LAZYGIT_VERSION="0.66.2"
BB_QOL_ZOXIDE_VERSION="0.10.0"
BB_QOL_LAZYGIT_BINARY="/usr/local/bin/lazygit"

BB_QOL_PACKAGES=(
    bat
    eza
    fd-find
    fzf
    htop
    ripgrep
)

qol_install() {

    apt_install "${BB_QOL_PACKAGES[@]}"

    # Générer le fichier de configuration de bat, s'il n'existe pas
    local bat_config_file
    bat_config_file=$(batcat --config-file)
    if [[ ! -f "$bat_config_file" ]]; then
        run_cmd batcat --generate-config-file
        state_mark_owned "file:$bat_config_file"
    fi

    _qol_lazygit_install
    _qol_zoxide_install
    
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

    _qol_zoxide_uninstall
    _qol_lazygit_uninstall

    # Configuration de bat, uniquement si elle a été générée par la Bigbox
    if command -v batcat >/dev/null 2>&1; then
        local bat_config_file
        bat_config_file=$(batcat --config-file)
        if state_is_owned "file:$bat_config_file"; then
            rm -f "$bat_config_file"
            state_unmark "file:$bat_config_file"
        fi
    fi

    # Seuls les paquets installés par la Bigbox sont purgés (htop est présent par défaut sur Ubuntu Desktop)
    apt_purge_owned "${BB_QOL_PACKAGES[@]}" || true

}

_qol_lazygit_install() {

    # Sur les ancienns versions, lazygit n'est pas publié sur les répos universe.
    # On vérifie donc sur quelle version d'Ubuntu nous sommes.
    . /etc/os-release

    local actual_version
    actual_version=$(( ${VERSION_ID/./} ))

    if [[ $actual_version -ge 2510 ]]; then
        apt_install lazygit
        return 0
    fi

    if command -v lazygit >/dev/null 2>&1; then
        return 0
    fi

    # Les archives de lazygit nomment l'architecture x86_64 et non amd64 comme dpkg
    local arch
    arch=$(dpkg --print-architecture)
    [[ "$arch" == "amd64" ]] && arch="x86_64"

    local tmp
    tmp=$(mktemp -d)

    run_cmd curl "${BB_CURL_OPTS[@]}" -o "$tmp/lazygit.tar.gz" \
        "https://github.com/jesseduffield/lazygit/releases/download/v${BB_QOL_LAZYGIT_VERSION}/lazygit_${BB_QOL_LAZYGIT_VERSION}_linux_${arch}.tar.gz"
    tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit

    sudo install "$tmp/lazygit" -D -t "$(dirname "$BB_QOL_LAZYGIT_BINARY")"
    state_mark_owned "file:$BB_QOL_LAZYGIT_BINARY"

    rm -rf "${tmp:?}"
}

_qol_lazygit_uninstall() {
    # Binaire GitHub ou paquet apt, selon la version d'Ubuntu, uniquement s'ils viennent de la Bigbox
    state_remove_owned_files "$BB_QOL_LAZYGIT_BINARY"
    apt_purge_owned lazygit || true
}

# Zoxide est installé depuis le .deb de sa release GitHub, en version épinglée, plutôt que via curl | sh
_qol_zoxide_install() {
    if command -v zoxide >/dev/null 2>&1; then
        return 0
    fi

    local tmp
    tmp=$(mktemp -d)

    run_cmd curl "${BB_CURL_OPTS[@]}" -o "$tmp/zoxide.deb" \
        "https://github.com/ajeetdsouza/zoxide/releases/download/v${BB_QOL_ZOXIDE_VERSION}/zoxide_${BB_QOL_ZOXIDE_VERSION}-1_$(dpkg --print-architecture).deb"
    apt_install "$tmp/zoxide.deb"

    rm -rf "${tmp:?}"
}

_qol_zoxide_uninstall() {
    # La base de zoxide (~/.local/share/zoxide, l'historique des répertoires) appartient à l'utilisateur
    apt_purge_owned zoxide || true
}