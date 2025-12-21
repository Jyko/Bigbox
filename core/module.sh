# Liste des modules chargés ordonnée par priorité d'exécution
declare -A MODULES

load_modules() {

    # Charger tous les modules
    for module in "$BB_MOD_DIR"/*/*.sh; do

        echo -ne "\r\t⏳ Chargement du module $module"

        source "$module"

        if [[ -z "$MODULE_NAME" || -z "$MODULE_PRIORITY" ]]; then
            echo -e "\r\t❌ Chargement échoué du module $module"
            exit 1
        fi

        MODULES["$MODULE_PRIORITY"]="$MODULE_NAME"

        echo -e "\r\t✅ Chargement réussi du module $module"

        sleep 0.1

        unset MODULE_NAME MODULE_PRIORITY

    done

}

run_modules() {
    local action="$1"

    # FIXME: peut-être à dégager dans le log.sh
    # Connaitre la longueur max du nom des modules pour tailler les messages proprement
    local max_module_name_length=0
    for m in "${MODULES[@]}"; do
        (( ${#m} > max_module_name_length )) && max_module_name_length=${#m}
    done

    # Pour chaque module enregistré, nous exécutons par ordre croissant de priorité l'action
    for module_priority in $(printf "%s\n" "${!MODULES[@]}" | sort -n); do

        module="${MODULES[$module_priority]}"
        func="${module}_${action}"

        # Si le module ne dispose pas de l'action nous écrivons un message de skip
        if ! declare -f "$func" >/dev/null; then
            log_action_not_implemented "$module" "$action" "$max_module_name_length"
            continue
        fi

        local status

        log_action_start "$module" "$action" "$max_module_name_length"

        # Gestion des erreurs et du stdout/stderr en fonction du flag DEBUG
        if [[ "$DEBUG" == "true" ]]; then
            # Obtenir les stdout/stderr du sous-shell directement (donc sans filtrage)
            "$func"
            status=$?
            log_action_end "$module" "$action" "$max_module_name_length" "$status"
        else
            # Capturer les stdout/stderr dans des process substitutions afin de les filtrer
            local ps_out ps_err
            ps_out=$(mktemp)
            ps_err=$(mktemp)

            "$func" >"$ps_out" 2>"$ps_err"

            status=$?
            local out err
            out=$(<"$ps_out")
            err=$(<"$ps_err")
            log_action_end "$module" "$action" "$max_module_name_length" "$status" "$out" "$err"

            # Nettoyage des fichiers temporaires
            rm -rf "$ps_out" "$ps_err"
        fi

        # Gestion des erreurs remontées par l'exécution
        if (( status != 0 )); then
            exit "$status"
        fi

    done
    
}