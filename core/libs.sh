#!/usr/bin/env bash
# shellcheck shell=bash

BB_CORE_DIR="$SCRIPT_DIR/core"

# L'ordre des librairies est important à cause des variables globales.
# TODO : Séparer les librairies Bigbox des librairies agnostiques Bash, çà règlera cet ordre de chargement.
# shellcheck source=core/constant.sh
source "$BB_CORE_DIR/constant.sh" # TOP1, le reste on s'en fout
# shellcheck source=core/action.sh
source "$BB_CORE_DIR/action.sh"
# shellcheck source=core/collection_utils.sh
source "$BB_CORE_DIR/collection_utils.sh"
# shellcheck source=core/configuration_utils.sh
source "$BB_CORE_DIR/configuration_utils.sh"
# shellcheck source=core/fs_utils.sh
source "$BB_CORE_DIR/fs_utils.sh"
# shellcheck source=core/kubernetes_utils.sh
source "$BB_CORE_DIR/kubernetes_utils.sh"
# shellcheck source=core/log.sh
source "$BB_CORE_DIR/log.sh"
# shellcheck source=core/menu.sh
source "$BB_CORE_DIR/menu.sh"
# shellcheck source=core/module.sh
source "$BB_CORE_DIR/module.sh"
# shellcheck source=core/utils.sh
source "$BB_CORE_DIR/utils.sh"
# shellcheck source=core/ssh_utils.sh
source "$BB_CORE_DIR/ssh_utils.sh"