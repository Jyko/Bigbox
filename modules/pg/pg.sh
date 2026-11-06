#!/usr/bin/env bash
# shellcheck shell=bash

BB_PG_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_PG_MODULE_HELM_DIR="$BB_PG_MODULE_BASE_DIR/helm"
BB_PG_HELM_CHART_NAME=bigbox-pg
BB_PG_HELM_RELEASE_NAME=bigbox-pg
BB_PG_VERSION=17
# Dépôt officiel PostgreSQL (PGDG) : les dépôts Ubuntu ne fournissent qu'une seule version majeure du client
BB_PG_APT_KEY_FILE="/etc/apt/keyrings/postgresql.asc"
BB_PG_APT_SOURCE_FILE="/etc/apt/sources.list.d/pgdg.list"

pg_install() {

    if ! _pg_client_verify; then
        _pg_apt_repository_install
        apt_wrapper install "postgresql-client-$BB_PG_VERSION"
    fi

    run_cmd kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_uninstall() {

    apt_purge_installed "postgresql-client-$BB_PG_VERSION" || true
    _pg_apt_repository_uninstall

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

_pg_apt_repository_install() {
    local codename
    codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

    sudo install -m 0755 -d "$(dirname "$BB_PG_APT_KEY_FILE")"
    run_cmd sudo curl "${BB_CURL_OPTS[@]}" https://www.postgresql.org/media/keys/ACCC4CF8.asc -o "$BB_PG_APT_KEY_FILE"
    sudo chmod 644 "$BB_PG_APT_KEY_FILE"

    echo "deb [signed-by=$BB_PG_APT_KEY_FILE] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" \
        | fs_file_replace "$BB_PG_APT_SOURCE_FILE"

    apt_wrapper update
}

_pg_apt_repository_uninstall() {
    sudo rm -f "$BB_PG_APT_SOURCE_FILE" "$BB_PG_APT_KEY_FILE"
}

_pg_client_verify() {
    # Le test de la commande renvoie un faux positif car le postgresql-commons (le wrapper) est appelé et est toujours présent passé la première installation.
    # Nous testons donc directement l'appel à la version du client wrappé par le commons.
    if psql --version >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}