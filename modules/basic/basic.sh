#!/usr/bin/env bash
# shellcheck shell=bash

# METADATA du module
MODULE_NAME="basic"
MODULE_PRIORITY=0

BB_BASIC_GO_PATH="$HOME/go/bin"

# Liste des packages considérés comme suffisament basiques pour ne jamais être désinstallés
BB_BASIC_PACKAGES=(
    shellcheck
    golang-go
)

__basic_go_configuration() {
    # S'assurer de la présence de l'entrée dans le PATH1
    # L'export permet de rendre Go et ses binaires disponibles aux modules suivants
    cfg_modify_env -k="PATH" -v="PATH" -a
    cfg_modify_env -k="PATH" -v="$BB_BASIC_GO_PATH" -a
    export PATH="$PATH:$BB_BASIC_GO_PATH"
}

__basic_go_unconfiguration() {
    # Supprimer l'entrée dans le PATH
    cfg_modify_env -k="PATH" -v="PATH" -d
    cfg_modify_env -k="PATH" -v="$BB_BASIC_GO_PATH" -d
}

basic_install() {

    apt_wrapper install "${BB_BASIC_PACKAGES[@]}"

    __basic_go_configuration
}

basic_uninstall() {

    apt_wrapper remove "${BB_BASIC_PACKAGES[@]}"

    __basic_go_unconfiguration
}

basic_upgrade() {

    apt_wrapper update && apt_wrapper install --only-upgrade "${BB_BASIC_PACKAGES[@]}"

    __basic_go_configuration
}
