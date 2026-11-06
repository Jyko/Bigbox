# shellcheck shell=bash
# shellcheck disable=SC2034 # Les variables TEST_* et BB_TEST_* sont lues par tests/run.sh et les fonctions du cas
# Service IaC : install -m pg doit déclencher l'install de k3s (module k8s),
# puis uninstall -m k8s retire k3s et tous les services qui en dépendent.
TEST_DESCRIPTION="install -m pg (k3s inclus), puis uninstall -m k8s"
TEST_INSTALL_ARGS="install -m pg"
TEST_UNINSTALL_ARGS="uninstall -m k8s"

BB_TEST_PG_PACKAGES=(kubectl helm kubecolor postgresql-client-17)
BB_TEST_PG_FILES=(
    /usr/local/bin/k3s /etc/rancher /var/lib/rancher
    /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    /etc/apt/sources.list.d/helm-stable-debian.list /usr/share/keyrings/helm.gpg
    /etc/apt/sources.list.d/pgdg.list /etc/apt/keyrings/postgresql.asc
)

test_after_install() {
    section "Install"
    assert_pkg_installed "${BB_TEST_PG_PACKAGES[@]}"
    assert_exists "${BB_TEST_PG_FILES[@]}"
    assert "k3s actif" "systemctl is-active --quiet k3s"
    assert "contexte kubectl bigbox" "kubectl config get-contexts bigbox"
    assert "kubeconfig en 600" "[[ \$(stat -L -c %a '$HOME/.kube/config') == 600 ]]"
    assert "PostgreSQL répond sur le NodePort 30001" "pg_isready -h localhost -p 30001 -t 5"
}

test_after_uninstall() {
    section "Uninstall"
    assert_pkg_absent "${BB_TEST_PG_PACKAGES[@]}"
    assert_absent "${BB_TEST_PG_FILES[@]}" "$HOME/.kube/config"
    assert_no_process k3s-server containerd
    assert "aucun service k3s" "! systemctl list-unit-files k3s.service | grep -q k3s"
    assert_port_closed 30001
    assert_desktop_preserved
    section "Orphelins"
    assert_no_orphans
}
