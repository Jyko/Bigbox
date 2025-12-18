#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

####################################
# LIBRAIRIES ET VARIABLES GLOBALES #
####################################

# Demander l'élévation des privilèges dès le début
sudo -v

# Variables globales
BB_CFG_DIR="$HOME/.config/bigbox"
BB_CFG_FILE_ALIAS="alias"
BB_CFG_FILE_AUTOCOMPLETION="autocompletion"
DEBUG=false
SHOW_VERSION=false
SHOW_BANNER=true
SHOW_EASTER_EGGS=false

# Bonne pratique, pour définir le répertoire du script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Importer les librairies
source "$SCRIPT_DIR/lib/log.sh"
source "$SCRIPT_DIR/lib/util.sh"
source "$SCRIPT_DIR/lib/system.sh"
source "$SCRIPT_DIR/lib/task.sh"

# Parser les arguments d'entrée
parse_args "$@"

###########################
# DEBUT DE L'INSTALLATION #
###########################

show_infos

######################
### 1 - PRE-REQUIS ###
######################

step "Vérification des pré-requis" "🔎"

task "Version d'Ubuntu" verify_ubuntu_version

# Mise à jour des répos et paquets
task "MàJ des dépôts et paquets" apt_wrapper update -y && \
    apt_wrapper upgrade -y

################
# 2 - Basiques #
################

step "Installation des dépôts et paquets de base" "🧱"

# Rien pour le moment
task "Installation des dépôts requis" echo N/A 

task "Installation des paquets requis" apt_wrapper install -y \
    apt-transport-https \
    bash-completion \
    curl \
    ca-certificates \
    git \
    jq \
    unzip \
    wget

step "Installation de snapd" "📦"
task "Installation de snapd" install_snapd

##############
# 3 - Docker #
##############

step "Installation de Docker" "\ue7b0"
task "Installation de Docker" install_docker

##################
# 4 - Kubernetes #
##################

step "Installation de Kubernetes" "\ue81d"
task "Installation de microk8s" install_microk8s
task "Installation des outils Kubernetes" install_k8s_tools
task "Configuration des outils Kubernetes" configure_k8s_tools
