# shellcheck shell=bash
# shellcheck disable=SC2034 # Les variables TEST_* et BB_TEST_* sont lues par tests/run.sh et les fonctions du cas
# Outillage du shell : install d'un module de haut niveau (dépendances ajoutées),
# puis uninstall d'un module dont un autre dépend (dépendant ajouté).
TEST_DESCRIPTION="install -m catppucin, puis uninstall -m qol"
TEST_INSTALL_ARGS="install -m catppucin"
TEST_UNINSTALL_ARGS="uninstall -m qol"

BB_TEST_QOL_PACKAGES=(bat eza fd-find ripgrep zoxide vivid)
BB_TEST_QOL_DOTFILES=(qol_env.sh qol_alias.sh catppucin_env.sh)

test_after_install() {
    section "Install"
    assert_pkg_installed "${BB_TEST_QOL_PACKAGES[@]}"
    assert_command lazygit batcat eza zoxide vivid
    assert_exists "${BB_TEST_QOL_DOTFILES[@]/#/$HOME/.config/bigbox/dotfiles/}"
    assert "thème catppuccin ajouté à la config bat existante" "grep -q -- '--theme' '$HOME/.config/bat/config'"
    assert "source de la Bigbox dans ~/.bashrc" "grep -q 'bigbox.sh' '$HOME/.bashrc'"
}

test_after_uninstall() {
    section "Uninstall"
    # lazygit : binaire GitHub avant 25.10, paquet apt ensuite
    assert_pkg_absent "${BB_TEST_QOL_PACKAGES[@]}" lazygit
    assert_absent /usr/local/bin/lazygit "${BB_TEST_QOL_DOTFILES[@]/#/$HOME/.config/bigbox/dotfiles/}"
    assert "thème catppuccin retiré de la config bat" "! grep -q -- '--theme' '$HOME/.config/bat/config'"
    # core n'est pas désinstallé par -m qol
    assert "source de la Bigbox conservée dans ~/.bashrc" "grep -q 'bigbox.sh' '$HOME/.bashrc'"
    assert_desktop_preserved
    section "Orphelins"
    assert_no_orphans
}
