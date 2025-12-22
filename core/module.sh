# Liste des modules chargés ordonnée par priorité d'exécution
declare -A MODULES

load_modules() {

    # Charger tous les modules
    for module in "$BB_MOD_DIR"/*/*.sh; do

        log_debug "\r\t⏳ Chargement du module $module"

        source "$module"

        if [[ -z "$MODULE_NAME" || -z "$MODULE_PRIORITY" ]]; then
            log_error "\r\t❌ Chargement échoué du module $module"
            exit 1
        fi

        MODULES["$MODULE_PRIORITY"]="$MODULE_NAME"

        log_debug "\r\t✅ Chargement réussi du module $module"

        unset MODULE_NAME MODULE_PRIORITY

    done

}

run_modules() {
    local action="$1"

    # Pour chaque module enregistré, nous exécutons par ordre croissant de priorité l'action
    for module_priority in $(printf "%s\n" "${!MODULES[@]}" | sort -n); do

        module="${MODULES[$module_priority]}"
        func="${module}_${action}"

        # Si le module ne dispose pas de l'action nous écrivons un message de skip
        if ! declare -f "$func" >/dev/null; then
            log_warn "\r\t❔ [$module] $action "
            continue
        fi

        log_success "\r\t⏳ [$module] $action"
        "$func"
        local status=$?
        
        if (( status ==  0 )); then
            log_success "\r\t✅ [$module] $action"
        else
            log_error "\r\t❌ [$module] $action"
            exit "$status"
        fi

    done
    
}