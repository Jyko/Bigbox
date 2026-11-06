#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

#################################################################################
# Tests de la Bigbox, rejouables, exécutés dans la sandbox QEMU/KVM (jamais sur l'hôte).
#
# Usage : tests/run.sh [--impl bash|go] [-r 24.04[,26.04 ...]] [-t secondes] [cas ...]
#   --impl  implémentation testée (défaut bash) : bash joue tests/cases/ avec ./bigbox,
#           go joue tests/cases-go/ avec la Bigbox Go (construite sur l'hôte, ~/bin/bigbox)
#   -r  release(s) Ubuntu, séparées par des virgules (défaut 24.04). Une sandbox par release,
#       créée si besoin ; plusieurs releases sont testées EN PARALLÈLE.
#   -t  durée maximale de chaque install et de chaque uninstall, pour tous les cas
#       (défaut : TEST_ACTION_TIMEOUT du cas, sinon 120 s)
#   cas noms de fichiers du répertoire des cas (défaut : tous, deps en premier, full en dernier)
#
# Chaque cas de scénario : reset au snapshot "pristine", poste préparé (prepare_desktop.sh),
# install bornée DANS la VM, assertions, uninstall bornée, assertions.
# Code de sortie non nul si un test échoue.
# Rapports : $BB_SANDBOX_DIR/logs/<date>/<release>/{report.md,junit.xml,<cas>.log}
#            et $BB_SANDBOX_DIR/logs/<date>/report.md (toutes releases)
#################################################################################

BB_TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BB_TEST_REPO_DIR="$(cd -- "$BB_TEST_DIR/.." && pwd)"
BB_TEST_SANDBOX="$BB_TEST_REPO_DIR/tools/sandbox/sandbox.sh"
BB_SANDBOX_DIR="${BB_SANDBOX_DIR:-$HOME/.cache/bigbox-sandbox}"
readonly BB_TEST_DIR BB_TEST_REPO_DIR BB_TEST_SANDBOX

# shellcheck source=SCRIPTDIR/lib/report.sh
source "$BB_TEST_DIR/lib/report.sh"

BB_TEST_DEFAULT_ACTION_TIMEOUT=120
BB_TEST_ACTION_TIMEOUT="$BB_TEST_DEFAULT_ACTION_TIMEOUT"
BB_TEST_TIMEOUT_OVERRIDE=""
BB_TEST_RELEASE="24.04"
BB_TEST_SANDBOX_CMD=()
# Implémentation testée : bash (./bigbox, tests/cases/) ou go (~/bin/bigbox, tests/cases-go/)
BB_TEST_IMPL=bash
BB_TEST_CASES_DIR="$BB_TEST_DIR/cases"
BB_TEST_BIGBOX=./bigbox
# Partagé avec les runners enfants en mode parallèle (calculé dans main selon --impl)
BB_TEST_LOG_BASE="${BB_TEST_LOG_BASE:-}"
BB_TEST_LOG_DIR=""
BB_TEST_LOG_FILE=/dev/null
BB_TEST_RESULTS=/dev/null

# --------------------
# Utilitaires
# --------------------

# Horodate chaque ligne, l'affiche et l'écrit sans couleurs dans le log du cas
_test_log_lines() {
    local line
    while IFS= read -r line; do
        printf '%(%H:%M:%S)T %s\n' -1 "$line"
        printf '%(%H:%M:%S)T %s\n' -1 "$line" | sed -u 's/\x1b\[[0-9;]*m//g' >> "$BB_TEST_LOG_FILE"
    done
}

# Copie sans couleurs (pour l'analyse de la sortie), puis log horodaté
# $1 : fichier de capture
_test_capture() {
    local line
    : > "$1"
    while IFS= read -r line; do
        printf '%s\n' "$line" | sed 's/\x1b\[[0-9;]*m//g; s/\r/\n/g' >> "$1"
        printf '%s\n' "$line"
    done | _test_log_lines
}

_test_step() { printf '######## %s\n' "$*" | _test_log_lines; }

# Commande dans la sandbox, bornée côté hôte (filet de sécurité si SSH ne rend pas la main)
# $1 : durée maximale, $2 : commande, stdin : transmis à la commande
_test_vm() {
    timeout --kill-after=10 "$1" "${BB_TEST_SANDBOX_CMD[@]}" exec "$2"
}

# Crée la sandbox de la release si elle n'existe pas encore
_test_prepare_sandbox() {
    if [[ ! -f "$BB_SANDBOX_DIR/vm-$BB_TEST_RELEASE/overlay.qcow2" ]]; then
        BB_TEST_LOG_FILE="$BB_TEST_LOG_DIR/create.log"
        _test_step "création de la sandbox $BB_TEST_RELEASE"
        timeout --kill-after=10 900 "${BB_TEST_SANDBOX_CMD[@]}" create </dev/null 2>&1 | _test_log_lines
    fi
}

