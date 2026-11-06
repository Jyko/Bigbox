# shellcheck shell=bash
# shellcheck disable=SC2016 # Les backticks sont du Markdown, pas des substitutions
#################################################################################
# Résultats et rapports des tests, côté hôte (sourcé par tests/run.sh).
#
# Chaque résultat est une ligne de results.tsv (séparateur tabulation) :
#   cas  phase  nom  statut  durée(s)  fichier_de_contexte
#   statut : passed | failed (assertion fausse) | error (action ou exécution en échec)
#
# Rapports produits par release :
#   junit.xml  : format JUnit (un testsuite par cas, un testcase par vérification)
#   report.md  : résumé, régressions, échecs avec contexte, corrections
# Les régressions se calculent contre la référence $BB_SANDBOX_DIR/logs/baseline/<release>.tsv,
# mise à jour à la fin de chaque run avec le dernier statut connu de chaque test.
#################################################################################

# Enregistrer un résultat
# $1 cas, $2 phase, $3 nom, $4 statut, $5 durée, $6 contexte (texte, optionnel)
report_record() {
    local case_name="$1" phase="$2" name="$3" status="$4" duration="$5" context="${6:-}"
    local context_file=""

    if [[ -n "$context" ]]; then
        mkdir -p "$BB_TEST_LOG_DIR/context"
        context_file="$BB_TEST_LOG_DIR/context/$case_name.$phase.$(( $(wc -l < "$BB_TEST_RESULTS" 2>/dev/null || echo 0) + 1 )).txt"
        printf '%s\n' "$context" > "$context_file"
    fi
    # Pas de tabulation ni de retour à la ligne dans les champs
    name=$(tr '\t\n' '  ' <<< "$name" | sed 's/ *$//')
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$case_name" "$phase" "$name" "$status" "$duration" "$context_file" >> "$BB_TEST_RESULTS"
}

# Transformer la sortie d'une fonction d'assertions en résultats
# $1 cas, $2 phase, $3 fichier de sortie (sans couleurs ni horodatage), $4 durée totale
report_parse_assertions() {
    local case_name="$1" phase="$2" out="$3" duration="$4"
    local line label="" context="" count=0

    _flush() {
        if [[ -n "$label" ]]; then
            if [[ -n "$context" ]]; then
                report_record "$case_name" "$phase" "$label" failed 0 "$context"
            else
                report_record "$case_name" "$phase" "$label" passed 0
            fi
        fi
        label="" context=""
    }

    while IFS= read -r line; do
        case "$line" in
            "✅ "*) _flush; label="${line#✅ }"; count=$((count + 1)) ;;
            "❌ "*) _flush; label="${line#❌ }"; context="(assertion fausse)"; count=$((count + 1)) ;;
            "   ↳ "*) [[ -n "$label" ]] && context+=$'\n'"${line#   ↳ }" ;;
            *) _flush ;;
        esac
    done < "$out"
    _flush

    # Assertions qui n'ont pas pu s'exécuter jusqu'au bout (SSH coupé, timeout global ...)
    if ! grep -q '^RESULTAT:' "$out"; then
        report_record "$case_name" "$phase" "exécution des assertions ($count jouées)" error "$duration" \
            "Les assertions ne sont pas allées jusqu'au bout. Fin de la sortie :"$'\n'"$(tail -n 20 "$out")"
    fi
}

_report_xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"
    # Caractères de contrôle (séquences ANSI résiduelles) interdits en XML
    printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'
}

# Statut de référence d'un test : passed, failed, error ou vide (inconnu)
# $1 fichier de référence, $2 clé "cas<TAB>phase<TAB>nom"
_report_baseline_status() {
    [[ -f "$1" ]] || return 0
    awk -F'\t' -v k="$2" '($1"\t"$2"\t"$3) == k { print $4 }' "$1"
}

# Classification d'un résultat par rapport à la référence
# $1 statut courant, $2 statut de référence
_report_classify() {
    case "$1:$2" in
        passed:failed|passed:error) echo "corrigé" ;;
        passed:*) echo "ok" ;;
        *:passed) echo "RÉGRESSION" ;;
        *:failed|*:error) echo "échec connu" ;;
        *:) echo "nouveau test en échec" ;;
    esac
}

