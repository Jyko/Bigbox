#!/usr/bin/env bash
# shellcheck shell=bash

# Liste des modules chargés ordonnée par priorité d'exécution
declare -A MODULES

load_modules() {

    # Charger tous les modules
    for module in "$BB_MOD_DIR"/*/*.sh; do

        log_debug "\r\t⏳ Chargement du module $module"

        source "$module"

        if [[ -z "$MODULE_NAME" || -z "$MODULE_PRIORITY" ]]; then
            log_error "\r\t❌ Chargement échoué du module $module\n"
            exit 1
        fi

        MODULES["$MODULE_PRIORITY"]="$MODULE_NAME"

        log_debug "\r\t✅ Chargement réussi du module $module\n"

        unset MODULE_NAME MODULE_PRIORITY

    done

}

run_modules() {
    local action="$1"

    # Nous récupérons la configuration de l'action dans le resources/action.json
    local action_config_file="$BB_RSC_DIR/action.json"
    local order_config
    local sort_args=(-n)

    order_config=$(jq -r ".\"$action\".order // \"asc\"" "$action_config_file")

    if [[ "$order_config" == "desc" ]]; then
        sort_args+=(-r)
    fi

    # Pour chaque module enregistré et trié, nous exécutons l'action
    for module_priority in $(printf "%s\n" "${!MODULES[@]}" | sort "${sort_args[@]}"); do

        module="${MODULES[$module_priority]}"
        func="${module}_${action}"

        # Si le module ne dispose pas de l'action nous écrivons un message de skip
        if ! declare -f "$func" >/dev/null; then
            log_warn "\r\t❔ [$module] $action\n"
            continue
        fi

        log_success "\r\t⏳ [$module] $action"
        "$func"
        local status=$?
        
        if (( status ==  0 )); then
            log_success "\r\t✅ [$module] $action\n"
        else
            log_error "\r\t❌ [$module] $action\n"
            exit "$status"
        fi

    done
    
}