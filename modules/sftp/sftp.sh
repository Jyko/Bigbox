#!/usr/bin/env bash
# shellcheck shell=bash

BB_SFTP_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_SFTP_MODULE_HELM_DIR="$BB_SFTP_MODULE_BASE_DIR/helm"
BB_SFTP_HELM_CHART_NAME=bigbox-sftp
BB_SFTP_HELM_RELEASE_NAME=bigbox-sftp
BB_SFTP_SSH_KEY_NAME=bigbox-sftp

sftp_install() {
    # Vérifier et regénérer une clé SSH pour se connecter sur le SFTP
    run_cmd ssh_generate_key "$BB_SFTP_SSH_KEY_NAME"
    run_cmd kutils_release_upgrade "$BB_SFTP_HELM_RELEASE_NAME" "$BB_SFTP_MODULE_HELM_DIR" \
        --set sftp.clientPublicKey="$(base64 -w0 "$(ssh_get_key_path "$BB_SFTP_SSH_KEY_NAME.pub")")"
}

sftp_uninstall() { 
    if run_cmd_silently kutils_is_api_available; then
        run_cmd kutils_release_uninstall "$BB_SFTP_HELM_RELEASE_NAME" "$BB_SFTP_HELM_CHART_NAME"
    fi
    run_cmd ssh_delete_key "$BB_SFTP_SSH_KEY_NAME"
}

sftp_upgrade() {
    # Vérifier et regénérer une clé SSH pour se connecter sur le SFTP
    run_cmd ssh_generate_key "$BB_SFTP_SSH_KEY_NAME"
    run_cmd kutils_release_upgrade "$BB_SFTP_HELM_RELEASE_NAME" "$BB_SFTP_MODULE_HELM_DIR" \
        --set sftp.clientPublicKey="$(base64 -w0 "$(ssh_get_key_path "$BB_SFTP_SSH_KEY_NAME.pub")")"
}

sftp_start() {
    # Vérifier et regénérer une clé SSH pour se connecter sur le SFTP
    run_cmd ssh_generate_key "$BB_SFTP_SSH_KEY_NAME"
    run_cmd kutils_release_upgrade "$BB_SFTP_HELM_RELEASE_NAME" "$BB_SFTP_MODULE_HELM_DIR" \
        --set sftp.clientPublicKey="$(base64 -w0 "$(ssh_get_key_path "$BB_SFTP_SSH_KEY_NAME.pub")")"
}

sftp_stop() {
    run_cmd kutils_release_stop "$BB_SFTP_HELM_RELEASE_NAME" "$BB_SFTP_HELM_CHART_NAME" "$BB_SFTP_MODULE_HELM_DIR"
}