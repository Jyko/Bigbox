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
LOG_LEVEL="$LOG_DEBUG"

# ====================
# Gestion du niveau de logs
# ====================
log_set_silent() { LOG_LEVEL=$LOG_SILENT ; }
log_set_info() { LOG_LEVEL=$LOG_INFO ; }
log_set_debug() { LOG_LEVEL=$LOG_DEBUG ; }

# ====================
# Fonctions
# ====================

# Retourner 0 si ce niveau de log est au moins égal au niveau de log courant de l'application.
# Evite la répétition de l'algo partout dans les utilitaires et l'application.
# $1        : Le niveau à tester contre le niveau de log courant
log_is_at_least() { (($LOG_LEVEL <= $1)) ; }

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

    printf "%b%b%b" "$prefix" "$msg" "$suffix"

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
log_warn() { log_msg -c "33" -l "$@" ; }
log_error() { log_msg -c "31" -l "$SILENT" "$@" >&2 ; }

show_infos() {

    if [[ "$SHOW_BANNER" == "true" ]]; then
        show_banner
    fi

    if [[ "$SHOW_EASTER_EGGS" == "true" ]]; then
        show_easter_eggs
    fi

    if [[ "$DEBUG" == "true" ]]; then
        show_debug_status
    fi

}

# Afficher la bannière
show_banner() {

    local entreprise

    if [[ $SHOW_EASTER_EGGS == "true" ]]; then
        entreprise="🐒 BOUGARD 🐒"
    fi


    cat \
<<-EOF
    
    ██████╗ ██╗ ██████╗ ██████╗  ██████╗ ██╗  ██╗ 
    ██╔══██╗██║██╔════╝ ██╔══██╗██╔═══██╗╚██╗██╔╝ 
    ██████╔╝██║██║  ███╗██████╔╝██║   ██║ ╚███╔╝  
    ██╔══██╗██║██║   ██║██╔══██╗██║   ██║ ██╔██╗  
    ██████╔╝██║╚██████╔╝██████╔╝╚██████╔╝██╔╝ ██╗    
    ╚═════╝ ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ 
    📦      La boîte à outils ${entreprise:-Bigard}

EOF

}

show_debug_status() {

    cat \
<<-EOF
    🐞      Le mode DEBUG est activé
EOF

}

# Afficher les easters eggs
show_easter_eggs() {

    cat \
<<-EOF
    ✒️  Auteur :
        🐒  Julien FERREIRA DA COSTA

    🔬  Testeurs :
        🐴  Anne-Sophie
        💪  Baptiste
        🔨  Guillaume   
        💎  Iwan        
        💣  Kévin
        🏸  Stéphane    
        🍅  Valérian
    
    🎤  Cassedédi :
        🥃  Benjamin
        🌸  François
        🌿  Tous mes gars sûrs du 93/94, les "maraîchers" et les "vendeurs sur les marchés" !

    ❤️  Merci, c'est grâce à vous que je n'ai pas encore sauté par la Sainte-Fenêtre ! 🪟
    
EOF

}
