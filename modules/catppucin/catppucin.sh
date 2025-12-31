#!/usr/bin/env bash
# shellcheck shell=bash

BB_CATPPUCIN_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_CATPPUCIN_DOTFILES_DIR="$BB_CATPPUCIN_BASE_DIR/dotfiles"

# La malveillance maximum, ici on install Catppucin Moccha PARTOUT ! :sdk:
catppucin_install() {

    apt_wrapper install vivid

    # LS_COLOR
    cfg_copy_dotfile "$BB_CATPPUCIN_DOTFILES_DIR/catppucin_env.sh"
    
    # bat
    local bat_themes_dir
    bat_themes_dir="$(batcat --config-dir)/themes"
    mkdir -p "$bat_themes_dir"

    if [[ ! -f "$bat_themes_dir/Catppuccin Mocha.tmTheme" ]]; then 
        run_cmd wget -P "$bat_themes_dir" "https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Mocha.tmTheme"
        run_cmd batcat cache --build
    fi

    local bat_config_file
    bat_config_file=$(batcat --config-file)

    if [[ -f "$bat_config_file" ]]; then
        cfg_set_line -p="--theme=\"Catppuccin Mocha\"" -l="--theme=\"Catppuccin Mocha\"" -f="$bat_config_file"
    fi

}

# On purge la malveillance :sadge:
catppucin_uninstall() {

    cfg_delete_dotfile "catppucin_env.sh"

    apt_wrapper purge vivid || true

}