# $1 : cas (pour l'enregistrement d'une erreur)
_test_reset_sandbox() {
    local out="$BB_TEST_LOG_DIR/context/$1.reset.out" status=0 start=$SECONDS
    _test_step "reset de la sandbox"
    { timeout 120 "${BB_TEST_SANDBOX_CMD[@]}" reset </dev/null 2>&1 \
        && timeout 360 "${BB_TEST_SANDBOX_CMD[@]}" start </dev/null 2>&1; } | _test_capture "$out" || status=$?
    if (( status != 0 )); then
        report_record "$1" setup "reset de la sandbox" error $((SECONDS - start)) \
            "Code $status. Fin de la sortie :"$'\n'"$(tail -n 20 "$out")"
    fi
    return "$status"
}

# Exécute une fonction d'assertions du cas dans la VM et enregistre chaque assertion
# $1 : cas, $2 : fonction (test_run, test_after_install, test_after_uninstall), $3 : phase
_test_assertions() {
    local case_name="$1" fn="$2" phase="$3" status=0 start=$SECONDS
    local case_file="$BB_TEST_CASES_DIR/$1.sh" out="$BB_TEST_LOG_DIR/context/$1.$3.out"

    { cat "$BB_TEST_DIR/lib/assert.sh" "$case_file"
      printf '\n%s\nreport_leftovers >/dev/null\nreport\n' "$fn"
    } | _test_vm 300 'timeout --kill-after=5 280 bash -s' 2>&1 | _test_capture "$out" || status=$?

    report_parse_assertions "$case_name" "$phase" "$out" $((SECONDS - start))
    return "$status"
}

# La Bigbox (Bash ou Go selon --impl) bornée DANS la VM (un timeout côté hôte ne tuerait que
# le client SSH). TEST_ENV (variables du cas, ex. BIGBOX_ESSAI=1) préfixe la commande.
# $1 : cas, $2 : phase, $3 : arguments de la Bigbox
_test_bigbox() {
    local case_name="$1" phase="$2" args="$3" status=0 start=$SECONDS duration
    local out="$BB_TEST_LOG_DIR/context/$1.$2.out" label="$BB_TEST_BIGBOX $3"

    _test_step "$label (max ${BB_TEST_ACTION_TIMEOUT} s)"
    _test_vm $((BB_TEST_ACTION_TIMEOUT + 60)) \
        "timeout --kill-after=10 $BB_TEST_ACTION_TIMEOUT env ${TEST_ENV:-} $BB_TEST_BIGBOX $args" </dev/null 2>&1 \
        | _test_capture "$out" || status=$?
    duration=$((SECONDS - start))

    if (( status == 0 )); then
        _test_step "$label : code 0 en $duration s"
        report_record "$case_name" "$phase" "$label" passed "$duration"
        return 0
    fi

    local reason="code $status"
    (( status == 124 )) && reason="timeout de ${BB_TEST_ACTION_TIMEOUT} s atteint"
    _test_step "❌ $label : $reason en $duration s"
    report_record "$case_name" "$phase" "$label" error "$duration" "$(
        printf 'Échec : %s en %s s\n' "$reason" "$duration"
        if [[ "$BB_TEST_IMPL" == go ]]; then
            # Contexte : étapes en échec (✗) avec cause, commande, stderr, remède et journal
            printf '\nÉtapes en échec :\n'
            grep -A12 '^✗ ' "$out" | head -n 40 || true
        else
            # Contexte : modules terminés (✅/❌), erreurs de run_cmd (🧨)
            printf '\nModules :\n'
            grep -oE '(✅|❌) \[[^]]+\] [a-z]+' "$out" | sed 's/^/  /' || true
            printf '\nErreurs remontées (🧨) :\n'
            grep -A8 '🧨' "$out" | head -n 30 || true
        fi
        printf '\nFin de la sortie :\n'
        tail -n 25 "$out"
    )"
    return "$status"
}

