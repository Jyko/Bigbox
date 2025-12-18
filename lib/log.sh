show_debug_status() {

    cat \
<<-EOF
    🐞      Le mode DEBUG est activé
EOF

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

    cat \
<<-EOF
    🏷️       ${version:-"inconnue"}
EOF

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

# Afficher les easters eggs
show_easter_eggs() {

    cat \
<<-EOF

    ✒️  Auteur :
        🐒  Julien FERREIRA DA COSTA

    🔬  Testeurs :
        🐴  Anne-Sophie KRAWSJ... Anne-So quoi !
        💪  Baptiste    BEAUVAIS
        🔨  Guillaume   
        💎  Iwan        
        💣  Kévin       NAU
        🏸  Stéphane    
        🍅  Valérian    DELEEUW
    
    🎤  Cassedédi :
        🥃  Benjamin    PERTUISEL
        🌸  François    BELLEC
        🌿  Tous mes gars sûrs du 93/94, les "maraîchers" et les "vendeurs sur les marchés" !

    ❤️  Merci, c'est grâce à vous que je n'ai pas encore sauté par la Sainte-Fenêtre ! 🪟
EOF

}

# Afficher l'aide
show_help() {

    cat \
<<-EOF
Usage: install.sh [options]

    Options:
    -d, --debug       Activer le mode debug
    -h, --help        Afficher ce message d'aide
    -v, --version     Afficher la version
    --no-banner       Ne pas afficher la bannière au démarrage (c'est un manque de goût évident, mais je ne juge pas)
EOF

}

show_infos() {

    if [[ "$SHOW_BANNER" == "true" ]]; then
        show_banner
    fi

    if [[ "$SHOW_VERSION" == "true" ]]; then
        show_version
    fi

    if [[ "$SHOW_EASTER_EGGS" == "true" ]]; then
        show_easter_eggs
    fi

    if [[ "$DEBUG" == "true" ]]; then
        show_debug_status
    fi

    echo -e "\n"
}

# Affichage d'un message de début d'étape
# $1 : message
# $2 : emoji (optionnel)
log_step_start() {

    local msg="$1"
    local emoji="$2"

    echo -e "\r$emoji $msg"
}

# Affichage d'un message de début d'action
# $1 : message
log_task_start() {
    local msg="$1"
    echo -ne "\r\t⏳ $msg"
}

# Affichage d'un message de fin d'action dépendant de son statut
# $1 : message
# $2 : status de la commande lancée (0=success, autre=erreur, optionnel, défaut 0)
# $3 : stdout de la commande lancée (optionnel)
# $4 : stderr de la commande lancée (optionnel)
log_task_end() {
    local msg="$1"
    local status="${2:-0}"
    local std_out="${3:-}"
    local std_err="${4:-}"

    if (( "$status" == 0 )); then
        echo -e "\r\t✅ $msg"
        if [[ "$DEBUG" == "true" ]]; then
            printf '%s\n' "$std_out"
        fi
    else
        echo -e "\r\t❌ $msg"
        if [[ "$DEBUG" == "true" ]]; then
            printf '%s\n' "$std_out"
        fi
        printf '%s\n' "$std_err"
    fi
}