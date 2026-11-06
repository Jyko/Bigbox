# shellcheck shell=bash
# shellcheck disable=SC2034 # Les variables TEST_* et BB_TEST_* sont lues par tests/run.sh et les fonctions du cas
# Résolution des dépendances avec -m : aucune action de module n'est exécutée, seul
# module_load est appelé. Ne modifie pas la sandbox, donc pas de reset.
TEST_DESCRIPTION="Résolution des dépendances entre modules (-m)"
TEST_RESET=false

# $1 action, $2 liste -m, $3 modules attendus (triés)
_assert_resolution() {
    assert "$1 -m $2 → $3" "
        set -euo pipefail
        cd '$HOME/Bigbox'
        SCRIPT_DIR=\$PWD ACTION='$1'
        IFS=',' read -ra MODULE_WHITELIST <<< '$2'
        source core/libs.sh
        module_load >/dev/null 2>&1
        [[ \"\$(printf '%s\n' \"\${MODULES[@]}\" | sort | paste -sd ' ')\" == '$3' ]]"
}

test_run() {
    section "Dépendances ajoutées (install, start, upgrade)"
    _assert_resolution install   pg          "core k8s pg system"
    _assert_resolution install   hoppscotch  "core hoppscotch k8s pg system"
    _assert_resolution install   catppucin   "catppucin core qol system"
    _assert_resolution install   nui         "core k8s nats nui system"
    _assert_resolution install   docker      "core docker system"
    _assert_resolution start     hoppscotch  "hoppscotch k8s pg"
    _assert_resolution upgrade   nui         "nats nui"

    section "Modules dépendants ajoutés (uninstall, stop)"
    _assert_resolution uninstall pg          "hoppscotch pg"
    _assert_resolution uninstall nats        "nats nui"
    _assert_resolution uninstall k8s         "hoppscotch k8s nats nui pg sftp wiremock"
    _assert_resolution uninstall qol         "catppucin qol"
    _assert_resolution stop      k8s         "hoppscotch k8s nats nui pg sftp wiremock"

    section "Erreurs"
    assert "module inconnu refusé" "
        cd '$HOME/Bigbox'
        out=\$(SCRIPT_DIR=\$PWD ACTION=install bash -c 'set -euo pipefail; MODULE_WHITELIST=(inconnu); source core/libs.sh; module_load' 2>&1) && exit 1
        [[ \$out == *'Module inconnu : inconnu'* ]]"
}
