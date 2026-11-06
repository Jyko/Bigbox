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
        return
    fi

    # En info et silent nous capturons stdout et stderr pour éviter de log toutes les commandes.
    # Le "|| status=$?" est indispensable : avec errexit, une affectation en échec arrêterait le script
    # avant que nous ayons pu logger l'erreur.
    local output status=0
    output="$("$@" 2>&1)" || status=$?

    # En cas d'erreur, nous loggons stderr
    if (( status != 0 )); then
        log_error "🧨 code:${status} '$*'\n"
        # Réinjection du stderr sans modifier son format pour une meilleure compréhension des erreurs
        printf "%s\n" "$output" >&2
    fi

    return "$status"
}

# Wrapper universel de commandes qui ne print pas les erreurs en mode autre que debug
# Utile pour les functions utilisées comme condition, dont on attend qu'elles retournent 0 ou 1 en comportement nominal.
# Contrôle les flux stdin/stdout/stderr des commandes executés.
# $@        : La commande à executer
run_cmd_silently() {

    # En débug nous ne contrôlons pas stdout ou stderr et laissons le comportement par défaut.
    if log_is_debug; then
        "$@"
    else
        # En info et silent nous jetons stdout et stderr, seul le code retour compte
        "$@" >/dev/null 2>&1
    fi
}

# Décorateur pour apt-get afin que celui-ci passe en mode non-interractif complet et
# ne redirige aucun flux vers /dev/tty, bloquant ainsi les scripts.
apt_wrapper() {
    if log_is_debug; then
        # Comportement normal
        run_cmd sudo apt-get -y "$@"
    else 
        # Mode silencieux complet
        run_cmd sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o=Dpkg::Use-Pty=0 "$@" </dev/null >/dev/null 2>&1
    fi
}

parse_args() {

    # --------------------
    # Action
    # --------------------

    # Nous affichons l'aide si l'utilisateur :
    # - Ne fourni pas d'action
    # - Ne fourni pas une action valide
    if [[ $# -eq 0 ]]; then
        return 1
    fi

    # Si c'est un flag global, on ne déclenche pas de test ou d'erreur et on poursuit
    # Sinon on considère que çà doit être une commande
    case "$1" in
        -s|--silent|-d|--debug|-h|--help|-v|--version|-b|--banner|--ee|--easter-eggs|-m|--module)
            ;;
        *)
            if ! action_is_valid "$1"; then
                log_error "\r\t❌ \"$1\" n'est pas une action valide\n"
            else
                ACTION="$1"
            fi
            
            # Nous retirons l'action (valide ou non) des params restants à parser, il ne doit reste que des options
            shift 
            ;;
    esac

    # --------------------
    # Options
    # --------------------
    # Nous parsons le reste des arguments qui doivent être uniquement des options connues et valides
    while [[ $# -gt 0 ]]; do

        # Si le paramètre est un flag connu
        case "$1" in
            -s|--silent)
                log_set_silent
                shift
                ;;
            -d|--debug)
                log_set_debug
                shift
                ;;
            -h|--help)
                SHOW_HELP=1
                shift
                ;;
            -v|--version)
                SHOW_VERSION=1
                shift
                ;;
            -b|--banner)
                SHOW_BANNER=1
                shift
                ;;
            --ee|--easter-eggs)
                SHOW_EE=1
                shift
                ;;
            -m|--module)
                # Nous splittons l'argument 2 (-m étant le $1, ce qui suit sera $2) sur la base d'un séparateur ',' et obtenons la whitelist
                IFS=',' read -ra modules <<< "$2"
                MODULE_WHITELIST+=("${modules[@]}")
                # Notre argument est en fait 2 arguments pour bash, nous passons donc 2 arguments
                shift 2
                ;;
            *)
                log_error "\r\t❌ Option non supportée : $1\n"
                # Break au premier argument non parsable
                return 1
                ;;
        esac
    done

    # FIXME : Une logique plus propre en plusieurs étapes de la récupération de l'action et des flags please >:[]
    if [[ -z "$ACTION" ]]; then
        # Si nous n'avons pas récupérer d'action en premier argument, nous considérons que nous avons échoué à parser les paramètres, mais nous avons tout de même lu les flags suivants.
        return 1
    fi

    # --------------------
    # Contrôles de cohérence des arguments
    # --------------------

    # Si nous avons une action qui n'est pas modulaire et que l'utilisateur fourni une whitelist
    if [[ $(action_get_property "modulable") == "false" ]] && [[ ${#MODULE_WHITELIST[@]} -gt 0 ]]; then
        log_error "\r\t❌ L'action n'est pas modulaire et n'accepte pas d'arguments [-m|--module]\n"
        return 1
    fi
}

get_host_ip() {
    local host_ip

    # Nous tentons de détecter si nous sommes sur un WSL2
    # Si nous sommes sur une WSL2, nous récupérons lIP du Windows host via le nameserver dans /etc/resolv.conf
    if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
        host_ip=$(grep nameserver /etc/resolv.conf | awk '{print $2}')
        echo "$host_ip"
        return 0
    fi

    # Nous tentons de détecter si nous sommes sur un Ubuntu standalone (server, desktop, container)
    if command -v hostname &> /dev/null; then
        host_ip=$(hostname -I | awk '{print $1}')
        echo "$host_ip"
        return 0
    fi

    log_error "Impossible de détecter l'environnement d'exécution de la Bigbox et donc l'IP de l'Host\n" >&2
    return 2
}