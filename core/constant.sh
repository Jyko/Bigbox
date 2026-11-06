#!/usr/bin/env bash
# shellcheck shell=bash
# Constantes globales utilisées par les autres librairies et les modules
# shellcheck disable=SC2034

# Fichier d'info
BB_INFO_FILE="$SCRIPT_DIR/info.json"

# Répertoire des modules de la BigBox
BB_MOD_DIR="$SCRIPT_DIR/modules"
# Répertoire des ressources de la Bigbox
BB_RSC_DIR="$SCRIPT_DIR/resources"

# Répertoire d'installation de la configuration de la BigBox
BB_CFG_DIR="$HOME/.config/bigbox"
BB_CFG_ENTRYPOINT_FILENAME="bigbox.sh"
BB_CFG_ENTRYPOINT_FILE="$BB_CFG_DIR/$BB_CFG_ENTRYPOINT_FILENAME"

BB_CFG_DOTFILES_DIR="$BB_CFG_DIR/dotfiles"
BB_CFG_ENV_FILE="$BB_CFG_DOTFILES_DIR/env.sh"

# KUBERNETES
BB_K8S_CONFIG_DIR=$HOME/.kube
BB_K8S_CONTEXT=bigbox
BB_K8S_NAMESPACE=bigbox
# Délai maximum d'attente de l'API Kubernetes, en secondes
BB_K8S_KUBECTL_TIMEOUT=60

# PostgreSQL de la Bigbox, vu depuis l'Host (doit rester cohérent avec modules/pg/helm/values.yaml)
BB_PG_HOST=localhost
BB_PG_PORT=30001
BB_PG_USER=bigbox
BB_PG_PASSWORD=bigbox
BB_PG_DATABASE=bigbox

# SSH
BB_SSH_DIR=$HOME/.ssh/bigbox

# Starship
BB_STARSHIP_CONFIG_FILE="$HOME/.config/starship.toml"