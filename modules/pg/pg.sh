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

    kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_uninstall() {

    apt_wrapper purge "postgresql-client-$BB_PG_VERSION" || true

    if kutils_is_api_available -s; then
        kutils_release_uninstall "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_HELM_CHART_NAME"
    fi
}

pg_upgrade() {
    kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_start() {
    kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_stop() {
    kutils_release_stop "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_HELM_CHART_NAME" "$BB_PG_MODULE_HELM_DIR"
}

_pg_client_verify() {
    command -v psql >/dev/null 2>&1
}