#!/usr/bin/env bash
# shellcheck shell=bash

BB_CATPPUCIN_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_CATPPUCIN_DOTFILES_DIR="$BB_CATPPUCIN_BASE_DIR/dotfiles"
BB_CATPPUCIN_BAT_THEME_FILE="Catppuccin Mocha.tmTheme"
BB_CATPPUCIN_BAT_THEME_LINE="--theme=\"Catppuccin Mocha\""

# La malveillance maximum, ici on install Catppuccin Mocha PARTOUT ! :sdk:
catppucin_install() {

    apt_wrapper install vivid

    # LS_COLOR
    cfg_copy_dotfile "$BB_CATPPUCIN_DOTFILES_DIR/catppucin_env.sh"
    
    # bat
    local bat_themes_dir
    bat_themes_dir="$(batcat --config-dir)/themes"
    mkdir -p "$bat_themes_dir"

    if [[ ! -f "$bat_themes_dir/$BB_CATPPUCIN_BAT_THEME_FILE" ]]; then
        run_cmd wget --tries=3 -P "$bat_themes_dir" "https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Mocha.tmTheme"
        run_cmd batcat cache --build
    fi

    local bat_config_file
    bat_config_file=$(batcat --config-file)

    if [[ -f "$bat_config_file" ]]; then
        cfg_set_line -p="$BB_CATPPUCIN_BAT_THEME_LINE" -l="$BB_CATPPUCIN_BAT_THEME_LINE" -f="$bat_config_file"
    fi

}

# On purge la malveillance :sadge:
catppucin_uninstall() {

    cfg_delete_dotfile "catppucin_env.sh"

    # Retirer le thème de la configuration bat de l'utilisateur, sans toucher au reste de sa configuration
    if command -v batcat >/dev/null 2>&1; then
        local bat_config_file bat_theme_path
        bat_config_file=$(batcat --config-file)
        bat_theme_path="$(batcat --config-dir)/themes/$BB_CATPPUCIN_BAT_THEME_FILE"

        if [[ -f "$bat_config_file" ]]; then
            cfg_set_line -p="$BB_CATPPUCIN_BAT_THEME_LINE" -l="" -f="$bat_config_file"
        fi

        if [[ -f "$bat_theme_path" ]]; then
            rm -f "$bat_theme_path"
            run_cmd batcat cache --build
        fi
    fi

    apt_purge_installed vivid || true

}