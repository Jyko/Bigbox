#!/usr/bin/env bash

show_version() {
    echo "Bigbox Installer Version: 1.0.0"
}

show_help() {
cat <<EOF
Usage: install.sh [options]

Options:
-d, --debug       Activer le mode debug
-h, --help        Afficher ce message d'aide
-v, --version     Afficher la version
EOF

}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            -d|--debug)
                DEBUG=true
                shift
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Argument non supporté : $1"
                exit 1
                ;;
        esac
    done
}

# Exécuter une tâche avec des logs et une gestion d'erreur
# $1 : message de lancement de la tâche
# $2... : commande à exécuter
task() {
    local msg="$1"
    shift

    log_task_start "$msg"

    # Capture de stdout et stderr dans des process substitutions
    # puis écriture dans des fichiers temporaires
    local ps_out ps_err
    ps_out=$(mktemp)
    ps_err=$(mktemp)

    # Exécution de la commande
    "$@" >"$ps_out" 2>"$ps_err"

    log_task_end "$msg" "$?" "$ps_out" "$ps_err"

    # Nettoyage des fichiers temporaires
    rm -rf "$ps_out" "$ps_err"

    # Pour éviter d'écraser les messages de log et mettre une tempo entre les commandes
    sleep 1
}

# Affichage d'un message de début d'action
# $1 : message
log_task_start() {
    local msg="$1"
    echo -ne "\r\t⏳ $msg"
}

# Affichage d'un message de fin d'action dépendant de son statut
# $1 : message
# $2 : status de la commande lancée (0=success, autre=erreur, optionnel, défaut 0)
# $3 : stdout de la commande lancée (optionnel)
# $4 : stderr de la commande lancée (optionnel)
log_task_end() {
    local msg="$1"
    local status="${2:-0}"
    local std_out="${3:-}"
    local std_err="${4:-}"

    if (( "$status" == 0 )); then
        echo -e "\r\t✅ $msg\n"
    else
        echo -e "\r\t❌ $msg\n"
    fi

    # Affichage du SDTOUT et STDERR en fonction du mode verbeux
    if [[ "$DEBUG" == "true" ]]; then
        [[ -n "$std_out" && -s "$std_out" ]] && cat "$std_out"
        [[ -n "$std_err" && -s "$std_err" ]] && cat "$std_err" >&2
    fi
}