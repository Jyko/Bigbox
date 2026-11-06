# shellcheck shell=bash
# shellcheck disable=SC2034 # Les variables TEST_* et BB_TEST_* sont lues par tests/run.sh et les fonctions du cas
# Install complète (tous les modules), puis uninstall complète.
# Les paquets du module core (golang, gcc, make, shellcheck, yq ...) sont conservés par conception.
TEST_DESCRIPTION="install complète, puis uninstall complète"
TEST_INSTALL_ARGS="install"
TEST_UNINSTALL_ARGS="uninstall"
# Install complète : Docker, k3s et 6 releases Helm (chacune attendue jusqu'à 30 s), elle ne
# tient pas en 120 s (117 s mesurées jusqu'à sftp sur 4 vCPU). 300 s laissent une marge sans masquer un blocage.
TEST_ACTION_TIMEOUT=300

BB_TEST_FULL_PACKAGES=(
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    kubectl helm kubecolor postgresql-client-17
    bat eza fd-find ripgrep zoxide vivid
)
BB_TEST_FULL_FILES=(
    /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
    /usr/local/bin/k3s /etc/rancher /var/lib/rancher
    /etc/apt/sources.list.d/kubernetes.list /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    /etc/apt/sources.list.d/helm-stable-debian.list /usr/share/keyrings/helm.gpg
    /etc/apt/sources.list.d/pgdg.list /etc/apt/keyrings/postgresql.asc
    "$HOME/go/bin/nats" "$HOME/.config/nats/context/bigbox.json"
)
# Ports NodePort : pg, nats, nui, sftp, wiremock, hoppscotch
BB_TEST_FULL_PORTS=(30001 30010 30012 30020 30030 30040)

test_after_install() {
    section "Install"
    assert_pkg_installed "${BB_TEST_FULL_PACKAGES[@]}"
    assert_exists "${BB_TEST_FULL_FILES[@]}"
    # nats est dans ~/go/bin, hors du PATH du shell d'assertion (vérifié par son chemin ci-dessus)
    assert_command docker kubectl helm k3s lazygit starship
    assert "docker actif" "systemctl is-active --quiet docker"
    assert "k3s actif" "systemctl is-active --quiet k3s"
    assert "utilisateur dans le groupe docker" "id -nG '$USER' | grep -qw docker"
    assert "6 releases Helm déployées" "[[ \$(helm --kube-context bigbox -n bigbox list -q | wc -l) -eq 6 ]]"
    assert_port_open "${BB_TEST_FULL_PORTS[@]}"
    assert "source de la Bigbox dans ~/.bashrc" "grep -q 'bigbox.sh' '$HOME/.bashrc'"
}

test_after_uninstall() {
    section "Uninstall"
    # lazygit et starship : binaire GitHub ou paquet apt selon la release
    assert_pkg_absent "${BB_TEST_FULL_PACKAGES[@]}" starship lazygit
    assert_absent "${BB_TEST_FULL_FILES[@]}" /usr/local/bin/starship /usr/local/bin/lazygit /var/lib/docker \
        "$HOME/.kube/config" "$HOME/.config/starship.toml" "$HOME/.config/bigbox" "$HOME/.ssh/bigbox"
    assert_no_process dockerd k3s-server containerd
    assert "groupe docker supprimé" "! getent group docker"
    assert "source de la Bigbox retirée de ~/.bashrc" "! grep -q 'bigbox.sh' '$HOME/.bashrc'"
    assert_port_closed "${BB_TEST_FULL_PORTS[@]}"
    assert_desktop_preserved
    section "Orphelins"
    assert_no_orphans
}
