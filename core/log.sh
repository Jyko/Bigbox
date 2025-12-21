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

# Affichage d'un message de début d'action d'un module
# $1 : message
log_action_start() {
    local module="$1"
    local action="$2"
    local max_length="${3:-10}"

    printf "\r\t⏳ [%-*s]\t%s" "$max_length" "$module" "$action"
}

# Affichage d'un message de fin d'action d'un module avec réaction au mod DEBUG
# $1 module     : Le nom du module
# $2 action     : L'action lancée sur ce module
# $3 status     : Le status d'exécution de cette action (0=success, autre=erreur, optionnel, défaut 0)
# $4 : stdout de la commande lancée (optionnel)
# $5 : stderr de la commande lancée (optionnel)
log_action_end() {
    local module="$1"
    local action="$2"
    local max_length="${3:-10}"
    local status="${4:-0}"
    local std_out="${5:-}"
    local std_err="${6:-}"

    if (( "$status" == 0 )); then
        printf "\r\t✅ [%-*s]\t%s\n" "$max_length" "$module" "$action"
        if [[ "$DEBUG" == "true" ]]; then
            printf "%s" "$std_out"
        fi
    else
        printf "\r\t❌ [%-*s]\t%s\n" "$max_length" "$module" "$action"
        if [[ "$DEBUG" == "true" ]]; then
            printf "%s" "$std_out"
        fi
        printf "%s" "$std_err"
    fi
}

# Affichage d'un message pour un module ne disposant pas d'implémentation pour l'action lancée
# $1 module     : Le nom du module
# $2 action     : L'action lancée sur ce module
log_action_not_implemented() {
    local module="$1"
    local action="$2"
    local max_length="${3:-10}"

    printf "\r\t❔ [%-*s]\t%s\n" "$max_length" "$module" "$action"
    
}