#!/usr/bin/env bash
# shellcheck shell=bash

BB_PG_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_PG_MODULE_HELM_DIR="$BB_PG_MODULE_BASE_DIR/helm"
BB_PG_HELM_CHART_NAME=bigbox-pg
BB_PG_HELM_RELEASE_NAME=bigbox-pg
BB_PG_VERSION=17

pg_install() {

    if ! _pg_client_verify; then
        apt_wrapper install "postgresql-client-$BB_PG_VERSION"
    fi

    run_cmd kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_uninstall() {

    apt_wrapper purge "postgresql-client-$BB_PG_VERSION" || true

    if run_cmd_silently kutils_is_api_available; then
        run_cmd kutils_release_uninstall "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_HELM_CHART_NAME"
    fi
}

pg_upgrade() {
    run_cmd kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_start() {
    run_cmd kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_stop() {
    run_cmd kutils_release_stop "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_HELM_CHART_NAME" "$BB_PG_MODULE_HELM_DIR"
}

_pg_client_verify() {
    command -v psql >/dev/null 2>&1
}