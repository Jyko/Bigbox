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
        # Mode silencieux : run_cmd capture déjà stdout/stderr et ne les affiche qu'en cas d'erreur.
        # Ne surtout pas rediriger la sortie de run_cmd elle-même, sinon son log d'erreur disparaît.
        run_cmd sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -qq -o=Dpkg::Use-Pty=0 "$@" </dev/null
    fi
}

# Retourne 0 si ce paquet est installé
# $1 : Le nom du paquet
apt_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# Installer des paquets (noms ou fichiers .deb) et enregistrer dans le registre ceux qui ne l'étaient pas.
# Les paquets déjà présents ne sont pas réinstallés : apt les marquerait comme installés manuellement,
# et ils ne seront jamais purgés à la désinstallation.
# $@ : Les paquets ou fichiers .deb
apt_install() {
    local arg pkg
    local to_install=() to_mark=()

    for arg in "$@"; do
        if [[ "$arg" == *.deb ]]; then
            pkg=$(dpkg-deb -f "$arg" Package)
        else
            pkg="$arg"
        fi

        if ! apt_is_installed "$pkg"; then
            to_install+=("$arg")
            to_mark+=("$pkg")
        fi
    done

    if (( ${#to_install[@]} == 0 )); then
        return 0
    fi

    apt_wrapper install "${to_install[@]}"

    for pkg in "${to_mark[@]}"; do
        state_mark_owned "apt:$pkg"
    done
}

# Purger, parmi ces paquets, uniquement ceux que la Bigbox a installés (voir apt_install).
# Un paquet présent avant la Bigbox (ex. htop sur un Ubuntu Desktop) est conservé.
# $@ : Les paquets à purger
apt_purge_owned() {
    local pkg
    local owned=()

    for pkg in "$@"; do
        if state_is_owned "apt:$pkg" && apt_is_installed "$pkg"; then
            owned+=("$pkg")
        fi
    done

    if (( ${#owned[@]} > 0 )); then
        apt_wrapper purge "${owned[@]}"
    fi

    for pkg in "$@"; do
        state_unmark "apt:$pkg"
    done
}

# Les variables de contrôle (SHOW_*) sont lues par menu.sh
# shellcheck disable=SC2034
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
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    log_error "\r\t❌ L'option $1 attend une liste de modules : $1 mod1,mod2\n"
                    return 1
                fi
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

# Envoyer SIGTERM à tous les descendants d'un processus (les plus profonds d'abord)
# $1 pid        : Le processus dont les descendants sont tués
# $2 exclude    : Un PID à épargner, avec ses descendants (optionnel)
# Les processus lancés via sudo appartiennent à root et ne peuvent pas être tués ainsi.
utils_kill_descendants() {
    local pid="$1"
    local exclude="${2:-}"
    local children child

    mapfile -t children < <(pgrep -P "$pid" || true)

    for child in "${children[@]}"; do
        [[ -z "$child" || "$child" == "$exclude" ]] && continue
        utils_kill_descendants "$child" "$exclude"
        kill -TERM "$child" 2>/dev/null || true
    done
}

# Retourne 0 si la Bigbox s'exécute dans une distribution WSL, sinon 1
utils_is_wsl() {
    grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null
}

get_host_ip() {
    local host_ip

    # Si nous sommes sur une WSL2, nous récupérons l'IP du Windows host via le nameserver dans /etc/resolv.conf
    if utils_is_wsl; then
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