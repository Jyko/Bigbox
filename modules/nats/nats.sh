# METADATA du module
MODULE_NAME="nats"
MODULE_PRIORITY=310

BB_NATS_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_NATS_MODULE_HELM_DIR="$BB_NATS_MODULE_BASE_DIR/helm"
BB_NATS_HELM_CHART_NAME=bigbox-nats
BB_NATS_HELM_RELEASE_NAME=bigbox-nats

nats_install() {
    kutils_release_upgrade "$BB_NATS_MODULE_HELM_DIR" "$BB_NATS_HELM_RELEASE_NAME"
}

nats_uninstall() { 
    kutils_release_uninstall "$BB_NATS_HELM_CHART_NAME" "$BB_NATS_HELM_RELEASE_NAME"
}

nats_upgrade() {
    kutils_release_upgrade "$BB_NATS_MODULE_HELM_DIR" "$BB_NATS_HELM_RELEASE_NAME"
}

nats_start() {
    kutils_release_upgrade "$BB_NATS_MODULE_HELM_DIR" "$BB_NATS_HELM_RELEASE_NAME"
}

nats_stop() {
    kutils_release_stop "$BB_NATS_MODULE_HELM_DIR" "$BB_NATS_HELM_CHART_NAME" "$BB_NATS_HELM_RELEASE_NAME"
}