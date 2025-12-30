# METADATA du module
MODULE_NAME="pg"
MODULE_PRIORITY=300

BB_PG_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_PG_MODULE_HELM_DIR="$BB_PG_MODULE_BASE_DIR/helm"
BB_PG_HELM_CHART_NAME=bigbox-pg
BB_PG_HELM_RELEASE_NAME=bigbox-pg
BB_PG_VERSION=17

pg_install() {
    apt_wrapper install "postgresql-client-$BB_PG_VERSION"
    kutils_release_upgrade "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_MODULE_HELM_DIR"
}

pg_uninstall() {
    apt_wrapper purge "postgresql-client-$BB_PG_VERSION"
    kutils_release_uninstall "$BB_PG_HELM_RELEASE_NAME" "$BB_PG_HELM_CHART_NAME"
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

