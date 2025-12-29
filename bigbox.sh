#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ====================
# Déclarer les librairies et les constantes globales
# ====================

# Demander l'élévation des privilèges dès le début
sudo -v

# Bonne pratique, pour définir le répertoire du script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Variables globales
ACTION=help
ACTION_SET=false
SHOW_BANNER=true
SHOW_EASTER_EGGS=false

# Importer les librairies
source "$SCRIPT_DIR/core/libs.sh"

# ====================
# Parser les arguments de la commande
# ====================
for arg in "$@"; do
    if is_valid_action "$arg"; then

        verify_action

        ACTION="$arg"
        ACTION_SET=true

    else
        case "$arg" in
            -s|--silent)
                log_set_silent
                ;;
            -d|--debug)
                log_set_debug
                ;;
            --nb|--no-banner)
                SHOW_BANNER=false
                ;;
            --ee|--easter-eggs)
                SHOW_EASTER_EGGS=true
                ;;
            *)
                echo "Argument non supporté : $arg"
                exit 1
                ;;
        esac
    fi
done

# TODO : A externaliser dans un script core.
# ====================
# Déclaration des actions
# ====================
execute_action() {

    case "$ACTION" in
        help)
            execute_help
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

# Afficher la bannière
show_banner() {

    local entreprise

    if [[ $SHOW_EASTER_EGGS == "true" ]]; then
        entreprise="🐒 BOUGARD 🐒"
    fi

    log_info "
    \t██████╗ ██╗ ██████╗ ██████╗  ██████╗ ██╗  ██╗ 
    \t██╔══██╗██║██╔════╝ ██╔══██╗██╔═══██╗╚██╗██╔╝ 
    \t██████╔╝██║██║  ███╗██████╔╝██║   ██║ ╚███╔╝  
    \t██╔══██╗██║██║   ██║██╔══██╗██║   ██║ ██╔██╗  
    \t██████╔╝██║╚██████╔╝██████╔╝╚██████╔╝██╔╝ ██╗    
    \t╚═════╝ ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ 
    \t📦      La boîte à outils ${entreprise:-Bigard}
    "

}

show_debug_status() {

    log_warn "
    \t🐞      Le mode DEBUG est activé
    "

}

# Afficher les easters eggs
show_easter_eggs() {

    log_info "
    \t✒️  Auteur :
    \t    🐒  Julien FERREIRA DA COSTA

    \t🎤  Cassedédi :
    \t    🐴  Anne-Sophie
    \t    💪  Baptiste
    \t    🥃  Benjamin
    \t    🌸  François
    \t    🔨  Guillaume   
    \t    💎  Iwan        
    \t    💣  Kévin
    \t    🏸  Stéphane    
    \t    🍅  Valérian
    
    "

}

show_version() {

    local version

    if ! git -C "$SCRIPT_DIR" rev-parse --git-dir > /dev/null; then
        version="inconnue"
    else
        # Chercher le nom du tag, sinon le SHA court surlequel se situe HEAD
        version=$(git -C "$SCRIPT_DIR" describe --tags --exact-match 2>/dev/null || \
            git -C "$SCRIPT_DIR" rev-parse --short HEAD || \
            echo "inconnue")
    fi

    log_info "
    \t🏷️      version : ${version:-"inconnue"}
    "

}

show_infos() {

    if [[ "$SHOW_BANNER" == "true" ]]; then
        show_banner
    fi

    show_version

    if [[ "$SHOW_EASTER_EGGS" == "true" ]]; then
        show_easter_eggs
    fi

    if log_is_debug; then
        show_debug_status
    fi

}

########
# HELP #
########
execute_help() {

    show_infos

    log_info "

    \tUsage: bigbox.sh [action] [options ...]

    \tActions:
    \t  help                    Afficher cette aide
    \t  version                 Afficher la version
        
    \t  install                 Installer la BigBox
    \t uninstall               Désinstaller la BigBox
    \t  upgrade                 Mettre à jour la BigBox
        
    \t  start                   Démarrer les outils et déploiements de la BigBox
    \t  stop                    Eteindre les outils et déploiements de la Bigbox

    \tOptions:
    \t  -q, --quiet             Activer le mode quiet, seul les erreurs sont loggées
    \t  -d, --debug             Activer le mode debug, tous les messages sont loggés
    \t  --nb, --no-banner       Masquer la bannière
    
    "

}

###########
# AUTRES #
###########
execute_others() {

    show_infos

    log_info "\n"

    # Charger les modules (pour le moment tous)
    load_modules

    # Exécuter l'action sur tous les modules chargés par ordre de priorité déclaré
    run_modules "$ACTION"

    log_warn "
    \t⚠️  Ne pas oublier de redémarrer le conteneur WSL2 (Windows) ou l'OS (Ubuntu Desktop) pour la prise en compte des modifications des utilisateurs, groupes et permissions. ⚠️
    "

}


#####################
# EXECUTER L'ACTION #
#####################

execute_action