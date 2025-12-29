#!/usr/bin/env bash
# shellcheck shell=bash

###################################
# Utilitaires communs génériques #
###################################

# Wrapper universel de commandes
# Contrôle les flux stdin/stdout/stderr des commandes executés.
# $@        : La commande à executer
run_cmd() {

    # En débug nous ne contrôlons pas stdout ou stderr et laissons le comportement par défaut.
    if log_is_debug; then
        "$@"
    else
        # En info et silent nous capturons stdout et stderr pour éviter de log toutes les commandes
        local output
        output="$("$@" 2>&1)"
        local status=$?
        
        # En cas d'erreur, nous loggons stderr
        if (( status != 0 )); then
            log_error "🧨 code:${status:-1} '$@'"
            # Réinjection du stderr sans modifier son format pour une meilleure compréhension des erreurs
            printf "%s\n" "$output" >&2
        fi

        return $status
    fi
}

# Décorateur pour apt-get afin que celui-ci passe en mode non-interractif complet et
# ne redirige aucun flux vers /dev/tty, bloquant ainsi les scripts.
apt_wrapper() {
    if log_is_debug; then
        # Comportement normal
        sudo apt-get -y "$@"
    else 
        # Mode silencieux complet
        sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -qq "$@" </dev/null
    fi
}

is_valid_action() {
    local action="$1"

    for a in "${BB_ALLOWED_ACTIONS[@]}"; do
        [[ "$a" == "$action" ]] && return 0
    done

    return 1
}

verify_action() {

    if [[ "$ACTION_SET" == true ]]; then
        echo "Une seule action est autorisée à la fois"
        echo "Pour obtenir de l'aide : bigbox.sh help"
        exit 1
    fi

}