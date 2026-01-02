#!/usr/bin/env bash
# shellcheck shell=bash

BB_NUI_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_NUI_MODULE_HELM_DIR="$BB_NUI_MODULE_BASE_DIR/helm"
BB_NUI_HELM_CHART_NAME=bigbox-nui
BB_NUI_HELM_RELEASE_NAME=bigbox-nui

nui_install() {
    run_cmd kutils_release_upgrade "$BB_NUI_HELM_RELEASE_NAME" "$BB_NUI_MODULE_HELM_DIR"
}

nui_uninstall() {
    if run_cmd_silently kutils_is_api_available; then
        run_cmd kutils_release_uninstall "$BB_NUI_HELM_RELEASE_NAME" "$BB_NUI_HELM_CHART_NAME"
    fi
}

nui_upgrade() {
    run_cmd kutils_release_upgrade "$BB_NUI_HELM_RELEASE_NAME" "$BB_NUI_MODULE_HELM_DIR"
}

nui_start() {
    run_cmd kutils_release_upgrade "$BB_NUI_HELM_RELEASE_NAME" "$BB_NUI_MODULE_HELM_DIR"
}

nui_stop() {
    run_cmd kutils_release_stop "$BB_NUI_HELM_RELEASE_NAME" "$BB_NUI_HELM_CHART_NAME"  "$BB_NUI_MODULE_HELM_DIR"
}