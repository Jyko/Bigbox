#!/usr/bin/env bash
# shellcheck shell=bash

BB_NATS_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_NATS_MODULE_HELM_DIR="$BB_NATS_MODULE_BASE_DIR/helm"
BB_NATS_HELM_CHART_NAME=bigbox-nats
BB_NATS_HELM_RELEASE_NAME=bigbox-nats
BB_NATS_DOTFILES_DIR="$BB_NATS_MODULE_BASE_DIR/dotfiles"
BB_NATS_CLI_VERSION="v0.5.1"
BB_NATS_CLI_BINARY="$HOME/go/bin/nats"
BB_NATS_CONTEXT_NAME="bigbox"
BB_NATS_CONTEXT_DIR="$HOME/.config/nats/context"

nats_install() {

    # Déployer l'instance NATS
    run_cmd kutils_release_upgrade "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_MODULE_HELM_DIR"

    # Installer la NATS-CLI, sauf si l'utilisateur l'a déjà
    if ! command -v nats >/dev/null 2>&1; then
        run_cmd go install "github.com/nats-io/natscli/nats@$BB_NATS_CLI_VERSION"
        state_mark_owned "file:$BB_NATS_CLI_BINARY"
    fi

    # Préparer un NATS-CLI contexte pour une connexion depuis le Host (crée ou met à jour le contexte)
    # TODO : Avec l'utilisation de varenv, on généra le Values.yaml pour que ce soit solide.
    run_cmd nats context add "$BB_NATS_CONTEXT_NAME" --server nats://localhost:30010

    cfg_copy_dotfile "$BB_NATS_DOTFILES_DIR/nats_completion.sh"
}

nats_uninstall() { 

    # Supprimer uniquement le contexte bigbox : les autres contextes appartiennent à l'utilisateur.
    # (nats context rm refuse de supprimer le dernier contexte, d'où la suppression du fichier.)
    rm -f "$BB_NATS_CONTEXT_DIR/$BB_NATS_CONTEXT_NAME.json"
    if [[ "$(cat "$BB_NATS_CONTEXT_DIR/../context.txt" 2>/dev/null)" == "$BB_NATS_CONTEXT_NAME" ]]; then
        rm -f "$BB_NATS_CONTEXT_DIR/../context.txt"
    fi
    rmdir --ignore-fail-on-non-empty "$BB_NATS_CONTEXT_DIR" "$(dirname "$BB_NATS_CONTEXT_DIR")" 2>/dev/null || true

    # Supprimer le binaire de NATS-CLI, s'il a été installé par la Bigbox
    if state_is_owned "file:$BB_NATS_CLI_BINARY"; then
        rm -f "$BB_NATS_CLI_BINARY"
        state_unmark "file:$BB_NATS_CLI_BINARY"
    fi

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