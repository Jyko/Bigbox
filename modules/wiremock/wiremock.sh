#!/usr/bin/env bash
# shellcheck shell=bash

BB_WIREMOCK_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_WIREMOCK_MODULE_HELM_DIR="$BB_WIREMOCK_MODULE_BASE_DIR/helm"
BB_WIREMOCK_HELM_CHART_NAME=bigbox-wiremock
BB_WIREMOCK_HELM_RELEASE_NAME=bigbox-wiremock

wiremock_install() {
    run_cmd kutils_release_upgrade "$BB_WIREMOCK_HELM_RELEASE_NAME" "$BB_WIREMOCK_MODULE_HELM_DIR"
}

wiremock_uninstall() {
    if run_cmd_silently kutils_is_api_available; then
        run_cmd kutils_release_uninstall "$BB_WIREMOCK_HELM_RELEASE_NAME" "$BB_WIREMOCK_HELM_CHART_NAME"
    fi
}

wiremock_upgrade() {
    run_cmd kutils_release_upgrade "$BB_WIREMOCK_HELM_RELEASE_NAME" "$BB_WIREMOCK_MODULE_HELM_DIR"
}

wiremock_start() {
    run_cmd kutils_release_upgrade "$BB_WIREMOCK_HELM_RELEASE_NAME" "$BB_WIREMOCK_MODULE_HELM_DIR"
}

wiremock_stop() {
    run_cmd kutils_release_stop "$BB_WIREMOCK_HELM_RELEASE_NAME" "$BB_WIREMOCK_HELM_CHART_NAME" "$BB_WIREMOCK_MODULE_HELM_DIR"
}