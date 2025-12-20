# METADATA du module
MODULE_NAME="pg"
MODULE_PRIORITY=300
BB_PG_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_PG_MODULE_HELM_DIR="$BB_PG_MODULE_BASE_DIR/helm"
BB_PG_VERSION=17

pg_install() {

    apt_wrapper install -y "postgresql-client-$BB_PG_VERSION"

    helm_wrapper upgrade --install pg "$BB_PG_MODULE_HELM_DIR" -f "$BB_PG_MODULE_HELM_DIR/values.yaml" --namespace "$BB_K8S_NAMESPACE"

}

# TODO : A réfléchir, notamment avec le contrôle de la Chart
# pg_uninstall() { return 0 }

# TODO : A réfléchir, notamment avec le contrôle de la Chart
# pg_upgrade() { return 0 }