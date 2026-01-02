#!/usr/bin/env bash
# shellcheck shell=bash

# Afficher la bannière
_menu_banner() {
    local entreprise
    
    if [[ $SHOW_EE -ne 0 ]]; then
        entreprise="🐒 \033[1mBOUG\033[0mard 🐒"
    else
        entreprise="\033[1mBIG\033[0mard"
    fi

    log_info "
    \t██████╗ ██╗ ██████╗ ██████╗  ██████╗ ██╗  ██╗ 
    \t██╔══██╗██║██╔════╝ ██╔══██╗██╔═══██╗╚██╗██╔╝ 
    \t██████╔╝██║██║  ███╗██████╔╝██║   ██║ ╚███╔╝  
    \t██╔══██╗██║██║   ██║██╔══██╗██║   ██║ ██╔██╗  
    \t██████╔╝██║╚██████╔╝██████╔╝╚██████╔╝██╔╝ ██╗    
    \t╚═════╝ ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ 
    \t📦      La ${entreprise} tool\033[1mBOX\033[0m
    "

}

_menu_debug_status() {

    log_warn "\t🐞      Le mode DEBUG est activé\n"

}

# Afficher les easters eggs
_menu_easter_eggs() {

    log_info "\t✒️  Auteur :
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
    \t    🍅  Valérian\n"

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

    log_info "\t🏷️      version : ${version:-"inconnue"}\n"

}

_menu_help() {
    log_info "\tUsage: bigbox <action> [options ...]

    \t-----------------------------------------------------------------
    \t  Actions         Modulaire               Description             
    \t-----------------------------------------------------------------
    \t  install         ❌                      Installer la BigBox     
    \t  uninstall       ❌                      Désinstaller la BigBox  
    \t  start           ✅                      Démarrer les outils     
    \t  stop            ✅                      Eteindre les outils     
    \t  upgrade         ✅                      Mettre à jour les outils

    \t----------------------------------------------------------------
    \t Options                                  Description
    \t----------------------------------------------------------------
    \t  [ -h | --help ]                         Afficher cette aide
    \t  [ -d | --debug ]                        Activer le mode debug, tous les messages sont loggés
    \t  [ -q | --quiet ]                        Activer le mode quiet, seules les erreurs sont loggées
    \t  [ -v | --version ]                      Afficher la version
    \t  [ -b | --banner ]                       Afficher la bannière
    \t  [ -m | --module ] <mod1,mod2,...>       Filtrer les modules à exécuter si l'action selectionnée permet une exécution modulaire\n"
}

menu_show() {

    if [[ $SHOW_BANNER -ne 0 ]]; then
        _menu_banner
    fi

    if [[ $SHOW_VERSION -ne 0 ]]; then
        _menu_version
    fi

    if [[ $SHOW_EE -ne 0 ]]; then
        _menu_easter_eggs
    fi

    if log_is_debug; then
        _menu_debug_status
    fi

    # Afficher l'aide si elle a été demandée ou si aucune action n'a été renseignée
    if [[ $SHOW_HELP -ne 0 || -z "$ACTION" ]]; then
        _menu_help
    fi

}