# Exécute un cas, retourne 0 s'il réussit
# $1 : nom du cas
_test_case() {
    local name="$1" case_file="$BB_TEST_CASES_DIR/$1.sh" failed=0
    local TEST_DESCRIPTION="" TEST_INSTALL_ARGS="" TEST_UNINSTALL_ARGS="" TEST_RESET=true
    local TEST_ACTION_TIMEOUT="" TEST_ENV=""

    # shellcheck source=/dev/null
    source "$case_file"
    BB_TEST_ACTION_TIMEOUT="${BB_TEST_TIMEOUT_OVERRIDE:-${TEST_ACTION_TIMEOUT:-$BB_TEST_DEFAULT_ACTION_TIMEOUT}}"
    BB_TEST_LOG_FILE="$BB_TEST_LOG_DIR/$name.log"
    _test_step "cas $name : $TEST_DESCRIPTION"

    if [[ -z "$TEST_INSTALL_ARGS" ]]; then
        # Cas sans action de la Bigbox : assertions seules
        if [[ "$TEST_RESET" == true ]]; then _test_reset_sandbox "$name" || return 1; fi
        _test_assertions "$name" test_run run || failed=1
        return "$failed"
    fi

    _test_reset_sandbox "$name" || return 1

    _test_step "préparation du poste"
    local out="$BB_TEST_LOG_DIR/context/$name.setup.out" start=$SECONDS status=0
    _test_vm 150 'timeout --kill-after=5 120 bash -s' < "$BB_TEST_DIR/lib/prepare_desktop.sh" 2>&1 \
        | _test_capture "$out" || status=$?
    if (( status != 0 )); then
        report_record "$name" setup "préparation du poste" error $((SECONDS - start)) \
            "Code $status. Sortie :"$'\n'"$(tail -n 20 "$out")"
        return 1
    fi

    # L'uninstall est joué même après un échec d'install : il doit nettoyer une install partielle
    _test_bigbox "$name" install "$TEST_INSTALL_ARGS" || failed=1
    _test_assertions "$name" test_after_install after_install || failed=1
    _test_bigbox "$name" uninstall "$TEST_UNINSTALL_ARGS" || failed=1
    _test_assertions "$name" test_after_uninstall after_uninstall || failed=1
    return "$failed"
}

_test_usage() {
    sed -n '/^# Usage/,/^# Rapports/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    printf '\nCas disponibles : %s\n' "$(_test_all_cases | paste -sd ' ')"
}

# deps (rapide, sans reset) en premier, full (le plus long) en dernier, s'ils existent
_test_all_cases() {
    local f name
    [[ -f "$BB_TEST_CASES_DIR/deps.sh" ]] && echo deps
    for f in "$BB_TEST_CASES_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f" .sh)
        [[ "$name" == deps || "$name" == full ]] || echo "$name"
    done
    [[ -f "$BB_TEST_CASES_DIR/full.sh" ]] && echo full
    return 0
}

# $1 : implémentation (bash ou go)
# shellcheck disable=SC2088 # ~ développé dans la VM, pas sur l'hôte
_test_select_impl() {
    case "$1" in
        bash) BB_TEST_IMPL=bash; BB_TEST_CASES_DIR="$BB_TEST_DIR/cases"; BB_TEST_BIGBOX=./bigbox ;;
        go)   BB_TEST_IMPL=go; BB_TEST_CASES_DIR="$BB_TEST_DIR/cases-go"; BB_TEST_BIGBOX='~/bin/bigbox' ;;
        *)    echo "Implémentation inconnue : $1 (bash ou go)" >&2; return 2 ;;
    esac
}

# Une release par runner enfant, en parallèle, sortie préfixée par la release
# $1 : releases séparées par des virgules, $@ : arguments transmis aux enfants
_test_parallel() {
    local releases=() release pids=() statuses=() failed=0 i status
    IFS=',' read -ra releases <<< "$1"
    shift

    export BB_TEST_LOG_BASE
    # Ctrl+C arrête tous les runners
    trap 'kill 0' INT TERM

    for release in "${releases[@]}"; do
        # Sous-shell : avec pipefail, son code est celui du runner et non celui du sed
        ( "${BASH_SOURCE[0]}" -r "$release" "$@" 2>&1 | sed -u "s/^/[$release] /" ) &
        pids+=($!)
    done

    for i in "${!releases[@]}"; do
        status=0
        wait "${pids[$i]}" || status=$?
        statuses+=("$status")
        (( status == 0 )) || failed=1
    done

    # Rapport global : tableau des releases puis rapport de chacune
    # shellcheck disable=SC2016 # Backticks Markdown
    {
        printf '# Rapport de test global\n\n| Release | Statut | Rapport |\n|---|---|---|\n'
        for i in "${!releases[@]}"; do
            printf '| Ubuntu %s | %s | `%s` |\n' "${releases[$i]}" \
                "$( (( statuses[i] == 0 )) && echo "✅" || echo "❌")" "$BB_TEST_LOG_BASE/${releases[$i]}/report.md"
        done
        printf '\n'
        for i in "${!releases[@]}"; do
            if [[ -f "$BB_TEST_LOG_BASE/${releases[$i]}/report.md" ]]; then
                sed 's/^#/##/' "$BB_TEST_LOG_BASE/${releases[$i]}/report.md"
            else
                printf '## Rapport de test : Ubuntu %s\n\nAucun rapport, le runner s'"'"'est arrêté avant la fin (code %s).\n' \
                    "${releases[$i]}" "${statuses[$i]}"
            fi
            printf '\n'
        done
    } > "$BB_TEST_LOG_BASE/report.md"

    printf '\n======== Résumé global\n'
    for i in "${!releases[@]}"; do
        printf '%s Ubuntu %s\n' "$( (( statuses[i] == 0 )) && echo "✅" || echo "❌")" "${releases[$i]}"
    done
    printf 'Rapport : %s\n' "$BB_TEST_LOG_BASE/report.md"
    return "$failed"
}

