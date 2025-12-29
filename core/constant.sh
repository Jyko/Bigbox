#!/usr/bin/env bash
# shellcheck shell=bash

BB_ALLOWED_ACTIONS=(
  help
  install
  start
  stop
  uninstall
  upgrade
)

# Répertoire des modules de la BigBox
BB_MOD_DIR="$SCRIPT_DIR/modules"

# Répertoire d'installation de la configuration de la BigBox
BB_CFG_DIR="$HOME/.config/bigbox"
BB_CFG_ENTRYPOINT_FILENAME="bigbox.sh"
BB_CFG_ENTRYPOINT_FILE="$BB_CFG_DIR/$BB_CFG_ENTRYPOINT_FILENAME"

BB_CFG_DOTFILES_DIR="$BB_CFG_DIR/dotfiles"
BB_CFG_ENV_FILE="$BB_CFG_DOTFILES_DIR/env.sh"
BB_CFG_ALIAS_FILE="$BB_CFG_DOTFILES_DIR/alias.sh"
BB_CFG_COMPLETION_FILE="$BB_CFG_DOTFILES_DIR/completion.sh"

# KUBERNETES
BB_K8S_CONFIG_DIR=$HOME/.kube
BB_K8S_CONTEXT=bigbox
BB_K8S_NAMESPACE=bigbox

# SSH
BB_SSH_DIR=$HOME/.ssh/bigbox