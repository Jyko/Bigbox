#!/usr/bin/env bash
# shellcheck shell=bash

BB_CORE_DIR="$SCRIPT_DIR/core"

# L'ordre des librairies est important à cause des variables globales.
# TODO : Séparer les librairies Bigbox des librairies agnostiques Bash, çà règlera cet ordre de chargement.
source "$BB_CORE_DIR/constant.sh" # TOP1, le reste on s'en fout
source "$BB_CORE_DIR/action.sh"
source "$BB_CORE_DIR/collection_utils.sh"
source "$BB_CORE_DIR/configuration_utils.sh"
source "$BB_CORE_DIR/fs_utils.sh"
source "$BB_CORE_DIR/kubernetes_utils.sh"
source "$BB_CORE_DIR/log.sh"
source "$BB_CORE_DIR/menu.sh"
source "$BB_CORE_DIR/module.sh"
source "$BB_CORE_DIR/utils.sh"
source "$BB_CORE_DIR/ssh_utils.sh"