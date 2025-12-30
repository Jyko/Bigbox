#!/usr/bin/env bash
# shellcheck shell=bash

# Afficher la bannière
_menu_banner() {

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

_menu_debug_status() {

    log_warn "
    \t🐞      Le mode DEBUG est activé
    "

}

# Afficher les easters eggs
_menu_easter_eggs() {

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

_menu_version() {

    local version

    # Nous allons chercher la version dans le fichier d'info du projet, sinon dans le nom du tag, sinon le short ID du commit, sinon ... inconnue :D
    if [[ -f "$BB_INFO_FILE" ]]; then
        version="$(jq -r '.version' "$BB_INFO_FILE")"
    elif ! git -C "$SCRIPT_DIR" rev-parse --git-dir > /dev/null; then
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

_menu_help() {
    log_info "
    \tUsage: bigbox [action] [options ...]

    \tActions:
    \t--------------------[ Gestion de la Bigbox ]--------------------
    \t  install                     Installer la BigBox
    \t  uninstall                   Désinstaller la BigBox
    \t  upgrade                     Mettre à jour la BigBox

    \t---------------------[ Gestion des outils ]---------------------
    \t  start                       Démarrer les outils et déploiements de la BigBox
    \t  stop                        Eteindre les outils et déploiements de la Bigbox

    \tOptions:
    \t  [ -h | --help ]             Afficher cette aide
    \t  [ -d | --debug ]            Activer le mode debug, tous les messages sont loggés
    \t  [ -q | --quiet ]            Activer le mode quiet, seul les erreurs sont loggées
    \t  [ -v | --version ]          Afficher la version de la Bigbox
    \t  [ --nb | --no-banner ]      Masquer la bannière 
    "
}

menu_show() {

    if [[ "$SHOW_BANNER" == "true" ]]; then
        _menu_banner
    fi

    if [[ "$SHOW_VERSION" == "true" ]]; then
        _menu_version
    fi

    if [[ "$SHOW_EASTER_EGGS" == "true" ]]; then
        _menu_easter_eggs
    fi

    if log_is_debug; then
        _menu_debug_status
    fi

    # Afficher l'aide si elle a été demandée ou si aucune action n'a été renseignée
    if [[ "$SHOW_HELP" == "true" || -z "$ACTION" ]]; then
        _menu_help
    fi

}