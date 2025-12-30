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
ACTION=""
SHOW_HELP=false
SHOW_BANNER=true
SHOW_VERSION=false
SHOW_EASTER_EGGS=false

# Importer les librairies
source "$SCRIPT_DIR/core/libs.sh"

# --------------------
# Parser les arguments
# --------------------
for arg in "$@"; do

    # Si le paramètre est une action configurée
    if action_is_valid "$arg"; then

        # Vérifier que c'est bien la première et seule action passée
        if [[ -n "$ACTION" ]]; then
            echo "Une seule action est autorisée à la fois" >&2
            exit 2
        fi

        ACTION="$arg"

    else
        case "$arg" in
            -s|--silent)
                log_set_silent
                ;;
            -h|--help)
                SHOW_HELP=true
                ;;
            -v|--version)
                SHOW_VERSION=true
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
                echo "Argument non supporté : $arg" >&2
                exit 2
                ;;
        esac
    fi
done

# --------------------
# Executer l'action
# --------------------
menu_show

if [[ -n "$ACTION" && $SHOW_HELP == "false" ]]; then
    action_execute "$ACTION"
fi

exit 0