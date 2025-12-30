#!/usr/bin/env bash
# shellcheck shell=bash

# =============================================
# Utilitaires communs pour la gestion des LOGS
# =============================================

# ====================
# Définition des niveaux de logs
# ====================
readonly LOG_DEBUG=0
readonly LOG_INFO=1
readonly LOG_SILENT=2

# Niveau de log courant
LOG_LEVEL="$LOG_INFO"

# ====================
# Gestion du niveau de logs
# ====================
log_set_silent() { LOG_LEVEL="$LOG_SILENT" ; }
log_set_info() { LOG_LEVEL="$LOG_INFO" ; }
log_set_debug() { LOG_LEVEL="$LOG_DEBUG" ; }

# ====================
# Fonctions
# ====================

# Retourner 0 si ce niveau de log est au moins égal au niveau de log courant de l'application, sinon retourne 1.
# -l|--level    : Le niveau à tester contre le niveau de log courant
_log_is_at_least() {
    local level=""

    for arg in "$@"; do
        case "$arg" in
            -l=*) level="${arg#*=}" ;;
            *) printf "\033[31mArgument non supporté \n\033[0m\n" >&2 && return 2 ;;
        esac
    done

    if [[ -z "$level" ]]; then
        printf "\033[31mLe niveau de log à tester est obligatoire\033[0m\n" >&2
    fi

    (( "$LOG_LEVEL" <= "$level" ))
}

# Retourner 0 si le niveau de log actuel est au moins égal à [...]
# Fonctions convénientes pour masquer l'implémentation interne
log_is_debug() { _log_is_at_least -l="$LOG_DEBUG" || return 1 ; }
log_is_info() { _log_is_at_least -l="$LOG_INFO" || return 1 ; }
log_is_silent() { _log_is_at_least -l="$LOG_SILENT" || return 1 ; }

_log_msg() {
    local color=""
    local level="$LOG_INFO"
    local message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c=*) color="${1#*=}" ; shift 1 ;;
            -l=*) level="${1#*=}" ; shift 1 ;;
            --) shift; break ;;  # fin des options
            *) break ;;
        esac
    done

    message="$*"

    # Vérifier que le niveau de log courant permet la publication du message
    _log_is_at_least -l="$level" || return 0

    # Applique la couleur
    local prefix=""
    local suffix=""
    if [[ -n "$color" ]]; then
        prefix="\033[${color}m"
        suffix="\033[0m"
    fi

    printf "%b%b%b" "$prefix" "$message" "$suffix" >&2

}

# Afficher un message de log d'une certaine typologie.
# Chaque à son niveau de déclenchement et son format propre.
# DEBUG     : Gris      uniquement en niveau DEBUG
# INFO      : Blanc     toujours sauf en SILENT
# SUCCESS   : Vert      toujours sauf en SILENT
# WARN      : Jaune     toujours sauf en SILENT
# ERROR     : Rouge     toujours y compris en SILENT
log_debug() { _log_msg -c="90" -l="$LOG_DEBUG" "$@" ; }
log_info() { _log_msg "$@" ; }
log_success() { _log_msg -c="32" "$@" ; }
log_warn() { _log_msg -c="33" "$@" ; }
log_error() { _log_msg -c="31" -l="$LOG_SILENT" "$@" ; }
