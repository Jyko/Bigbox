#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

####################################
# LIBRAIRIES ET VARIABLES GLOBALES #
####################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Importer les librairies
source "$SCRIPT_DIR/lib/utils.sh"

# Variables globales
DEBUG=false
UBUNTU_MINI_VERSION=24

# Parser les arguments d'entrée
parse_args "$@"

###########################
# DEBUT DE L'INSTALLATION #
###########################

cat <<EOF

██████╗ ██╗ ██████╗ ██████╗  ██████╗ ██╗  ██╗ 
██╔══██╗██║██╔════╝ ██╔══██╗██╔═══██╗╚██╗██╔╝ 
██████╔╝██║██║  ███╗██████╔╝██║   ██║ ╚███╔╝  
██╔══██╗██║██║   ██║██╔══██╗██║   ██║ ██╔██╗  
██████╔╝██║╚██████╔╝██████╔╝╚██████╔╝██╔╝ ██╗    
╚═════╝ ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ 

EOF

######################
### 1 - PRE-REQUIS ###
######################

cat <<EOF

1️⃣   Vérification des pré-requis

EOF

# Vérification de la version Ubuntu
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_MAJOR_VERSION=${UBUNTU_VERSION%%.*}
if (( UBUNTU_MAJOR_VERSION < UBUNTU_MINI_VERSION )); then

cat <<EOF
    ❌ Une version majeure d'Ubuntu $UBUNTU_MINI_VERSION+ est requise

    ℹ️ La version majeure actuelle est $UBUNTU_VERSION
    
    🔄 Mettez à jour la version de la distribution Ubuntu
    sudo do-release-upgrade

    Après la mise à jour, relancez ce script d'installation
EOF

exit 1

fi

echo -e "\t✅ Version d'Ubuntu $UBUNTU_VERSION"

# Mise à jour des répos et paquets
task "MàJ des dépôts et paquets" sudo apt-get update -y && \
    sudo apt-get upgrade -y

################
# 2 - Basiques #
################

cat <<EOF

2️⃣   Installation des dépôts et paquets de base

EOF

task "Installation des paquets requis" sudo apt-get install -y \
    curl \
    wget \
    apt-transport-https \
    git \
    jq

# 2. Installer dépendances systèmes
# 3. Installer Docker
# 4. Installer MicroK8s et configurer addons
# 5. Installer kubectl et Helm
# 6. Installer clients Postgres, NATS
# 7. Créer namespace dev et services de base (optionnel)
# 8. Fin
