#!/usr/bin/env bash
# shellcheck shell=bash

# Liste des modules chargés ordonnée par priorité d'exécution
declare -A MODULES=()

# Index de tous les modules disponibles : nom -> chemin de son module.json
declare -A MODULE_DESCRIPTORS=()
# Index des priorités : nom -> priorité
declare -A MODULE_PRIORITIES=()
# Modules retenus pour l'action (liste fournie par -m, complétée par la résolution des dépendances)
declare -A MODULE_SELECTION=()

module_load() {

    _module_index
    _module_resolve_selection

    local name descriptor entrypoint priority
    for name in "${!MODULE_SELECTION[@]}"; do

        descriptor="${MODULE_DESCRIPTORS[$name]}"
        priority="${MODULE_PRIORITIES[$name]}"
        entrypoint="$(dirname "$descriptor")/$(jq -r '.entrypoint // empty' "$descriptor")"

        log_debug "\r\t⏳ Chargement du module $name"

        # Un module retenu (par exemple par dépendance) peut ne pas déclarer l'action : il est simplement ignoré
        if ! _module_has_declared_action "$descriptor"; then
            log_debug "\r\t⏭️ Le module $name ne déclare pas l'action $ACTION\n"
            continue
        fi

        # shellcheck source=/dev/null
        source "$entrypoint"

        MODULES["$priority"]="$name"

        log_debug "\r\t✅ Chargement réussi du module $name\n"
    done

    # Chargement terminé, nous passons la variable globale MODULES en readonly, nous n'avons plus aucune raison de la modifier à partir de maintenant.
    readonly MODULES

    if (( ${#MODULES[@]} == 0 )); then
        log_warn "\r\t❗ Aucun module chargé, vérifiez la compatibilité des modules listés avec l'action demandée\n"
    fi

}

# Indexer et valider tous les descripteurs de modules (modules/*/module.json)
_module_index() {
    local descriptor path name priority entrypoint
    declare -A seen_priorities=()

    for descriptor in "$BB_MOD_DIR"/*/module.json; do
        path=$(dirname "$descriptor")

        # "// empty" : une propriété absente donne une chaîne vide et non "null"
        name=$(jq -r '.name // empty' "$descriptor")
        priority=$(jq -r '.priority // empty' "$descriptor")
        entrypoint="$path/$(jq -r '.entrypoint // empty' "$descriptor")"

        if ! _module_verify -n="$name" -p="$priority" -e="$entrypoint"; then
            log_error "Le chargement du descripteur de module $descriptor a échoué\n"
            exit 1
        fi

        # Deux modules de même priorité s'écraseraient dans MODULES, l'un des deux ne serait jamais exécuté
        if [[ -n "${seen_priorities[$priority]:-}" ]]; then
            log_error "Les modules ${seen_priorities[$priority]} et $name ont la même priorité $priority\n"
            exit 1
        fi
        seen_priorities["$priority"]="$name"

        MODULE_DESCRIPTORS["$name"]="$descriptor"
        MODULE_PRIORITIES["$name"]="$priority"
    done

    # Une dépendance doit exister et passer avant le module qui en dépend (priorité inférieure),
    # sinon l'ordre d'exécution par priorité ne respecterait pas les dépendances.
    local dep
    for name in "${!MODULE_DESCRIPTORS[@]}"; do
        while IFS= read -r dep; do
            [[ -z "$dep" ]] && continue
            if [[ -z "${MODULE_DESCRIPTORS[$dep]:-}" ]]; then
                log_error "Le module $name dépend du module inconnu $dep\n"
                exit 1
            fi
            if (( MODULE_PRIORITIES[$dep] >= MODULE_PRIORITIES[$name] )); then
                log_error "Le module $name (priorité ${MODULE_PRIORITIES[$name]}) dépend de $dep (priorité ${MODULE_PRIORITIES[$dep]}) : une dépendance doit avoir une priorité inférieure\n"
                exit 1
            fi
        done < <(jq -r '.dependencies[]?' "${MODULE_DESCRIPTORS[$name]}")
    done
}

# Retourner sur stdout les dépendances directes d'un module
# $1 : Le nom du module
_module_dependencies() {
    jq -r '.dependencies[]?' "${MODULE_DESCRIPTORS[$1]}"
}

# Retourner sur stdout les modules qui dépendent directement d'un module
# $1 : Le nom du module
_module_dependents() {
    local name
    for name in "${!MODULE_DESCRIPTORS[@]}"; do
        if jq -e --arg dep "$1" '(.dependencies // []) | index($dep)' "${MODULE_DESCRIPTORS[$name]}" >/dev/null; then
            echo "$name"
        fi
    done
}

# Construire MODULE_SELECTION à partir de la liste -m et du sens de résolution de l'action :
# - forward (install, start, upgrade) : ajout des dépendances, ex. install -m pg installe aussi k8s (k3s)
# - reverse (uninstall, stop)         : ajout des dépendants, ex. uninstall -m pg désinstalle aussi hoppscotch
# Sans -m, tous les modules sont retenus.
_module_resolve_selection() {
    local name

    if (( ${#MODULE_WHITELIST[@]} == 0 )); then
        for name in "${!MODULE_DESCRIPTORS[@]}"; do
            MODULE_SELECTION["$name"]=1
        done
        return 0
    fi

    local direction
    direction=$(action_get_property "dependencies" "forward")

    local queue=()
    for name in "${MODULE_WHITELIST[@]}"; do
        if [[ -z "${MODULE_DESCRIPTORS[$name]:-}" ]]; then
            log_error "\r\t❌ Module inconnu : $name\n"
            exit 1
        fi
        queue+=("$name")
    done

    local current related
    local added=()
    while (( ${#queue[@]} > 0 )); do
        current="${queue[0]}"
        queue=("${queue[@]:1}")

        [[ -n "${MODULE_SELECTION[$current]:-}" ]] && continue
        MODULE_SELECTION["$current"]=1

        while IFS= read -r related; do
            [[ -z "$related" || -n "${MODULE_SELECTION[$related]:-}" ]] && continue
            queue+=("$related")
            added+=("$related")
        done < <(if [[ "$direction" == "reverse" ]]; then _module_dependents "$current"; else _module_dependencies "$current"; fi)
    done

    if (( ${#added[@]} > 0 )); then
        local label="dépendances"
        [[ "$direction" == "reverse" ]] && label="modules dépendants"
        log_info "\t🔗 Ajout des $label : $(printf '%s\n' "${added[@]}" | sort -u | paste -sd ' ')\n"
    fi
}

module_run() {

    # Nous récupérons la configuration de l'action dans le resources/action.json
    local order is_reboot_wanted module module_priority func
    local sort_args=(-n)

    if [[ -z "$ACTION" ]]; then
        log_error "L'action à executer est obligatoire\n"
        exit 2
    fi

    order=$(action_get_property "order" "asc")
    is_reboot_wanted=$(action_get_property "reboot")

    if [[ "$order" == "desc" ]]; then
        sort_args+=(-r)
    fi

    # Avec errexit, la première commande en échec d'un module arrête la Bigbox.
    # Le trap ERR (hérité par les fonctions grâce à errtrace) permet d'indiquer quel module a échoué.
    set -o errtrace
    trap '_module_on_error "$?" "$module"' ERR

    local priorities
    mapfile -t priorities < <(printf "%s\n" "${!MODULES[@]}" | sort "${sort_args[@]}")

    # Pour chaque module enregistré et trié, nous exécutons l'action
    for module_priority in "${priorities[@]}"; do

        module="${MODULES[$module_priority]}"
        func="${module}_${ACTION}"

        # Si le module ne dispose pas de l'action qu'il déclarait pourtant dans son module.json, nous arrêtons la Bigbox
        if ! declare -f "$func" >/dev/null; then
            log_error "\t❌  [$module] $ACTION non implementée\n"
            exit 2
        fi

        log_success "\t⏳ [$module] $ACTION"
        _module_watchdog_start "$module"
        "$func"
        _module_watchdog_stop
        log_success "\r\t✅ [$module] $ACTION\n"

    done

    trap - ERR
    set +o errtrace

    # Dépendances apt devenues orphelines après la purge des paquets des modules (ex. pigz, libpq5)
    if [[ "$(action_get_property "autoremove" "false")" == "true" ]]; then
        log_success "\t⏳ Suppression des paquets orphelins (apt autoremove)"
        # --purge : comme pour les paquets des modules, aucune configuration résiduelle (état "rc")
        apt_wrapper autoremove --purge
        log_success "\r\t✅ Suppression des paquets orphelins (apt autoremove)\n"
    fi

    if [[ "$is_reboot_wanted" == "true" ]]; then
        log_warn "\r\t ⚠️ Relancez votre shell ou executez \`source \$HOME/.bashrc\` pour prendre en compte la nouvelle configuration du shell ⚠️\n"
    fi
    
}

# Garde contre les attentes prolongées : un processus de surveillance tue les commandes en cours
# du module si son action dépasse BB_MODULE_TIMEOUT secondes. La commande tuée échoue, ce qui
# déclenche le trap ERR et arrête la Bigbox avec le message habituel.
# $1 module : Le nom du module surveillé
_module_watchdog_start() {
    local module="$1"
    local bigbox_pid="$$"

    (
        trap - ERR
        set +e
        sleep "$BB_MODULE_TIMEOUT"
        log_error "\r\t⏱️  [$module] $ACTION dépasse ${BB_MODULE_TIMEOUT}s : arrêt des commandes en cours (BB_MODULE_TIMEOUT pour ajuster)\n"
        utils_kill_descendants "$bigbox_pid" "$BASHPID"
    ) &
    BB_MODULE_WATCHDOG_PID=$!
    # disown : pas de notification "Terminated" quand la surveillance est arrêtée
    disown "$BB_MODULE_WATCHDOG_PID"
}

_module_watchdog_stop() {
    if [[ -z "${BB_MODULE_WATCHDOG_PID:-}" ]]; then
        return 0
    fi

    # L'ordre compte : la surveillance d'abord (sans trap, SIGTERM la termine immédiatement),
    # son sleep ensuite. Tuer le sleep en premier la laisserait reprendre la main et croire le délai écoulé.
    local sleepers
    mapfile -t sleepers < <(pgrep -P "$BB_MODULE_WATCHDOG_PID" || true)

    kill -TERM "$BB_MODULE_WATCHDOG_PID" 2>/dev/null || true
    if (( ${#sleepers[@]} > 0 )) && [[ -n "${sleepers[0]}" ]]; then
        kill -TERM "${sleepers[@]}" 2>/dev/null || true
    fi

    BB_MODULE_WATCHDOG_PID=""
}

# Handler du trap ERR posé par module_run
# $1 status : Le code retour de la commande en échec
# $2 module : Le nom du module en cours d'exécution
_module_on_error() {
    local status="$1"
    local module="$2"

    # errtrace propage aussi le trap dans les substitutions de commande ($(...)), qui n'arrêtent pas le script.
    # Seule une erreur du shell principal est fatale et doit être signalée.
    (( BASH_SUBSHELL == 0 )) || return 0

    _module_watchdog_stop
    log_error "\r\t❌ [$module] $ACTION (code:$status)\n"
}

_module_verify() {
    local name="" priority="" entrypoint=""

    for arg in "$@"; do
        case "$arg" in
            -n=*) name="${arg#-n=}" ;;
            -p=*) priority="${arg#-p=}" ;;
            -e=*) entrypoint="${arg#-e=}" ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    if [[ -z "$name" ]]; then
        log_error "La propriété \"name\" est obligatoire\n"
        return 1
    fi

    if [[ ! "$priority" =~ ^-?[0-9]+$ ]]; then
        log_error "La propriété \"priority\" est obligatoire et doit être un entier\n"
        return 1
    fi

    if [[ ! -f "$entrypoint" ]]; then
        log_error "La propriété \"entrypoint\" est obligatoire et doit pointer vers un fichier executable : \"$entrypoint\"\n"
        return 1
    fi

    return 0
}

# Retourne 0 si l'action est déclarée dans le module.json
# Retourne 1 si l'action n'est pas déclarée dans le module.json
# Retourne 2 si jq retourne une erreur interne (fichier invalide, action fournie null ...)
_module_has_declared_action() {
    local module_file_path="$1"

    if [[ -z "$ACTION" ]]; then
        log_error "L'action à chercher dans \"$module_file_path\" est obligatoire\n"
        exit 2
    fi

    if jq -e --arg action "$ACTION" '.actions | index($action)' "$module_file_path" >/dev/null; then
        log_debug "Le descripteur de module \"$module_file_path\" contient l'action $ACTION\n"
        return 0
    else
        log_debug "Le descripteur de module \"$module_file_path\" ne contient pas l'action $ACTION\n"
        return 1
    fi
}
