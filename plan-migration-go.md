# Plan d'exécution de la migration Go

> Branche `feat/go`, 2026-11-06. Ce document découpe en étapes exécutables la cible décrite dans
> [`migration.md`](migration.md), qui reste la référence pour le *quoi* et le *pourquoi* (charts,
> exposition, secrets, dotfiles…). Ici : le *comment* et l'*ordre*.

## Décisions de cadrage

| Décision | Conséquence |
|---|---|
| **Bash gelé** | Aucune évolution de la Bigbox Bash : ni charts officiels, ni Traefik/ServiceLB, ni revue des paquets (anciennes étapes 0a à 0d). Tout est fait directement en Go. Le Bash reste la **référence fonctionnelle** jusqu'à la parité, et seul un bug bloquant pourrait y être corrigé. |
| **Go en parallèle** | Le binaire `bigbox` (Go) est construit à côté du script `./bigbox` et ne connaît que les features déjà portées. Les TU visent l'une ou l'autre implémentation (`tests/run.sh --impl bash\|go`). Le Bash est supprimé à l'étape 8. |
| **Re-conception, pas transposition** | On porte le **comportement** vérifié par les TU (ce qui est installé, préservé, retiré), jamais la structure du Bash. Les logs, les erreurs et les messages, insuffisants en Bash, sont conçus de zéro (section 2). |

## Décisions encore ouvertes

| Décision | À trancher | Éléments |
|---|---|---|
| SDK Helm v3 ou v4 | début de l'étape 3 | maturité de l'API Go de la v4, compatibilité des charts retenus, post-renderers |
| Mécanisme d'écoute limitée au bouclage | étape 3 | `hostIP` sur Traefik, `--bind-address` de k3s, nftables (`migration.md` 7.2, point 5) |
| CopyQ ou GPaste | étape 7 | surveillance du presse-papier sous Wayland |
| Données pg d'un poste Bash : import CNPG ou remise à zéro | étape 8 | coût de `mode: recovery` / `import` contre une remise à zéro documentée |
| Lanceur Windows | étape 8 | besoin réel des utilisateurs WSL2 |
| Repli `groundhog2k/postgres` si CNPG pèse trop | étape 6 (mesures) | RAM au repos de l'opérateur et du webhook |

---

## 1. Principes transverses

1. **Chaque étape livre un binaire utilisable** sur les features déjà portées, et se termine par des
   critères de sortie vérifiables : tests unitaires et lint verts, TU Go verts sur 24.04 **et** 26.04.
2. **Rien ne s'exécute sur le poste de développement** : comme aujourd'hui, le binaire n'est lancé que
   dans la sandbox. Les tests unitaires n'exécutent jamais `apt`, `systemctl` ni `sudo` : ils passent
   par le faux `Runner`.
3. **Le registre de propriété reste la règle d'or** : ne rien retirer que la Bigbox n'ait installé.
   Les TU Go réutilisent `tests/lib/prepare_desktop.sh` et `assert_desktop_preserved`.
4. **Idempotence vérifiée, pas supposée** : un second `apply` sans changement de `bigbox.yaml` ne
   produit **aucune** étape « modifié ». Un TU dédié le garantit.
5. **Tout est borné** : chaque étape d'une feature a un délai (`context.WithTimeout`), propagé jusqu'à
   `exec.CommandContext` et aux appels client-go et Helm.

### 1.1 Mauvaises pratiques du Bash à ne pas reproduire

