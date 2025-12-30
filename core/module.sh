#!/usr/bin/env bash
# shellcheck shell=bash

# Liste des modules chargés ordonnée par priorité d'exécution
declare -A MODULES

module_verify() {
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
        log_error "La propriété \"name\" est obligatoire \n"
        return 1
    fi

    if [[ -z "$priority" ]]; then
        log_error "La propriété \"priority\" est obligatoire \n"
        return 1
    fi

    if [[ ! -f "$entrypoint" ]]; then
        log_error "La propriété \"entrypoint\" est obligatoire et doit pointer vers un fichier executable : \"$entrypoint\" \n"
        return 1
    fi

    return 0
}

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

        if ! module_verify -n="$name" -p="$priority" -e="$entrypoint"; then
            log_error "Le chargement du descripteur de module $path/module.json a échoué"
            exit 1
        fi

        source "$entrypoint"

        MODULES["$priority"]="$name"

        log_debug "\r\t✅ Chargement réussi du module $module \n"

    done

}

module_run() {
    local action="$1"

    # Nous récupérons la configuration de l'action dans le resources/action.json
    local action_config_file="$BB_RSC_DIR/action.json"
    local order
    local sort_args=(-n)

    order=$(jq -r ".\"$action\".order // \"asc\"" "$action_config_file")
    is_reboot_wanted=$(jq -r ".\"$action\".reboot" "$action_config_file")

    if [[ "$order" == "desc" ]]; then
        sort_args+=(-r)
    fi

    # Pour chaque module enregistré et trié, nous exécutons l'action
    for module_priority in $(printf "%s\n" "${!MODULES[@]}" | sort "${sort_args[@]}"); do

        module="${MODULES[$module_priority]}"
        func="${module}_${action}"

        # Si le module ne dispose pas de l'action nous écrivons un message de skip
        if ! declare -f "$func" >/dev/null; then
            log_warn "\t❔ [$module] $action\n"
            continue
        fi

        log_success "\t⏳ [$module] $action"
        "$func"
        local status=$?
        
        if (( status ==  0 )); then
            log_success "\r\t✅ [$module] $action\n"
        else
            log_error "\r\t❌ [$module] $action\n"
            exit "$status"
        fi

    done

    if [[ "$is_reboot_wanted" == "true" ]]; then
        log_warn "\r\t⚠️  Ne pas oublier de redémarrer le conteneur WSL2 (Windows) ou l'OS (Ubuntu Desktop) pour la prise en compte des modifications des utilisateurs, groupes et permissions. ⚠️\n"
    fi
    
}