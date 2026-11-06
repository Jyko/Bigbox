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
# Registre de ce que la Bigbox a installé ou créé (voir core/state_utils.sh)
BB_STATE_FILE="$BB_CFG_DIR/state/owned"
BB_CFG_ENV_FILE="$BB_CFG_DOTFILES_DIR/env.sh"

# KUBERNETES
BB_K8S_CONFIG_DIR=$HOME/.kube
BB_K8S_CONTEXT=bigbox
BB_K8S_NAMESPACE=bigbox
# Délai maximum d'attente de l'API Kubernetes, en secondes
BB_K8S_KUBECTL_TIMEOUT=60
# Délai maximum d'une requête kubectl vers l'API (kubectl n'en a aucun par défaut)
BB_K8S_REQUEST_TIMEOUT="15s"
# Durée maximum d'une commande kubectl ou helm complète, en secondes
BB_K8S_COMMAND_TIMEOUT=180

# Garde contre les attentes prolongées : durée maximum d'une action d'un module, en secondes.
# Surchargeable : BB_MODULE_TIMEOUT=1800 ./bigbox install
BB_MODULE_TIMEOUT="${BB_MODULE_TIMEOUT:-900}"

# Options communes de curl : échec sur erreur HTTP, et 3 nouvelles tentatives sur toute erreur
# (une coupure réseau ponctuelle, ex. curl (56), faisait échouer toute l'installation).
# Garde contre les transferts bloqués : connexion bornée à 15 s, abandon (puis nouvelle
# tentative) si le débit reste sous 1 Ko/s pendant 30 s.
BB_CURL_OPTS=(-fsSL --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 15 --speed-limit 1024 --speed-time 30)

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