| Bash (où) | Problème | Remplacement en Go |
|---|---|---|
| `core/log.sh` : `\r\t`, `\n` et emojis écrits dans chaque message ; aucun fichier de log | mise en forme mêlée au contenu ; rien à relire après une exécution | logs structurés (`log/slog`) ; le rendu console est fait par un seul composant ; journal JSONL systématique (section 2.2) |
| `run_cmd` (`core/utils.sh`) : sortie jetée si succès, déversée brute si échec, non capturée en debug | aucune trace exploitable a posteriori ; en debug, la sortie se mélange à l'affichage | `Runner` : argv masqué, durée, code de sortie, stdout et stderr **toujours** écrits dans le journal, quel que soit le niveau console |
| `run_cmd_silently` pour les conditions | une condition en échec et une vraie panne se confondent | `Observe()` renvoie un état typé ; une commande de test a une sémantique explicite (`Runner.Probe`) |
| `_module_on_error` : `❌ [pg] install (code:1)` | ni étape, ni commande, ni cause, ni remède | erreur typée `*errs.Error` (section 2.1) |
| `apt_purge_owned … \|\| true` dans les uninstall | échecs avalés en silence ; poste à moitié nettoyé sans le savoir | désinstallation « best effort » qui **continue et collecte** les échecs (`errors.Join`), puis les rapporte tous avec un code de sortie non nul |
| watchdog `_module_watchdog_*` | ne tue pas les processus lancés par sudo (root) ; délai global unique | délai par étape, annulation par contexte ; `sudo` lancé avec `exec.CommandContext` et un groupe de processus |
| `parse_args` (FIXME) + `resources/action.json` (booléens en chaînes `"true"`) | parsing fragile, propriétés non typées | cobra ; comportements d'action dans le code, typés |
| `priority` entière unique (`module.json`) | ordre implicite, collisions, vérification à la main | graphe de dépendances, tri topologique, détection de cycle **à la compilation des tests** |
| `sudo -v` au démarrage | root demandé même pour afficher l'aide | élévation seulement si le plan contient des étapes privilégiées, après affichage de leur liste et de la raison |
| `_pg_client_verify` et autres heuristiques `*_verify` | état réel mal observé (faux positifs documentés en commentaire) | `Observe()` explicite, testé sur des sorties de commandes enregistrées |
| avertissement générique « relancez votre shell » | sans contexte | message précis : ce qui a changé et la commande à lancer (« nouvelles commandes : kubectl, helm ; lancez `exec bash` ») |
| `curl` sans somme de contrôle (k3s mis à part) | chaîne d'approvisionnement | `internal/download` : URL, version et sha256 épinglés, vérifiés avant usage |
| variables globales `readonly` partagées entre fichiers sourcés | dépendances implicites | un `Env` passé explicitement à chaque feature |
| `get_host_ip` sans appelant, Hoppscotch, NUI dans le cluster | code mort ou retiré | non porté |

---

## 2. Erreurs, logs et messages : conception

C'est le chantier qui justifie le plus la réécriture : un utilisateur doit savoir, **sans relancer en
debug**, ce qui a échoué, pourquoi, et quoi faire.

### 2.1 Erreurs (`internal/errs`)

**Type :**

```go
type Kind int // Usage, Config, Precondition, Environment, Conflict, Internal

type Error struct {
    Kind    Kind
    Feature string   // "pg"
    Step    string   // "déployer le Cluster bigbox-pg"
    Op      string   // ce qu'on tentait, en langage utilisateur
    Cause   error    // erreur enveloppée (Unwrap)
    Hint    string   // action concrète à mener
    Command []string // argv, déjà masqué
    Stderr  []string // dernières lignes utiles (20 au plus)
}
```

- Compatible `errors.Is` / `errors.As` ; une feature enveloppe sans perdre la cause.
- La référence au journal (chemin + `run_id`) est ajoutée au rendu, pas stockée dans l'erreur.
- Une erreur sans `Kind` est traitée comme `Internal` et le message invite à ouvrir un ticket avec
  `bigbox logs --last`.

**Codes de sortie stables (documentés dans `bigbox --help`) :**

