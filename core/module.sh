#!/usr/bin/env bash
# shellcheck shell=bash

# Liste des modules chargés ordonnée par priorité d'exécution
declare -A MODULES

module_load() {

    # Charger tous les modules
    for module in "$BB_MOD_DIR"/*/module.json; do

        local path name priority entrypoint

        # Récupérer le root path du module
        path=$(dirname "$module")

        name=$(jq -r '.name' "$module")
        priority=$(jq -r '.priority' "$module")
        entrypoint="$path/$(jq -r '.entrypoint' "$module")"
        
        log_debug "\r\t⏳ Chargement du module $module"

        if ! _module_verify -n="$name" -p="$priority" -e="$entrypoint"; then
            log_error "Le chargement du descripteur de module $path/module.json a échoué\n"
            exit 1
        fi

        if _module_is_whitelisted "$name" && _module_has_declared_action "$module"; then

            source "$entrypoint"

            MODULES["$priority"]="$name"

            log_debug "\r\t✅ Chargement réussi du module $module\n"
        else
            log_debug "\r\t⏭️ Chargement abandonné du module $module\n"
        fi
    done

    # Chargement terminé, nous passons la variable globale MODULES en readonly, nous n'avons plus aucune raison de la modifier à partir de maintenant.
    readonly MODULES

}

module_run() {

    # Nous récupérons la configuration de l'action dans le resources/action.json
    local order
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
        local status=$?
        
        if (( status ==  0 )); then
            log_success "\r\t✅ [$module] $ACTION\n"
        else
            log_error "\r\t❌ [$module] $ACTION\n"
            exit "$status"
        fi

    done

    if [[ "$is_reboot_wanted" == "true" ]]; then
        log_warn "\r\t ⚠️ Relancez votre shell ou executez \`source \$HOME/.bashrc\` pour prendre en compte la nouvelle configuration du shell ⚠️\n"
    fi
    
}

_module_verify() {
    local name priority entrypoint

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

    if [[ -z "$priority" ]]; then
        log_error "La propriété \"priority\" est obligatoire\n"
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