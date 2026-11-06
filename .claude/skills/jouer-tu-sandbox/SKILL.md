---
name: jouer-tu-sandbox
description: Jouer les tests (TU) de la Bigbox dans la sandbox QEMU/KVM, sur une ou plusieurs distributions Ubuntu (24.04, 26.04 ...), en parallèle, puis lire le rapport JUnit/Markdown. À utiliser pour valider une modification, vérifier une release Ubuntu particulière ou établir un rapport d'exécution.
---

# Jouer les TU de la Bigbox (sandbox)

**Ne jamais lancer `./bigbox` sur l'hôte.** Tout passe par `tests/run.sh`, qui pilote une VM par release via `tools/sandbox/sandbox.sh`.

## 1. Vérifications préalables (hôte)

```bash
test -r /dev/kvm -a -w /dev/kvm && echo kvm OK
nproc; free -g | sed -n 2p          # 2 vCPU et 4 Go de RAM par VM
df -h ~/.cache | tail -1            # au plus 20 Go par VM (qcow2 alloué à l'usage)
tools/sandbox/sandbox.sh status     # VM existantes et état
```

Une VM en cours d'exécution hors d'un run (état « démarrée ») vient d'un run interrompu : la remettre à zéro avec `tools/sandbox/sandbox.sh -r <release> reset`.

## 2. Cibler une distribution

| Commande | Effet |
|---|---|
| `tests/run.sh` | tous les cas sur 24.04 |
| `tests/run.sh -r 26.04` | tous les cas sur 26.04 |
| `tests/run.sh -r 24.04,26.04` | tous les cas, **les deux releases en parallèle** |
| `tests/run.sh -r 26.04 pg qol` | certains cas seulement |
| `tests/run.sh -t 180 full` | force la durée maximale de chaque install/uninstall |

- Une VM par release : `~/.cache/bigbox-sandbox/vm-<release>/`, port SSH `2<release sans point>` (22404, 22604).
- Une VM absente est créée automatiquement : téléchargement de l'image cloud (environ 600 Mo, vérifiée par SHA256, conservée), puis cloud-init. Compter 3 à 5 min la première fois.
- Le dépôt est synchronisé dans la VM à chaque commande : on teste l'arbre de travail, modifications non commitées comprises (le rapport le signale).

## 3. Lancer sans attendre à l'aveugle

Durées indicatives par release : deps 5 s, qol 1 min, pg 1 min 30, full 4 à 6 min. Avec la création des VM, un run complet dure 10 à 20 min.

Lancer en arrière-plan, avec une borne globale, et suivre le log :

```bash
LOG=$CLAUDE_JOB_DIR/tmp/tu.out      # ou tout fichier temporaire hors du dépôt
nohup timeout 2700 tests/run.sh -r 24.04,26.04 > "$LOG" 2>&1 &
# Attente bornée (moins de 10 min par appel), à répéter jusqu'au résumé
timeout 580 bash -c "until grep -q -e '======== Résumé' '$LOG'; do sleep 15; done"; tail -5 "$LOG"
# Progression
grep -E 'cas |code [0-9]+ en|❌' "$LOG" | tail -20
```

Toutes les étapes sont bornées par le lanceur : install et uninstall 120 s par défaut (`TEST_ACTION_TIMEOUT` du cas), assertions 10 s chacune, reset 120 s, préparation 120 s. Un run ne peut donc pas tourner indéfiniment. Si le log n'avance plus depuis plus de 6 min, c'est un incident d'infrastructure : le signaler.

## 4. Lire les résultats

Sorties dans `~/.cache/bigbox-sandbox/logs/<date>/` :

| Fichier | Contenu |
|---|---|
| `report.md` | rapport global (mode parallèle) : statut par release puis rapport de chacune |
| `<release>/report.md` | synthèse, tableau des cas, puis sections 🔴 Régressions, 🟠 Nouveaux en échec, 🟡 Échecs connus, 🟢 Corrigés, chaque échec avec son scénario et son contexte |
| `<release>/junit.xml` | JUnit : un `testsuite` par cas (`ubuntu-<release>.<cas>`), un `testcase` par vérification (`classname` = `ubuntu-<release>.<cas>.<phase>`). `<failure>` pour une assertion fausse, `<error>` pour une action en échec ; l'attribut `type` porte la classification |
| `<release>/results.tsv` | résultats bruts : cas, phase, nom, statut, durée, fichier de contexte |
| `<release>/<cas>.log` | log horodaté complet du cas |
| `<release>/context/` | contexte de chaque échec et sorties capturées par phase |

Phases : `setup` (reset, préparation du poste), `install`, `after_install`, `uninstall`, `after_uninstall`, `run` (cas sans action).

Classification, calculée contre `~/.cache/bigbox-sandbox/logs/baseline/<release>.tsv` (dernier statut connu de chaque test, mis à jour à chaque run) :
- **RÉGRESSION** : le test passait au run précédent ;
- **nouveau test en échec** : le test n'a pas de référence ;
- **échec connu** : déjà en échec au run précédent ;
- **corrigé** : en échec au run précédent, passe maintenant.

Le code de sortie de `tests/run.sh` est non nul dès qu'un test échoue.

## 5. Après le run

La sandbox est remise au snapshot `pristine` et arrêtée par le lanceur. En cas d'interruption (Ctrl+C, timeout global), le faire soi-même pour chaque release : `tools/sandbox/sandbox.sh -r <release> reset`, puis contrôler avec `tools/sandbox/sandbox.sh status` qu'aucune VM ne tourne.

## 6. Incidents d'infrastructure connus

- `curl: (28)` ou `(55)/(56)` dans un log d'install : coupure réseau, relancée automatiquement par `BB_CURL_OPTS`. Ce n'est un échec que si l'action finit en erreur.
- « Pas de connexion SSH après 300 s » : VM qui ne démarre pas, voir `vm-<release>/console.log`.
- « La somme SHA256 ne correspond pas » : image corrompue (supprimée automatiquement), relancer.
- Port SSH occupé : une autre VM de la même release tourne déjà (un seul run par release à la fois).
