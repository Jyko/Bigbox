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

# Retourner 0 si ce niveau de log est au moins égal au niveau de log courant de l'application.
# Evite la répétition de l'algo partout dans les utilitaires et l'application.
# $1        : Le niveau à tester contre le niveau de log courant
log_is_at_least() {
    local level="${1:-}"

    [[ -z "$level" ]] && return 1
    (( "$LOG_LEVEL" <= "$level" ))
}

log_msg() {
    local color=""
    local level="$LOG_INFO"

    # Options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c) color="$2" ; shift 2 ;;
            -l) level="$2" ; shift 2 ;;
            --) shift; break ;;  # fin des options
            *) break ;;
        esac
    done

    # Le message correspond à tout ce qui n'a pas été parser
    local msg="$*"

    # Vérifier que le niveau de log courant permet la publication du message
    log_is_at_least "$level" || return 0

    # Applique la couleur
    local prefix=""
    local suffix=""
    if [[ -n "$color" ]]; then
        prefix="\033[${color}m"
        suffix="\033[0m"
    fi

    printf "%b%b%b" "$prefix" "$msg" "$suffix" >&2

}

# Afficher un message de log d'une certaine typologie.
# Chaque à son niveau de déclenchement et son format propre.
# DEBUG     : Gris      uniquement en niveau DEBUG
# INFO      : Blanc     toujours sauf en SILENT
# SUCCESS   : Vert      toujours sauf en SILENT
# WARN      : Jaune     toujours sauf en SILENT
# ERROR     : Rouge     toujours y compris en SILENT
log_debug() { log_msg -c "90" -l "$LOG_DEBUG" "$@" ; }
log_info() { log_msg "$@" ; }
log_success() { log_msg -c "32" "$@" ; }
log_warn() { log_msg -c "33" "$@" ; }
log_error() { log_msg -c "31" -l "$LOG_SILENT" "$@" ; }