# --------------------
# Point d'entrée
# --------------------
main() {
    local cases=() name status results=() failed=0 start passthrough=() run_start=$SECONDS

    while (( $# > 0 )); do
        case "$1" in
            -r) BB_TEST_RELEASE="${2:?release attendue après -r}"; shift 2 ;;
            -t) BB_TEST_TIMEOUT_OVERRIDE="${2:?durée attendue après -t}"; passthrough+=(-t "$2"); shift 2 ;;
            --impl) _test_select_impl "${2:?implémentation attendue après --impl}" || return 2
                    passthrough+=(--impl "$2"); shift 2 ;;
            -h|--help) _test_usage; return 0 ;;
            -*) echo "Option inconnue : $1" >&2; _test_usage >&2; return 2 ;;
            *) cases+=("$1"); shift ;;
        esac
    done
    (( ${#cases[@]} > 0 )) || mapfile -t cases < <(_test_all_cases)
    if (( ${#cases[@]} == 0 )); then
        echo "Aucun cas dans $BB_TEST_CASES_DIR" >&2
        return 2
    fi

    for name in "${cases[@]}"; do
        if [[ ! -f "$BB_TEST_CASES_DIR/$name.sh" ]]; then
            echo "Cas inconnu : $name (disponibles : $(_test_all_cases | paste -sd ' '))" >&2
            return 2
        fi
    done

    # Logs séparés par implémentation : <date> (bash, inchangé) ou <date>-go
    if [[ -z "$BB_TEST_LOG_BASE" ]]; then
        BB_TEST_LOG_BASE="$BB_SANDBOX_DIR/logs/$(date +%Y%m%d-%H%M%S)"
        [[ "$BB_TEST_IMPL" == bash ]] || BB_TEST_LOG_BASE+="-$BB_TEST_IMPL"
    fi
    mkdir -p "$BB_TEST_LOG_BASE"
    if [[ "$BB_TEST_RELEASE" == *,* ]]; then
        _test_parallel "$BB_TEST_RELEASE" "${passthrough[@]}" "${cases[@]}"
        return
    fi

    BB_TEST_SANDBOX_CMD=("$BB_TEST_SANDBOX" -r "$BB_TEST_RELEASE")
    BB_TEST_LOG_DIR="$BB_TEST_LOG_BASE/$BB_TEST_RELEASE"
    BB_TEST_RESULTS="$BB_TEST_LOG_DIR/results.tsv"
    mkdir -p "$BB_TEST_LOG_DIR/context"
    : > "$BB_TEST_RESULTS"
    _test_prepare_sandbox
    timeout 360 "${BB_TEST_SANDBOX_CMD[@]}" start </dev/null >/dev/null 2>&1

    for name in "${cases[@]}"; do
        start=$SECONDS
        status=0
        _test_case "$name" || status=$?
        if (( status == 0 )); then
            results+=("✅ $name ($((SECONDS - start)) s)")
        else
            results+=("❌ $name ($((SECONDS - start)) s) : $BB_TEST_LOG_DIR/$name.log")
            failed=1
        fi
    done

    # La sandbox est laissée vierge et arrêtée
    timeout 120 "${BB_TEST_SANDBOX_CMD[@]}" reset </dev/null >/dev/null 2>&1 || true

    report_generate "$BB_TEST_RELEASE" $((SECONDS - run_start))

    printf '\n======== Résumé (Ubuntu %s, Bigbox %s)\n' "$BB_TEST_RELEASE" "$BB_TEST_IMPL"
    printf '%s\n' "${results[@]}"
    printf 'Rapport : %s\nJUnit   : %s\n' "$BB_TEST_LOG_DIR/report.md" "$BB_TEST_LOG_DIR/junit.xml"
    return "$failed"
}

main "$@"
