#!/usr/bin/env bash
# shellcheck shell=bash

BB_ALLOWED_ACTIONS=(
  install
  start
  stop
  uninstall
  upgrade
)

action_is_valid() {
    local action="$1"

    for a in "${BB_ALLOWED_ACTIONS[@]}"; do
        [[ "$a" == "$action" ]] && return 0
    done

    return 1
}

action_execute() {
    local action="$1"

    # Charger les modules disposant de l'action
    module_load

    # Exécuter l'action sur tous les modules chargés par ordre de priorité déclaré
    module_run "$action"

}