| Code | Signification |
|---|---|
| 0 | succès (pour `status` : aucune dérive) |
| 1 | échec d'au moins une étape d'`apply` |
| 2 | usage incorrect ou `bigbox.yaml` invalide |
| 3 | dérive détectée (`status`) ou changements en attente (`plan --detailed-exitcode`) |
| 4 | précondition non remplie : OS non supporté, sudo refusé, port occupé, espace disque |
| 130 | interruption (Ctrl-C) : l'étape en cours est annulée proprement, l'état reste cohérent |

**Catalogue de remèdes** (`internal/errs/hints.go`), testé unitairement sur des sorties réelles :

| Symptôme reconnu | Message « à faire » |
|---|---|
| `Could not get lock /var/lib/dpkg/lock-frontend` | « apt est utilisé par le processus <nom> (PID <n>) ; attendez la fin des mises à jour automatiques puis relancez » |
| port d'hôte déjà occupé | « le port 5432 est pris par <processus> (PID <n>) ; changez `features.pg.expose.port` dans bigbox.yaml » |
| API k3s injoignable | « k3s ne répond pas ; `sudo systemctl status k3s` puis `journalctl -u k3s -n 50` » |
| webhook CNPG non prêt | « l'opérateur cnpg démarre encore ; relancez `bigbox apply` » |
| DNS ou réseau | « <hôte> injoignable ; vérifiez la connexion ou le proxy (`HTTPS_PROXY`) » |
| sha256 différent | « le fichier téléchargé ne correspond pas à la version épinglée ; ne pas forcer, signaler » |
| sudo refusé ou sans TTY | « des étapes nécessitent root (liste) ; relancez dans un terminal interactif » |

**Erreurs de `bigbox.yaml`** : toujours `fichier:ligne:colonne`, la clé fautive, la valeur reçue et les
valeurs admises, et toutes les erreurs d'un coup (pas seulement la première) :

```
~/.config/bigbox/bigbox.yaml:9:12 : features.pg.state = "on" invalide (admis : running, stopped, absent)
~/.config/bigbox/bigbox.yaml:14:3 : features.hoppscotch : feature inconnue (retirée, voir migration.md 12.1)
```

**Rendu d'un échec :**

```
✗ pg › déployer le Cluster bigbox-pg  (échec après 42 s)
  cause    : webhook "mcluster.cnpg.io" injoignable (connection refused)
  commande : helm upgrade --install bigbox-pg cnpg/cluster 0.9.0
  à faire  : l'opérateur cnpg démarre encore ; relancez `bigbox apply`,
             ou consultez `kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg`
  journal  : ~/.local/state/bigbox/logs/2026-11-06T14-03-12-apply.jsonl (run 7f3a)
```

