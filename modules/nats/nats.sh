#!/usr/bin/env bash
# shellcheck shell=bash

BB_NATS_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_NATS_MODULE_HELM_DIR="$BB_NATS_MODULE_BASE_DIR/helm"
BB_NATS_HELM_CHART_NAME=bigbox-nats
BB_NATS_HELM_RELEASE_NAME=bigbox-nats
BB_NATS_DOTFILES_DIR="$BB_NATS_MODULE_BASE_DIR/dotfiles"

nats_install() {

    # Déployer l'instance NATS
    run_cmd kutils_release_upgrade "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_MODULE_HELM_DIR"

    # Installer la NATS-CLI
    run_cmd go install github.com/nats-io/natscli/nats@latest

    # Préparer un NATS-CLI contexte pour une connexion depuis le Host
    # TODO : Avec l'utilisation de varenv, on généra le Values.yaml pour que ce soit solide.
    run_cmd nats context add bigbox --server nats://localhost:30010

    cfg_copy_dotfile "$BB_NATS_DOTFILES_DIR/nats_completion.sh"
}

nats_uninstall() { 

    # Supprimer les contextes de NATS-CLI
    # FIXME : C'est barbare, mais elle ne nous autorise pas à supprimer le dernier. Faut trouver un workaround
    rm -rf "$HOME/.config/nats"
    # Supprimer le binaire de NATS-CLI
    rm -f "$HOME/go/bin/nats"

    if run_cmd_silently kutils_is_api_available; then
        run_cmd kutils_release_uninstall "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_HELM_CHART_NAME"
    fi

    cfg_delete_dotfile "nats_completion.sh"
}

nats_upgrade() {
    run_cmd kutils_release_upgrade "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_MODULE_HELM_DIR"
}

nats_start() {
    run_cmd kutils_release_upgrade "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_MODULE_HELM_DIR"
}

nats_stop() {
    run_cmd kutils_release_stop "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_HELM_CHART_NAME" "$BB_NATS_MODULE_HELM_DIR"
}