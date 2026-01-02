#!/usr/bin/env bash
# shellcheck shell=bash

BB_STARSHIP_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_STARSHIP_DOTFILES_DIR="$BB_STARSHIP_BASE_DIR/dotfiles"

starship_install() {

    apt_wrapper install starship
    run_cmd starship print-config > "$BB_STARSHIP_CONFIG_FILE"

    cfg_copy_dotfile "$BB_STARSHIP_DOTFILES_DIR/starship_env.sh"

}

starship_uninstall() {

    cfg_delete_dotfile "$BB_STARSHIP_DOTFILES_DIR/starship_env.sh"

    rm -f "$BB_STARSHIP_CONFIG_FILE"
    apt_wrapper purge starship

}