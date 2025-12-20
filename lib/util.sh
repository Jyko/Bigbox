parse_args() {
    for arg in "$@"; do
        case "$arg" in
            -d|--debug)
                DEBUG=true
                shift
                ;;
            --no-banner)
                SHOW_BANNER=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --ee|--easter-eggs)
                SHOW_EASTER_EGGS=true
                shift
                ;;
            -v|--version)
                SHOW_VERSION=true
                shift
                ;;
            *)
                echo "Argument non supporté : $1"
                exit 1
                ;;
        esac
    done
}

# Exécuter une étape avec des logs et une gestion d'erreur
# $1 : message descriptif de l'étape
# $2 : emoji descritive de l'étape (optionnel, défaut "⚙️")
step() {
    
    local msg="$1"
    local emoji="${2:-⚙️}"

    log_step_start "$msg" "$emoji"

}

# Décorateur d'exécution d'une tâche pour y gérer les logs et les erreurs
# $1 : message descriptif de la tâche
# $2... : commande à exécuter
task() {
    local msg="$1"
    shift

    log_task_start "$msg"

    local status

    if [[ "$DEBUG" == "true" ]]; then
        # Obtenir les stdout/stderr du sous-shell directement (donc sans filtrage)
        "$@"

        status=$?
        log_task_end "$msg" "$status"
    else
        # Capturer les stdout/stderr dans des process substitutions afin de les filtrer
        local ps_out ps_err
        ps_out=$(mktemp)
        ps_err=$(mktemp)

        "$@" >"$ps_out" 2>"$ps_err"

        status=$?
        local out err
        out=$(<"$ps_out")
        err=$(<"$ps_err")
        log_task_end "$msg" "$status" "$out" "$err"

        # Nettoyage des fichiers temporaires
        rm -rf "$ps_out" "$ps_err"
    fi

    # Pour éviter d'écraser les messages de log et mettre une tempo entre les commandes
    sleep 0.1

    # Gestion des erreurs remontées par l'exécution
    if (( status != 0 )); then
        exit "$status"
    fi

}

# Décorateur pour apt-get afin que celui-ci passe en mode non-interractif complet et
# ne redirige aucun flux vers /dev/tty, bloquant ainsi les scripts.
apt_wrapper() {
    sudo env DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

# Décorateur pour snapd afin de gérer les installations déjà existantes
# $1 cmd : La commande Snapd à exécuter
# $2 snap : Le package Snap contre lequel jouer la commande Snapd
# $3 flags... : Les flags supplémentaires (optionnal)
snap_wrapper() {
    local cmd="$1"
    local snap="$2"
    local flags="${3:-}"

    case "$cmd" in
        install|refresh|remove)
            ;;
        *)
            echo "Commande non supportée: $cmd" >&2
            return 1
            ;;
    esac

    local installed=$(snap list "$snap" >/dev/null 2>&1 && echo 1 || echo 0 )

    # Vérifier si le snap est déjà installé
    if [[ "$cmd" == "install" ]] && (( installed )); then
        return 0
    fi

    # Installer le snap si il ne l'est pas lors d'une tentative de refresh
    if [[ "$cmd" == "refresh" ]] && (( ! $installed )); then
        cmd="install"
    fi

    # Ne rien faire si le snap est déjà désintallé
    if [[ "$cmd" == "remove" ]] && (( ! $installed )); then
        return 0
    fi

    sudo snap install $snap $flags
    
}

# Retourne la nouvelle valeur d'une variable d'env après la concaténation de cette valeur
# avec les anciennes connues. Ne modifie pas cette variable d'env.
#
# $1 var        : Le nom de cette variable d'env
# $2 value      : La nouvelle valeur de cette variable d'env à concaténer ou remplacer
# $3 separator  : Le séparateur entre chaque valeur de la variable d'env, si celui-ci est différent
#                 de ":" (optionnal) (default: ":")
#
# Exemple :
#
# KUBECONFIG:$HOME/.kube/config
# echo "$(add_value_to_varenv KUBECONFIG "$HOME/.kube/nouvelle_valeur)"
# $ $HOME/.kube/config:$HOME/.kube/nouvelle_valeur
# echo KUBECONFIG
# $ $HOME/.kube/config
append_value_to_var() {
    local var="$1"
    local value="$2"
    local separator="${3:-:}"

    local current_value="${!var}"
    local result

    case "$separator$current_value$separator" in
        *"$separator$value$separator"*)
            result="$current_value"
            ;;
        *)
            if [[ -n "$current_value" ]]; then
                result="$current_value$separator$value"
            else
                result="$value"
            fi
            ;;
    esac

    echo "$result";

}