# Générer junit.xml et report.md, puis mettre à jour la référence
# $1 release, $2 durée totale du run
report_generate() {
    local release="$1" total_duration="$2"
    local baseline="$BB_SANDBOX_DIR/logs/baseline/$release.tsv"
    local junit="$BB_TEST_LOG_DIR/junit.xml" md="$BB_TEST_LOG_DIR/report.md"
    local case_name phase name status duration context_file class ref
    local tests failures errors suite_time

    [[ -f "$BB_TEST_RESULTS" ]] || : > "$BB_TEST_RESULTS"
    local case_names=()
    mapfile -t case_names < <(cut -f1 "$BB_TEST_RESULTS" | awk '!seen[$0]++')

    # ---- JUnit
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<testsuites name="bigbox" tests="%s" failures="%s" errors="%s" time="%s">\n' \
            "$(wc -l < "$BB_TEST_RESULTS")" \
            "$(awk -F'\t' '$4=="failed"' "$BB_TEST_RESULTS" | wc -l)" \
            "$(awk -F'\t' '$4=="error"' "$BB_TEST_RESULTS" | wc -l)" "$total_duration"
        for case_name in "${case_names[@]}"; do
            tests=$(awk -F'\t' -v c="$case_name" '$1==c' "$BB_TEST_RESULTS" | wc -l)
            failures=$(awk -F'\t' -v c="$case_name" '$1==c && $4=="failed"' "$BB_TEST_RESULTS" | wc -l)
            errors=$(awk -F'\t' -v c="$case_name" '$1==c && $4=="error"' "$BB_TEST_RESULTS" | wc -l)
            suite_time=$(awk -F'\t' -v c="$case_name" '$1==c { t += $5 } END { print t+0 }' "$BB_TEST_RESULTS")
            printf '  <testsuite name="ubuntu-%s.%s" tests="%s" failures="%s" errors="%s" time="%s">\n' \
                "$release" "$case_name" "$tests" "$failures" "$errors" "$suite_time"
            while IFS=$'\t' read -r _ phase name status duration context_file; do
                printf '    <testcase classname="ubuntu-%s.%s.%s" name="%s" time="%s"' \
                    "$release" "$case_name" "$phase" "$(_report_xml_escape "$name")" "$duration"
                if [[ "$status" == passed ]]; then
                    printf '/>\n'
                    continue
                fi
                ref=$(_report_baseline_status "$baseline" "$case_name"$'\t'"$phase"$'\t'"$name")
                class=$(_report_classify "$status" "$ref")
                printf '>\n      <%s type="%s" message="%s"><![CDATA[%s]]></%s>\n    </testcase>\n' \
                    "$([[ "$status" == error ]] && echo error || echo failure)" "$class" \
                    "$(_report_xml_escape "$name")" \
                    "$( [[ -n "$context_file" ]] && sed 's/]]>/]]]]><![CDATA[>/g' "$context_file" | tr -d '\000-\010\013\014\016-\037')" \
                    "$([[ "$status" == error ]] && echo error || echo failure)"
            done < <(awk -F'\t' -v c="$case_name" '$1==c' "$BB_TEST_RESULTS")
            printf '  </testsuite>\n'
        done
        printf '</testsuites>\n'
    } > "$junit"

    # ---- Markdown
    local total passed failed regressions=() known=() new_failures=() fixed=() line
    total=$(wc -l < "$BB_TEST_RESULTS")
    passed=$(awk -F'\t' '$4=="passed"' "$BB_TEST_RESULTS" | wc -l)
    failed=$(( total - passed ))

    while IFS=$'\t' read -r case_name phase name status duration context_file; do
        ref=$(_report_baseline_status "$baseline" "$case_name"$'\t'"$phase"$'\t'"$name")
        class=$(_report_classify "$status" "$ref")
        line="$case_name|$phase|$name|$status|$duration|$context_file"
        case "$class" in
            "RÉGRESSION") regressions+=("$line") ;;
            "échec connu") known+=("$line") ;;
            "nouveau test en échec") new_failures+=("$line") ;;
            "corrigé") fixed+=("$line") ;;
        esac
    done < "$BB_TEST_RESULTS"

    _report_md_failures() {
        local entry c p n s d f
        for entry in "$@"; do
            IFS='|' read -r c p n s d f <<< "$entry"
            printf '### `%s` › %s › %s\n\n' "$c" "$p" "$n"
            printf -- '- statut : **%s**%s\n' "$s" "$( (( d > 0 )) && echo " (${d} s)")"
            printf -- '- scénario : %s\n' "$(_report_case_description "$c")"
            printf -- '- log complet : `%s`\n' "$BB_TEST_LOG_DIR/$c.log"
            if [[ -n "$f" ]]; then
                printf -- '- contexte (`%s`) :\n\n```text\n%s\n```\n' "$f" "$(head -n 40 "$f")"
            fi
            printf '\n'
        done
    }

    {
        printf '# Rapport de test : Ubuntu %s\n\n' "$release"
        printf -- '- commit : `%s`%s\n' "$(git -C "$BB_TEST_REPO_DIR" rev-parse --short HEAD 2>/dev/null)" \
            "$( [[ -n "$(git -C "$BB_TEST_REPO_DIR" status --porcelain 2>/dev/null)" ]] && echo " (+ modifications non commitées)")"
        printf -- '- date : %s, durée : %s s\n' "$(date '+%Y-%m-%d %H:%M')" "$total_duration"
        printf -- '- référence : `%s`%s\n\n' "$baseline" "$([[ -f "$baseline" ]] || echo " (absente : premier run)")"
        printf '| Tests | Réussis | En échec | Régressions | Échecs connus | Nouveaux en échec | Corrigés |\n'
        printf '|---|---|---|---|---|---|---|\n'
        printf '| %s | %s | %s | %s | %s | %s | %s |\n\n' "$total" "$passed" "$failed" \
            "${#regressions[@]}" "${#known[@]}" "${#new_failures[@]}" "${#fixed[@]}"

        printf '## Cas\n\n| Cas | Scénario | Tests | Échecs | Durée |\n|---|---|---|---|---|\n'
        for case_name in "${case_names[@]}"; do
            printf '| %s %s | %s | %s | %s | %s s |\n' \
                "$(awk -F'\t' -v c="$case_name" '$1==c && $4!="passed"' "$BB_TEST_RESULTS" | grep -q . && echo ❌ || echo ✅)" \
                "$case_name" "$(_report_case_description "$case_name")" \
                "$(awk -F'\t' -v c="$case_name" '$1==c' "$BB_TEST_RESULTS" | wc -l)" \
                "$(awk -F'\t' -v c="$case_name" '$1==c && $4!="passed"' "$BB_TEST_RESULTS" | wc -l)" \
                "$(awk -F'\t' -v c="$case_name" '$1==c { t += $5 } END { print t+0 }' "$BB_TEST_RESULTS")"
        done
        printf '\n'

        if (( ${#regressions[@]} > 0 )); then
            printf '## 🔴 Régressions (réussis au run précédent)\n\n'; _report_md_failures "${regressions[@]}"
        fi
        if (( ${#new_failures[@]} > 0 )); then
            printf '## 🟠 Nouveaux tests en échec (sans référence)\n\n'; _report_md_failures "${new_failures[@]}"
        fi
        if (( ${#known[@]} > 0 )); then
            printf '## 🟡 Échecs connus (déjà en échec au run précédent)\n\n'; _report_md_failures "${known[@]}"
        fi
        if (( ${#fixed[@]} > 0 )); then
            printf '## 🟢 Corrigés (en échec au run précédent)\n\n'
            local entry c p n
            for entry in "${fixed[@]}"; do IFS='|' read -r c p n _ <<< "$entry"; printf -- '- `%s` › %s › %s\n' "$c" "$p" "$n"; done
            printf '\n'
        fi
        printf '## Fichiers\n\n- JUnit : `%s`\n- résultats bruts : `%s`\n- logs par cas : `%s/<cas>.log`\n' \
            "$junit" "$BB_TEST_RESULTS" "$BB_TEST_LOG_DIR"
    } > "$md"

    # ---- Référence : dernier statut connu de chaque test joué
    mkdir -p "$(dirname "$baseline")"
    local merged
    merged=$(mktemp)
    awk -F'\t' 'NR==FNR { seen[$1"\t"$2"\t"$3]=1; print; next } !(($1"\t"$2"\t"$3) in seen)' \
        "$BB_TEST_RESULTS" "${baseline}" 2>/dev/null > "$merged" || cat "$BB_TEST_RESULTS" > "$merged"
    cut -f1-4 "$merged" > "$baseline"
    rm -f "$merged"
}

# Description d'un cas (TEST_DESCRIPTION de son fichier)
_report_case_description() {
    sed -n 's/^TEST_DESCRIPTION="\(.*\)"$/\1/p' "$BB_TEST_DIR/cases/$1.sh" 2>/dev/null
}
