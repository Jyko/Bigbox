#!/usr/bin/env bash
# shellcheck shell=bash

# Liste des modules chargés ordonnée par priorité d'exécution
declare -A MODULES=()

module_load() {

    # Charger tous les modules
    for module in "$BB_MOD_DIR"/*/module.json; do

        local path name priority entrypoint

        # Récupérer le root path du module
        path=$(dirname "$module")

        # "// empty" : une propriété absente donne une chaîne vide et non "null"
        name=$(jq -r '.name // empty' "$module")
        priority=$(jq -r '.priority // empty' "$module")
        entrypoint="$path/$(jq -r '.entrypoint // empty' "$module")"
        
        log_debug "\r\t⏳ Chargement du module $module"

        if ! _module_verify -n="$name" -p="$priority" -e="$entrypoint"; then
            log_error "Le chargement du descripteur de module $path/module.json a échoué\n"
            exit 1
        fi

        if _module_is_whitelisted "$name" && _module_has_declared_action "$module"; then

            # Deux modules de même priorité s'écraseraient dans MODULES, l'un des deux ne serait jamais exécuté
            if [[ -n "${MODULES[$priority]:-}" ]]; then
                log_error "Les modules ${MODULES[$priority]} et $name ont la même priorité $priority\n"
                exit 1
            fi

            # shellcheck source=/dev/null
            source "$entrypoint"

            MODULES["$priority"]="$name"

            log_debug "\r\t✅ Chargement réussi du module $module\n"
        else
            log_debug "\r\t⏭️ Chargement abandonné du module $module\n"
        fi
    done

    # Chargement terminé, nous passons la variable globale MODULES en readonly, nous n'avons plus aucune raison de la modifier à partir de maintenant.
    readonly MODULES

    if (( ${#MODULES[@]} == 0 )); then
        log_warn "\r\t❗ Aucun module chargé, vérifiez la compatibilité des modules listés avec l'action demandée\n"
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

    # Pour chaque module enregistré et trié, nous exécutons l'action
    for module_priority in $(printf "%s\n" "${!MODULES[@]}" | sort "${sort_args[@]}"); do

        module="${MODULES[$module_priority]}"
        func="${module}_${ACTION}"

        # Si le module ne dispose pas de l'action qu'il déclarait pourtant dans son module.json, nous arrêtons la Bigbox
        if ! declare -f "$func" >/dev/null; then
            log_error "\t❌  [$module] $ACTION non implementée\n"
            exit 2
        fi

        log_success "\t⏳ [$module] $ACTION"
        "$func"
        log_success "\r\t✅ [$module] $ACTION\n"

    done

    trap - ERR
    set +o errtrace

    if [[ "$is_reboot_wanted" == "true" ]]; then
        log_warn "\r\t ⚠️ Relancez votre shell ou executez \`source \$HOME/.bashrc\` pour prendre en compte la nouvelle configuration du shell ⚠️\n"
    fi
    
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

# Retourne 0 si le module est whitelisté
# Retourne 1 si le module n'est pas whitelisté
# Exit 2 si le module est null ou blanc
_module_is_whitelisted() {
    local module_name="$1"

    if [[ -z "$module_name" ]]; then
        log_error "Le nom du module à tester en obligatoire\n"
        exit 2
    fi

    # Si l'utilisateur n'a pas fourni de whitelist, tous les modules sont acceptés
    [[ ${#MODULE_WHITELIST[@]} -eq 0 ]] && return 0

    for wm in "${MODULE_WHITELIST[@]}"; do
        if [[ "$wm" == "$module_name" ]]; then
            log_debug "Le module $module_name est whitelisté\n"
            return 0
        fi
    done

    log_debug "Le module $module_name n'est pas whitelisté\n"
    return 1
}