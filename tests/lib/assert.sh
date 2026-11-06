# shellcheck shell=bash
# shellcheck disable=SC2016 # Les commandes des assertions sont évaluées par bash -c, dans la VM
#################################################################################
# Assertions des tests, exécutées DANS la sandbox (jamais sur l'hôte).
#
# Chaque assertion est bornée à BB_TEST_ASSERT_TIMEOUT secondes : aucune attente sans fin.
# Les commandes passent par `bash -c` car `timeout` n'exécute que des binaires,
# d'où l'export des fonctions utilitaires.
#################################################################################

BB_TEST_ASSERT_TIMEOUT="${BB_TEST_ASSERT_TIMEOUT:-10}"
_bb_ok=0
_bb_ko=0

_pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'; }
_port_open() { timeout 2 bash -c "</dev/tcp/127.0.0.1/$1" 2>/dev/null; }
export -f _pkg_installed _port_open

section() { printf '== %s\n' "$*"; }

# $1 : libellé, $2 : commande (chaîne) qui doit réussir
# En cas d'échec, le contexte est affiché sur des lignes « ↳ » (lues par le rapport de test)
assert() {
    local output status=0
    output=$(timeout --kill-after=2 "$BB_TEST_ASSERT_TIMEOUT" bash -c "$2" 2>&1) || status=$?
    if (( status == 0 )); then
        printf '✅ %s\n' "$1"
        _bb_ok=$((_bb_ok + 1))
    else
        printf '❌ %s\n' "$1"
        (( status == 124 )) && printf '   ↳ timeout de %s s atteint\n' "$BB_TEST_ASSERT_TIMEOUT"
        printf '   ↳ code : %s\n' "$status"
        printf '   ↳ commande : %s\n' "$(tr -s ' \n' ' ' <<< "$2")"
        [[ -n "$output" ]] && head -n 10 <<< "$output" | sed 's/^/   ↳ sortie : /'
        _bb_ko=$((_bb_ko + 1))
    fi
}

assert_pkg_installed() { local p; for p in "$@"; do assert "paquet $p installé" "_pkg_installed '$p'"; done; }
assert_pkg_absent()    { local p; for p in "$@"; do assert "paquet $p absent" "! _pkg_installed '$p'"; done; }
assert_exists()        { local f; for f in "$@"; do assert "$f présent" "test -e '$f'"; done; }
assert_absent()        { local f; for f in "$@"; do assert "$f absent" "test ! -e '$f'"; done; }
assert_command()       { local c; for c in "$@"; do assert "commande $c disponible" "command -v '$c'"; done; }
assert_no_process()    { local p; for p in "$@"; do assert "aucun processus $p" "! pgrep -x '$p'"; done; }
assert_port_open()     { local p; for p in "$@"; do assert "port $p ouvert" "_port_open $p"; done; }
assert_port_closed()   { local p; for p in "$@"; do assert "port $p fermé" "! _port_open $p"; done; }

assert_no_orphans() {
    assert "apt autoremove n'a plus rien à retirer" \
        '[[ $(apt-get -s autoremove 2>/dev/null | grep -c "^Remv") -eq 0 ]]'
    assert "aucun paquet résiduel (état rc)" \
        '[[ $(dpkg -l | grep -c "^rc") -eq 0 ]]'
}

# Le poste préparé par prepare_desktop.sh doit être intact après un uninstall
assert_desktop_preserved() {
    section "Préservation du poste existant"
    assert_pkg_installed htop fzf
    assert "contexte NATS de l'utilisateur intact" "test -f '$HOME/.config/nats/context/perso.json'"
    assert "base zoxide de l'utilisateur intacte" "test -f '$HOME/.local/share/zoxide/db.zo'"
    assert "configuration bat de l'utilisateur intacte" "grep -qx -- '--paging=never' '$HOME/.config/bat/config'"
}

# Informations (sans assertion) utiles au diagnostic
report_leftovers() {
    section "Paquets ajoutés depuis la référence (informatif)"
    if [[ -f "$HOME/.bigbox-test/ref-packages.txt" ]]; then
        comm -13 "$HOME/.bigbox-test/ref-packages.txt" \
            <(timeout 10 dpkg-query -W -f '${Package}\n' | sort) | paste -sd ' '
    fi
    section "Registre de la Bigbox (informatif)"
    paste -sd ' ' "$HOME/.config/bigbox/state/owned" 2>/dev/null || echo "(absent)"
}

# Dernière ligne lue par le lanceur, code de sortie non nul en cas d'échec
report() {
    printf 'RESULTAT: %d ok, %d ko\n' "$_bb_ok" "$_bb_ko"
    (( _bb_ko == 0 ))
}