**Désinstallation « best effort » :** chaque étape est tentée même si une précédente échoue (sauf
dépendance d'ordre explicite, ex. `pg` avant `cnpg`). Le rapport final liste **toutes** les étapes en
échec et ce qui reste sur le poste.

### 2.2 Logs (`internal/log`, sur `log/slog`)

**Deux sorties, alimentées par les mêmes événements :**

| Sortie | Public | Contenu |
|---|---|---|
| Console | humain | arbre *feature › étape* avec un statut (`ok`, `modifié`, `ignoré`, `échec`) et une durée ; spinner sur un TTY, lignes simples hors TTY (CI, sandbox, pipe) ; couleurs désactivables (`NO_COLOR`) ; `-v` ajoute le debug, `-q` n'affiche que les erreurs |
| Journal JSONL | diagnostic | **toujours au niveau debug**, quel que soit le niveau console : `~/.local/state/bigbox/logs/<horodatage>-<commande>.jsonl` (XDG), les 20 dernières exécutions conservées, champ `run_id` sur chaque ligne ; chaque commande externe avec argv, cwd, durée, code, stdout et stderr ; chaque appel Helm ou Kubernetes avec ressource, verbe et durée |

**Événements normalisés** (attributs slog stables) : `run.start`, `feature.start`, `step.start`,
`cmd.exec`, `cmd.exit`, `step.end` (`status`, `duration`), `feature.end`, `run.end`. Le rendu console
et les tests s'appuient sur ces événements, pas sur du texte.

**Masquage :** un `Redactor` alimenté par `internal/secret` (et par une liste de motifs : `password=`,
`token`, en-têtes `Authorization`) remplace les valeurs sensibles par `«masqué»` dans **toutes** les
sorties, y compris le journal et le debug. Test unitaire dédié : un secret injecté dans argv, stdout et
un message d'erreur n'apparaît dans aucune sortie.

**Récapitulatif de fin d'exécution :**

```
Bigbox apply terminé en 3 min 12 s : 14 ok, 6 modifiés, 2 ignorés, 1 échec
  ✗ sftp › charger les utilisateurs   (voir ci-dessus)
Shell : nouvelles commandes kubectl, helm, psql ; lancez `exec bash`
Journal : ~/.local/state/bigbox/logs/2026-11-06T14-03-12-apply.jsonl
```

**Sorties machine :** `bigbox plan --output json` et `bigbox status --output json` (schéma versionné),
utilisés par les TU et par d'éventuels scripts.

**`bigbox logs`** : `--last` affiche le dernier journal en version lisible, `--run <id>` en choisit un,
`--raw` restitue le JSONL (pour joindre à un rapport de bug).

### 2.3 Messages

- Français, phrases complètes, sujet + verbe : « Installation du client PostgreSQL 17 » plutôt que
  « ⏳ [pg] install ».
- Chaque étape d'un `Plan` porte un libellé utilisateur, réutilisé tel quel par `plan`, la console et
  le journal : une seule source de vérité.
- `bigbox plan` affiche l'écart façon `terraform plan` : `+` à créer, `~` à modifier, `-` à retirer,
  `=` conservé car préexistant (pas à la Bigbox).

---

## 3. Étapes

Le tableau donne la vue d'ensemble ; chaque étape est détaillée ensuite.

| # | Étape | Sortie |
|---|---|---|
| 1 | Socle : CLI, erreurs, logs, Runner, registre, `bigbox.yaml`, graphe, réconciliation, outillage de test | tests unitaires + lint ; `bigbox plan` vide dans la sandbox |
| 2 | Features système : apt, téléchargements, docker, k3s | TU Go `system`, `k3s` |
| 3 | Couche cluster et secrets : client-go, SDK Helm, charts embarqués, secrets, exposition | tests unitaires ; TU `k3s` étendu |
| 4 | Services : cnpg + pg, nats, wiremock, sftp | TU Go `pg`, `full` |
| 5 | Shell et QoL : dotfiles à plat, complétions en cache, outils | TU Go `qol` |
| 6 | Ressources : mesures, arrêt global, mise en veille | mesures consignées |
| 7 | Profil Desktop | TU `desktop` |
| 8 | Bascule : reprise d'un poste Bash, livraison, suppression du Bash | TU `adopt`, `.deb` en sandbox |

### Étape 1 : socle

**Objectif** : un binaire qui sait lire `bigbox.yaml`, construire un plan sur un graphe de features
(vide ou factice), l'appliquer, journaliser et échouer proprement. Aucune feature réelle.

**À créer :**

| Chemin | Contenu |
|---|---|
| `go.mod` | module `github.com/<org>/bigbox`, Go 1.25+ |
| `cmd/bigbox/` | cobra : `version`, `plan`, `apply`, `status`, `logs`, `enable/disable`, `start/stop` ; options globales `-v`, `-q`, `--yes`, `--config`, `--output` |
| `internal/errs/` | type `Error`, `Kind`, codes de sortie, catalogue de remèdes, rendu (section 2.1) |
| `internal/log/` | handler slog double (console + JSONL), événements, `Redactor`, rotation, récapitulatif |
| `internal/run/` | `Runner` (`Run`, `Probe`, `RunPrivileged`) : capture complète, contexte, masquage ; `FakeRunner` scriptable pour les tests ; gestion de sudo (une demande, liste des raisons, keep-alive lié au contexte) |
| `internal/state/` | registre JSON (`~/.config/bigbox/state/owned.json`), écriture atomique (fichier temporaire + `rename`), verrou fichier contre deux exécutions simultanées ; **lecture du format Bash** `~/.config/bigbox/state/owned` (`apt:<paquet>`, `file:<chemin>`, marques libres comme `k3s`) pour l'étape 8 |
| `internal/spec/` | schéma `bigbox.yaml` v1, valeurs par défaut par profil (`desktop`, `wsl`, `minimal`), validation avec positions (`yaml.v3` `Node`), écriture qui préserve les commentaires (pour `enable/disable`) |
| `internal/feature/` | interface `Feature` (`migration.md` 3.3), registre, graphe : tri topologique, cycle, fermeture *avant* (dépendances) et *arrière* (dépendants) |
| `internal/reconcile/` | observe → plan → apply ; ordre de création dans un sens et de suppression dans l'autre ; statut par étape ; best effort à la suppression |
| `internal/env/` | détection du contexte (Ubuntu ≥ 24.04, WSL2, conteneur, Desktop), chemins XDG |
| `Makefile` ou `magefile` | `build` (linux/amd64, arm64), `test`, `lint` |
| `.golangci.yml` | `govet`, `staticcheck`, `errcheck`, `errorlint`, `gosec`, `revive` |

**Outillage sandbox et TU :**
- `tools/sandbox/sandbox.sh run --impl go <args>` : construit le binaire sur l'hôte
  (`GOOS=linux GOARCH=amd64 CGO_ENABLED=0`), le copie dans la VM (`~/bin/bigbox`) et l'exécute.
- `tests/run.sh --impl bash|go` (bash par défaut) ; `--impl go` lit `tests/cases-go/`.
- Ajouts dans `tests/lib/assert.sh` : `assert_exit_code`, `assert_json` (requête jq sur
  `--output json`), `assert_log_contains` (journal JSONL).

**Tests unitaires attendus :** graphe (ordre, cycle, fermetures), validation de `bigbox.yaml` (golden
files d'erreurs), registre (atomicité, lecture du format Bash, verrou), Runner (capture, délai,
annulation, masquage), rendu des erreurs et du récapitulatif (golden files), réconciliation avec des
features factices (idempotence, best effort, Ctrl-C).

**Critères de sortie :** `go test ./...` et `golangci-lint` verts ; dans la sandbox 24.04 et 26.04,
`bigbox version` et `bigbox plan` (profil `minimal`, aucune feature) répondent, sans `sudo`, et
produisent un journal ; une feature factice en échec affiche le rendu de la section 2.1 avec le code 1.

**Risques :** sur-ingénierie du socle avant la première vraie feature. Parade : l'étape 2 commence
dès que le graphe et le Runner sont stables, et le rendu console s'affine ensuite.

### Étape 2 : features système

**Objectif** : parité avec les modules Bash `system`, `core` (allégé) et `docker`, et la partie k3s de
`k8s`.

| Feature | Contenu | Écarts volontaires par rapport au Bash |
|---|---|---|
| `internal/apt` | `Install` (n'enregistre que les paquets absents), `PurgeOwned`, `autoremove --purge` en fin de suppression ; dépôts tiers avec clé `.asc` dans `signed-by` (plus de `gnupg`) ; `apt-get update` seulement si un dépôt a changé | revue des paquets de `migration.md` section 8 : retrait d'`apt-transport-https`, `wget`, `gnupg`, `openssl`, `shellcheck`, `golang-go` de core |
| `internal/download` | URL, version et sha256 épinglés dans le code ; écriture dans un `os.MkdirTemp` ; vérification avant usage | systématique, plus seulement pour k3s |
| `system` | mises à jour et prérequis minimaux | — |
| `docker` | dépôt Docker, paquets, groupe `docker` (possédé), `docker.socket` activé sans `docker.service` au boot (à vérifier) | `docker-ce-rootless-extras` à justifier, sinon retiré |
| `k3s` | installeur épinglé ; `/etc/rancher/k3s/config.yaml` possédé (`secrets-encryption: true`, `write-kubeconfig-mode: "0600"`) écrit **avant** le premier démarrage ; kubeconfig fusionné dans `~/.kube/config`, contexte `bigbox` ; namespace `bigbox` ; `autostart` (`systemctl enable/disable k3s`) ; `kubectl`, `helm`, `kubecolor`, `kubectx` en outils utilisateur (catégorie **O**) | secrets chiffrés au repos ; plus de prérequis helm/kubectl pour la Bigbox elle-même |

**TU Go :** `system` (paquets possédés, préservation de htop/fzf du poste) et `k3s` (k3s actif,
contexte `bigbox`, kubeconfig en 600, `secrets-encrypt status` actif, uninstall complet sans
orphelins). Plus `idempotence` : `apply` deux fois de suite, le second sans aucune étape « modifié ».

**Critères de sortie :** ces trois TU verts sur 24.04 et 26.04 ; parité avec les assertions
équivalentes de `tests/cases/pg.sh` (partie k3s) et `tests/cases/deps.sh`.

**Risques :** un k3s préexistant sur le poste (règle du registre : jamais touché) ; l'activation du
chiffrement des secrets n'est possible simplement qu'à l'installation.

### Étape 3 : couche cluster et secrets

**Décision d'entrée :** SDK Helm v3 ou v4.

| Package | Contenu |
|---|---|
| `internal/kube` | client-go avec contexte `bigbox` forcé ; `Release` (install/upgrade avec attente bornée, uninstall, scale à 0, état) via le SDK Helm ; attente de l'API ; post-renderer Go en dernier recours |
| `charts/` | `charts.lock.yaml` (dépôt, nom, version, digest) ; `go generate` télécharge et vérifie les `.tgz` ; `go:embed` ; values Bigbox = écart minimal avec les values par défaut (`migration.md` 4.2) |
| `internal/secret` | génération `crypto/rand` ; Secret k8s créé avant le déploiement ; restitution via `~/.pgpass` (600), trousseau Secret Service si disponible, sinon `~/.config/bigbox/secrets/` (600) ; `bigbox secret get/rotate` ; alimente le `Redactor` |
| exposition | Ingress Traefik `*.bigbox.localhost`, Services `LoadBalancer` via ServiceLB ; **détection des ports d'hôte occupés pendant `plan`** (erreur `Conflict`, code 4, remède avec `expose.port`) |

**Décision à prendre pendant l'étape :** mécanisme d'écoute limitée au bouclage.

**Tests unitaires :** rendu des values de chaque chart (golden files comparés à `helm template`),
détection de conflit de port, masquage des secrets, digest des charts.

**Critères de sortie :** TU `k3s` étendu (une release de test déployée puis retirée, un Secret créé
puis supprimé) ; aucun secret dans argv ni dans le journal (`assert_log_contains` négatif).

### Étape 4 : services

| Feature | Dépend de | Points clés |
|---|---|---|
| `cnpg` | `k3s` | opérateur 0.29.1, attente du webhook avant tout `Cluster` |
| `pg` | `cnpg` | `Cluster` `bigbox-pg`, Secret `bigbox-pg-auth`, service `bigbox-pg-lb` en 5432, client `postgresql-client-17` (dépôt PGDG) ; `stop` = hibernation CNPG ; supprimé **avant** `cnpg` |
| `nats` | `k3s` | chart officiel 2.15.2, JetStream, 4222/8222 via ServiceLB, `nats` CLI en `.deb` épinglé |
| `wiremock` | `k3s` | chart officiel 1.11.0, `wiremock.bigbox.localhost` |
| `sftp` | `k3s` | SFTPGo 0.48.0, 2022 via ServiceLB, UI `sftp.bigbox.localhost`, admin généré, utilisateur `bigbox` avec `~/.ssh/bigbox.pub` (`SFTPGO_LOADDATA_FROM`) |

Non portés : Hoppscotch (retiré), NUI dans le cluster (remplacé par l'application de bureau, étape 7).

**`start/stop <feature>`** : modifient `state:` dans `bigbox.yaml` puis lancent `apply` ; scale à 0
(Deployments, StatefulSets) ou hibernation (pg).

**TU Go :** `pg` (`enable pg` installe k3s et cnpg, `pg_isready -h localhost -p 5432`, `psql` sans mot
de passe via `~/.pgpass`, `stop pg` hiberne, `disable k3s` retire tout) et `full` (tous les services,
ports natifs, Ingress `*.bigbox.localhost`, **connexion SFTP par clé**, aucun NodePort ouvert).

**Critères de sortie :** parité fonctionnelle avec `tests/cases/full.sh` aux écarts documentés près
(ports, SFTPGo, pas de Hoppscotch) ; durée de l'install complète mesurée et comparée au Bash.

**Risques :** chargement déclaratif des utilisateurs SFTPGo ; poids de CNPG (repli
`groundhog2k/postgres`) ; renommage des PVC NATS (StatefulSet).

### Étape 5 : shell et QoL

- Dotfiles à plat (`migration.md` section 10) : `bigbox.sh`, `env.sh`, `aliases.sh`, `completions.sh`,
  `keybindings.sh`, `prompt.sh` générés en bloc par écriture atomique, `local.sh` jamais touché, une
  seule ligne dans `~/.bashrc`.
- Complétions générées à l'`apply` dans `cache/completions/` (et régénérées à chaque montée de version
  de l'outil).
- Feature `shell` (regroupe starship, catppuccin/vivid, bash-completion) et feature `qol` (liste
  d'outils déclarés : bat, eza, fd, fzf, ripgrep, zoxide, lazygit, htop), chaque outil désactivable.
- Message de fin précis sur le rechargement du shell (section 2.3).

**TU Go :** `qol` (outils présents, `bash -ic` charge la config sans erreur ni lenteur, complétions en
cache, outils préexistants conservés à la suppression, `~/.bashrc` restauré à l'identique).

### Étape 6 : ressources

1. **Mesurer d'abord** dans la sandbox : RAM au repos de k3s seul, puis par service, puis de
   l'opérateur CNPG. Les chiffres sont consignés dans `migration.md` section 6.
2. `bigbox stop` / `bigbox start` globaux (`systemctl stop k3s` puis `k3s-killall.sh`) ;
   `k3s.autostart: false` par défaut.
3. Timer systemd utilisateur de mise en veille des services TCP (pg, NATS) et `bigbox status --notify`.
4. Sablier pour les UI HTTP si les mesures le justifient.

**Critères de sortie :** mesures avant/après publiées ; décision sur le repli PostgreSQL.

### Étape 7 : profil Desktop

**Décision d'entrée :** CopyQ ou GPaste (test sous Wayland dans une VM Ubuntu Desktop).

Ultracopier, presse-papier retenu, Tiling Assistant réglé par `gsettings` (valeur d'origine
sauvegardée dans le registre et restituée), Flameshot, Nerd Font épinglée, application de bureau NUI
(sha256 épinglé par la Bigbox, lanceur `.desktop`). Profil ignoré sous WSL2 et en conteneur.

**Outillage :** image sandbox Ubuntu Desktop (`sandbox.sh --desktop`). **TU :** `desktop`.

### Étape 8 : bascule

1. **`bigbox adopt`** : reprise d'un poste installé par le Bash.
   - Lecture du registre `owned` (format Bash) et conversion vers `owned.json`, sans perdre une seule
     marque.
   - Génération d'un `bigbox.yaml` qui reflète les modules Bash installés.
   - Ancien `~/.config/bigbox/dotfiles/` remplacé par l'arborescence à plat.
   - Releases Bash (`bigbox-pg`, `bigbox-hoppscotch`, `bigbox-nui`…) retirées après confirmation ;
     données pg importées ou remises à zéro (décision ouverte) ; fichier `hoppscotch.key` supprimé.
2. **Livraison :** goreleaser + nfpm (`.deb` et archives amd64/arm64), sommes de contrôle publiées.
3. **Suppression du Bash :** `bigbox` (script), `core/`, `modules/`, `resources/`, `tests/cases/` Bash
   (`tests/cases-go/` devient `tests/cases/`), shellcheck retiré du lint, `--impl` retiré.
4. **Documentation :** réécriture de `README.md` et `CLAUDE.md` (architecture Go, conventions d'erreurs
   et de logs, commandes), mise à jour des skills `ecrire-tu-sandbox` / `jouer-tu-sandbox` et de
   l'agent `bigbox-testeur`.
5. Lanceur Windows en option, selon la décision ouverte.

**TU :** `adopt` (install Bash complète, puis `bigbox adopt`, puis `bigbox apply` sans dérive, puis
uninstall Go : poste identique au poste « Desktop » initial) ; installation du `.deb` en sandbox.

---

## 4. TU pendant la transition

| Élément | Rôle |
|---|---|
| `tests/cases/` (Bash) | figés : référence de parité, joués avec `--impl bash` |
| `tests/cases-go/<nom>.sh` | même format (`TEST_INSTALL_ARGS`, `test_after_install`…), avec des arguments Go (`enable pg --yes`, `disable k3s --yes`) et des assertions adaptées (5432 au lieu de 30001, `*.bigbox.localhost`…) |
| `tests/lib/assert.sh` | partagé ; ajouts `assert_exit_code`, `assert_json`, `assert_log_contains` |
| `tests/run.sh --impl bash\|go` | bash par défaut jusqu'à l'étape 8 ; rapports et baselines séparés par implémentation (`baseline/<impl>-<release>.tsv`) |

**Nouveaux cas propres au Go :**
- `idempotence` : `apply` deux fois, le second sans aucune modification (`plan --detailed-exitcode` = 0) ;
- `erreurs` : panne provoquée (port 5432 occupé avant `enable pg`) ; vérifie le code 4, le message
  « à faire » et la présence de l'événement dans le journal ;
- `interruption` : `SIGINT` pendant un `apply`, puis `apply` qui termine sans dérive.

---

## Annexe : correspondance avec `migration.md`

| Section de `migration.md` | Étape |
|---|---|
| 1. Pourquoi sortir du Shell | 1 (section 1.1 de ce plan) |
| 2. Cible Go, multiplateforme | 1 (build croisé), 8 (`.deb`, lanceur Windows) |
| 3.1–3.2 Arborescence, correspondance Bash → Go | 1 |
| 3.3 Modèle déclaratif | 1 (`spec`, `reconcile`, commandes), 6 (timer `status --notify`) |
| 4.1–4.3, 4.7–4.9 Charts officiels | 3 (embarquement), 4 (services), 8 (données existantes) |
| 4.4 CNPG | 4 |
| 4.5 SFTPGo | 4 |
| 4.6 UI NATS | 7 (application de bureau) |
| 5. Exposition Traefik + ServiceLB | 3 |
| 6. Ressources | 2 (`autostart`), 6 |
| 7. Sécurité et secrets | 2 (chiffrement k3s), 3 (secrets, bouclage), 2.2 de ce plan (masquage) |
| 8. Revue des paquets | 2 (core, docker), 5 (QoL) |
| 9. Profil Desktop | 7 |
| 10. Dotfiles à plat | 5 |
| 11. Plan de migration | remplacé par ce document |
| 12.1 Retrait de Hoppscotch | non porté ; nettoyage des postes existants à l'étape 8 |
| 12.2 Risques | répartis dans les étapes et dans « Décisions encore ouvertes » |
