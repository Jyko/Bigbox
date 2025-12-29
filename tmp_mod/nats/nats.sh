# METADATA du module
MODULE_NAME="nats"
MODULE_PRIORITY=310

BB_NATS_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_NATS_MODULE_HELM_DIR="$BB_NATS_MODULE_BASE_DIR/helm"
BB_NATS_HELM_CHART_NAME=bigbox-nats
BB_NATS_HELM_RELEASE_NAME=bigbox-nats
# Il sera exporté dans le PATH et source pour les sessions suivantes, mais ici on veut du robuste.
BB_NATS_BIN_DIR=$HOME/go/bin

nats_install() {

    # Déployer l'instance NATS
    kutils_release_upgrade "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_MODULE_HELM_DIR"

    # Installer la NATS-CLI
    go install github.com/nats-io/natscli/nats@latest

    # Préparer un NATS-CLI contexte pour une connexion depuis le Host
    # TODO : Avec l'utilisation de varenv, on généra le Values.yaml pour que ce soit solide.
    $BB_NATS_BIN_DIR/nats context add bigbox --server nats://localhost:30010

}

nats_uninstall() { 
    kutils_release_uninstall "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_HELM_CHART_NAME"
}

nats_upgrade() {
    kutils_release_upgrade "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_MODULE_HELM_DIR"
}

nats_start() {
    kutils_release_upgrade "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_MODULE_HELM_DIR"
}

nats_stop() {
    kutils_release_stop "$BB_NATS_HELM_RELEASE_NAME" "$BB_NATS_HELM_CHART_NAME" "$BB_NATS_MODULE_HELM_DIR"
}