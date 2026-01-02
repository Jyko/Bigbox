#!/usr/bin/env bash
# shellcheck shell=bash

BB_ACTION_CONFIG_FILE="$BB_RSC_DIR/action.json"
BB_ACTION_CONFIG=$(<"$BB_ACTION_CONFIG_FILE")
readonly BB_ACTION_CONFIG_FILE BB_ACTION_CONFIG

action_is_valid() {
    local action="$1"

    if jq -e --arg action "$action" '.[$action] != null' <<< "$BB_ACTION_CONFIG" >/dev/null; then
        log_debug "L'action $action est valide\n"
        return 0
    else
        log_debug "tL'action $action n'est pas une action valide configurée\n"
        return 1
    fi
}

action_execute() {

    # Charger les modules disposant de l'action
    module_load

    # Exécuter l'action sur tous les modules chargés par ordre de priorité déclaré
    module_run

}

# Retourne dans stdout la valeur de la propriété fournie pour l'action
action_get_property() {
    local property="$1"
    local default_value="${2:-}"

    if [[ -z "$ACTION" ]]; then
        log_error "L'action à executer est obligatoire\n"
        exit 2
    fi

    if [[ -z "$property" ]]; then
        log_error "La propriété à chercher est obligatoire\n"
        exit 2
    fi

    jq -r \
    --arg a "$ACTION" \
    --arg p "$property" \
    --arg d "$default_value" \
    '.[$a][$p] // $d' <<< "$BB_ACTION_CONFIG"
}