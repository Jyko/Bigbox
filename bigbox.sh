#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

####################################
# LIBRAIRIES ET VARIABLES GLOBALES #
####################################

# Demander l'élévation des privilèges dès le début
sudo -v

# Bonne pratique, pour définir le répertoire du script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Variables globales
ACTION=help
ACTION_SET=false
DEBUG=false
SHOW_BANNER=true
SHOW_EASTER_EGGS=false

# Importer les librairies
source "$SCRIPT_DIR/core/libs.sh"

# TODO/FIXME : A externaliser dans une librairie core, quand j'aurais de l'inspiration pour le rangement.
# Certainement un init.sh avec le parse des arguments un peu plus propre et des entrypoints mieux refactoré
# Les messages et logs devraient aussi se trouver dans une lib d'UI/TUI/Message, je sais pas trop comment appeler çà.

###################
# PARSER LES ARGS #
###################
parse_args "$@"

###########################
# ENTRYPOINTS DES ACTIONS #
###########################
execute_action() {

    case "$ACTION" in
        help)
            execute_help
            exit 0
            ;;
        version)
            execute_version
            exit 0
            ;;
        install|uninstall|upgrade|start|stop)
            execute_others
            exit 0
            ;;
    esac

    # SORTIE DE LA BIGBOX
    exit 1
}

########
# HELP #
########
execute_help() {

    show_infos

    cat \
<<EOF
    Usage: bigbox.sh [action] [options ...]

    Actions:
        help                    Afficher cette aide
        version                 Afficher la version
        
        install                 Installer la BigBox
        uninstall               Désinstaller la BigBox
        upgrade                 Mettre à jour la BigBox
        
        start                   Démarrer les outils et déploiements de la BigBox
        stop                    Eteindre les outils et déploiements de la Bigbox

    Options:
        -d, --debug             Activer le mode debug
        --nb, --no-banner       Masquer la bannière
EOF

}

###########
# VERSION #
###########
execute_version() {

    local version

    if ! git -C "$SCRIPT_DIR" rev-parse --git-dir > /dev/null; then
        version="inconnue"
    else
        # Chercher le nom du tag, sinon le SHA court surlequel se situe HEAD
        version=$(git -C "$SCRIPT_DIR" describe --tags --exact-match 2>/dev/null || \
            git -C "$SCRIPT_DIR" rev-parse --short HEAD || \
            echo "inconnue")
    fi

    show_infos

    cat \
<<-EOF
    🏷️       ${version:-"inconnue"}
EOF

}

###########
# AUTRES #
###########
execute_others() {

    show_infos

    # Charger les modules (pour le moment tous)
    load_modules

    # Exécuter l'action sur tous les modules chargés par ordre de priorité déclaré
    run_modules "$ACTION"

    echo -e "\r\t⚠️  Ne pas oublier de redémarrer le conteneur WSL2 (Windows) ou l'OS (Ubuntu Desktop) pour la prise en compte des modifications des utilisateurs, groupes et permissions. ⚠️"

}


#####################
# EXECUTER L'ACTION #
#####################

execute_action