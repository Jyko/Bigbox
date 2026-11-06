# Migration de la Bigbox : du Shell vers Go

> Étude de cadrage, branche `feat/go`, novembre 2026.
> Point de départ : `feat/refacto_bash` (≈ 3 000 lignes de Bash, 13 modules, 6 charts Helm maison).

## Décisions

| Date | Décision | Pourquoi | Impact |
|---|---|---|---|
| 2026-11-06 | **Go** comme langage cible, binaire Linux statique, lanceur WSL2 optionnel | sections 1 à 3 | réécriture par étapes (section 5) |
| 2026-11-06 | **Plus aucun chart Helm maison** : charts officiels ou `app-template` | section 4 | chaque module ne fournit plus qu'un fichier de values |
| 2026-11-06 | **PostgreSQL via CNPG** (opérateur CloudNativePG sur le k3s + un `Cluster`) au lieu d'un PostgreSQL standalone | opérateur de référence de l'écosystème, `Cluster` déclaratif, hibernation, sauvegarde, restauration et import intégrés, même modèle qu'en production | nouveau module `cnpg` dont dépend `pg` (section 4.3) |
| 2026-11-06 | **Retrait de Hoppscotch** des services de la Bigbox | chart officiel inutilisable en l'état ; plus de clé de chiffrement, de base dédiée, d'`hostAliases` ni de `get_host_ip` à maintenir | module supprimé ; nettoyage côté Bash listé en section 5.1 |

## 1. Pourquoi sortir du Shell

La Bigbox Bash fonctionne, et la refonte récente l'a rendue robuste (registre de propriété, watchdog,
tests rejouables en sandbox). Mais une bonne partie de cette robustesse est du code qui compense le
langage :

| Limite du Shell | Ce qu'elle coûte aujourd'hui |
|---|---|
| Gestion d'erreurs par `set -e` + trap ERR | règle « ne jamais tester `$?` », `\|\| true` partout, uninstall « best effort » difficile à écrire |
| Pas de types ni de structures | `module.json` / `action.json` relus à l'exécution par `jq`, vérifications de priorités et de dépendances faites à la main (`_module_index`) |
| Pas d'annulation native | watchdog maison (`_module_watchdog_start`), `timeout` autour de chaque `kubectl`/`helm` |
| Dépendances externes | `helm`, `kubectl`, `curl`, `jq`… doivent être installés *avant* de pouvoir déployer quoi que ce soit |
| Livrable = le dépôt | clonage ou `rsync` d'un arbre de fichiers, pas de version binaire unique |
| Testabilité | seulement des tests boîte noire en VM (lents) ; aucun test unitaire possible sans exécuter réellement `apt`/`systemctl` |
| Séquentiel | les déploiements Helm indépendants (pg, nats, sftp, wiremock) s'enchaînent un par un |

## 2. Cible recommandée : Go

### 2.1 Comparatif

| Critère | **Go** | Rust | Python | Ansible |
|---|---|---|---|---|
| Binaire unique, sans runtime | ✅ statique | ✅ | ❌ (PyInstaller fragile) | ❌ |
| SDK Helm utilisable comme librairie | ✅ officiel | ❌ | ❌ | ⚠️ appelle le binaire `helm` |
| Client Kubernetes | ✅ `client-go` (k3s et CNPG sont eux-mêmes en Go) | ⚠️ `kube-rs` | ⚠️ | ⚠️ |
| Embarquer charts / dotfiles / values | ✅ `go:embed` | ✅ | ⚠️ | ❌ |
| Compilation croisée amd64/arm64/windows | ✅ `GOOS`/`GOARCH` | ✅ (plus lourd) | ❌ | ❌ |
| Courbe d'apprentissage | faible (Go est déjà installé par le module `core`) | élevée | faible | moyenne |

**L'argument décisif est le SDK Helm** : la Bigbox Go embarque les charts et les déploie elle-même
sur k3s. `helm` et `kubectl` ne sont plus des prérequis de la Bigbox (ils restent installés pour
l'utilisateur, comme outils de confort). Les types Go de CNPG (`api/v1`) sont aussi utilisables
directement avec client-go (hibernation, état du `Cluster`).

Ansible est l'alternative crédible pour l'idempotence, mais il ne produit pas de livrable autonome et
reste dépendant de Python sur le poste.

### 2.2 « Multiplateforme » : ce que cela veut dire ici

Ubuntu Desktop et WSL2 font tourner **le même noyau Linux** : la cible réelle n'est pas
Linux + Windows, mais :

1. **`bigbox` (linux/amd64, linux/arm64)** : un binaire statique qui fonctionne tel quel sur
   Ubuntu Desktop, en conteneur et dans WSL2. Livré en archive et en `.deb` (goreleaser + nfpm).
2. **`bigbox.exe` (windows/amd64), optionnel** : un lanceur minimal qui
   - vérifie WSL2 et propose `wsl --install -d Ubuntu-24.04` si besoin ;
   - copie le binaire Linux dans la distribution ;
   - relaie la commande : `bigbox.exe install -m pg` → `wsl -d Ubuntu-24.04 -- bigbox install -m pg`.

Un seul code source, deux cibles de compilation.

## 3. Architecture cible

### 3.1 Arborescence proposée

```
cmd/bigbox/              point d'entrée (cobra)
cmd/bigbox-win/          lanceur Windows (optionnel)
internal/action/         install|uninstall|start|stop|upgrade, sens de résolution des dépendances
internal/module/         interface Module, registre, graphe de dépendances (tri topologique)
internal/state/          registre de propriété (~/.config/bigbox/state/owned, JSON, écriture atomique)
internal/run/            Runner (ex-run_cmd), élévation sudo ciblée, mode --dry-run
internal/apt/            apt_install / apt_purge_owned
internal/kube/           client-go + SDK Helm, contexte "bigbox" forcé, post-renderers
internal/download/       téléchargements épinglés + vérification sha256
internal/dotfiles/       dotfiles embarqués, cfg_copy_dotfile / cfg_modify_env
internal/log/            log_debug/info/warn/error/success
modules/<nom>/           un package Go par module (system, core, docker, k8s, cnpg, pg, nats…)
charts/                  charts tiers épinglés (.tgz) + values Bigbox, embarqués (go:embed)
tests/                   inchangé : les TU sandbox restent le filet de non-régression
```

### 3.2 Correspondance Bash → Go

| Bash actuel | Go |
|---|---|
| `module.json` + fonctions `<nom>_<action>` découvertes au sourcing | interface vérifiée à la compilation (cf. ci-dessous) |
| `priority` entière unique + `dependencies` | graphe de dépendances ; l'ordre se déduit, les priorités disparaissent |
| `order: asc/desc`, `dependencies: forward/reverse` | parcours du graphe dans un sens ou dans l'autre |
| trap ERR, `❌ [module] action` | `error` retournée, enveloppée avec le module et l'action (`fmt.Errorf("%s/%s: %w", …)`) |
| watchdog `BB_MODULE_TIMEOUT`, `timeout` sur kubectl/helm | `context.WithTimeout` propagé jusqu'aux appels réseau et `exec.CommandContext` |
| `run_cmd` / `run_cmd_silently` | `Runner.Run(ctx, cmd…)` : sortie capturée, stderr restitué en cas d'échec, implémentation factice en test |
| `sudo -v` au démarrage | binaire lancé en utilisateur ; élévation uniquement pour apt/systemctl/usermod |
| `curl` + `mktemp -d` + `BB_*_VERSION` | `net/http` + version **et sha256** épinglés, vérifiés avant usage |
| `kutils_release_upgrade/stop/uninstall` | `kube.Release{…}.Upgrade/Stop/Uninstall(ctx)` via le SDK Helm ; `Stop` = hibernation pour pg (section 4.3) |
| `cfg_copy_dotfile` | dotfiles embarqués, rendus avec `text/template` si besoin |
| menu `menu.sh` | `huh` / `bubbletea` |

```go
type Module interface {
    Name() string
    Dependencies() []string
    Install(ctx context.Context, env *Env) error
    Uninstall(ctx context.Context, env *Env) error // doit tolérer une installation partielle
    Start(ctx context.Context, env *Env) error
    Stop(ctx context.Context, env *Env) error
    Upgrade(ctx context.Context, env *Env) error
}
```

Un module qui ne supporte pas une action embarque un type de base qui renvoie `ErrUnsupported`, à la
place du tableau `actions` de `module.json`.

**Ce qui reste un appel externe :** `apt-get`, `systemctl`, `usermod`, l'installeur k3s. Aucune
librairie ne les remplace proprement ; ils passent par le `Runner`.

**Gains secondaires :** démarrage en parallèle des services indépendants dès que le graphe le
permet, `--dry-run`, tests unitaires des modules avec un `Runner` factice et un cluster `envtest`
ou `fake` client-go.

## 4. Ne plus écrire nos propres charts Helm

### 4.1 Constat

Les 6 charts maison font tous la même chose : un Deployment, un Service NodePort, un PVC
`local-path`, parfois un Secret. On maintient donc six copies de templates quasi identiques, plus les
sondes, les labels et les helpers.

**Bitnami est écarté :** depuis le 28 août 2025, Broadcom ne publie plus les images ni les charts
OCI Bitnami gratuitement sur Docker Hub (images versionnées déplacées dans `bitnamilegacy`, sans
mises à jour). Ce n'est plus une base saine.

### 4.2 Étude service par service

Chaque proposition ci-dessous a été **rendue avec `helm template` (Helm 3.20) avec des values
Bigbox** : NodePort, storage class, taille de PVC et image vérifiés dans le manifeste produit.
Rien n'a encore été déployé dans la sandbox.

| Service | Chart retenu | Version | Verdict | Remarques |
|---|---|---|---|---|
| **PostgreSQL** | `cnpg/cloudnative-pg` (opérateur) + `cnpg/cluster` (instance) | 0.29.1 (opérateur 1.30.1) + 0.9.0 | ✅ décidé | Voir section 4.3. Deux modules : `cnpg` et `pg`. |
| **NATS** | `nats/nats` (officiel, nats-io/k8s) | 2.15.2 | ✅ remplace le chart maison | JetStream, PVC, monitoring natifs. Pas de clé `nodePort` : passe par `service.merge` / `service.patch` (prévu par le chart). Ajoute un config-reloader et un PDB. |
| **WireMock** | `wiremock/wiremock` (officiel) | 1.11.0 | ✅ remplace le chart maison | `service.nodePort`, PVC mappings/fichiers, sondes `/__admin/health`. L'image `holomekc/wiremock-gui` se surcharge. |
| **SFTP** | `bjw-s/app-template` (générique) | 5.3.0 | ✅ | Aucun chart officiel pour `atmoz/sftp`. app-template décrit le déploiement en values seulement (initContainer, secret, PVC, NodePort). |
| **NUI** | `bjw-s/app-template` (le chart officiel `nats-nui/nui` 0.1.6 est déconseillé) | 5.3.0 | ✅ | Le chart officiel est marqué expérimental, sans `nodePort`, avec `pullPolicy: Always` et un tag `latest` par défaut. |
| ~~Hoppscotch~~ | — | — | ❌ retiré de la Bigbox | Voir Décisions. |

**Bilan : zéro chart maison.** Trois charts dédiés (CNPG, NATS, WireMock) et le chart générique
`app-template` pour SFTP et NUI. Chaque module ne fournit plus qu'un fichier de values.

Alternative écartée pour PostgreSQL : **`groundhog2k/postgres`** 1.6.8 (image `postgres` officielle,
`service.nodePort`, `existingSecret`, validé au rendu). Plus léger qu'un opérateur, il reste le **plan
de repli** si CNPG s'avère trop lourd sur les postes modestes ou sous WSL2.

### 4.3 PostgreSQL avec CNPG

#### Découpage en modules

| Module | Contenu | Dépend de | Priorité (Bash) |
|---|---|---|---|
| `cnpg` | opérateur CloudNativePG + 11 CRD + 2 webhooks, namespace `cnpg-system`, déployé **avec attente** (le webhook doit répondre avant la création de tout `Cluster`) | `k8s` | 250 |
| `pg` | `Cluster` `bigbox-pg` dans le namespace `bigbox`, secret d'authentification, client `postgresql-client-17` sur le poste | `cnpg` | 300 |

Effet sur la résolution des dépendances : `install -m pg` tire `cnpg` puis `k8s` ;
`uninstall -m cnpg` retire aussi `pg`. L'ordre de désinstallation garantit que le `Cluster` disparaît
avant l'opérateur. C'est indispensable : désinstaller l'opérateur retire les CRD et, en cascade, tout
`Cluster` restant (et ses données).

#### Values validées au rendu

Opérateur (`cnpg/cloudnative-pg` 0.29.1) :

```yaml
replicaCount: 1
image: { tag: "1.30.1" }
crds: { create: true }
resources:
  requests: { cpu: 50m, memory: 128Mi }
  limits: { memory: 256Mi }
```

Instance (`cnpg/cluster` 0.9.0) :

```yaml
fullnameOverride: bigbox-pg
type: postgresql
mode: standalone
cluster:
  instances: 1
  # Tag daté et immuable (dernier 17.x au 2026-11-06), à faire suivre comme les autres BB_*_VERSION
  imageName: ghcr.io/cloudnative-pg/postgresql:17.11-202611020810-standard-trixie
  storage: { size: 1Gi, storageClass: local-path }
  enablePDB: false              # un PDB sur une instance unique bloque le drain du nœud
  enableSuperuserAccess: false
  monitoring: { enabled: false }
  initdb:
    database: bigbox
    owner: bigbox
    secret: { name: bigbox-pg-auth }   # Secret kubernetes.io/basic-auth créé par la Bigbox
  services:
    disabledDefaultServices: ["ro", "r"]
    additional:
      - selectorType: rw
        serviceTemplate:
          metadata: { name: bigbox-pg-nodeport }
          spec:
            type: NodePort
            ports:
              - { name: postgres, port: 5432, targetPort: 5432, nodePort: 30001 }
  resources:
    requests: { cpu: 250m, memory: 256Mi }
    limits: { memory: 512Mi }
backups: { enabled: false }
```

Le manifeste rendu contient bien un `Cluster` à une instance, l'image épinglée, un stockage
`local-path` de 1 Gi, `enablePDB: false`, le bootstrap `initdb` relié au secret, et le service
additionnel NodePort 30001 sur le primaire. Le port nommé `postgres` déclaré dans le template est
**conservé** par l'opérateur : pour les services additionnels, il fusionne les ports sans écraser
ceux de l'utilisateur (`WithServicePortNoOverwrite`, correctif de l'issue CNPG #6389). Le chart
ajoute aussi un Job `helm test` (ping) qui ne tourne qu'avec `helm test`.

#### Ce qui change par rapport au PostgreSQL actuel

- **`stop` / `start` = hibernation.** Les pods sont gérés par l'opérateur (ni Deployment ni
  StatefulSet) : un scale à 0 via `kutils_release_stop` ne fonctionne pas. On pose l'annotation
  `cnpg.io/hibernation=on` sur le `Cluster` (puis `off` au `start`). Les pods sont supprimés, les PVC
  conservés.
- **Noms des Services :** `bigbox-pg-rw` (ClusterIP, primaire) et `bigbox-pg-nodeport` (NodePort
  30001). Aucun autre module ne référence pg depuis le retrait de Hoppscotch.
- **Droits de l'utilisateur `bigbox` :** avec l'image `postgres` actuelle, `POSTGRES_USER` est
  superutilisateur. Avec CNPG, `bigbox` est seulement propriétaire de la base `bigbox`. Pour garder la
  création de bases depuis le poste, on ajoute un rôle géré : `cluster.roles:
  [{ name: bigbox, ensure: present, login: true, createdb: true, passwordSecret: { name: bigbox-pg-auth } }]`.
  L'accès superutilisateur (`postgres`) reste désactivé par défaut (décision ouverte, section 6).
- **Empreinte :** un pod opérateur en plus (128 Mi demandés, 256 Mi au maximum) et des webhooks
  d'admission sur l'API.
- **Reprise d'une Bigbox existante :** le `Cluster` crée son propre PVC. Les données de l'ancien
  PostgreSQL ne sont reprises que par import (`mode: recovery` + `recovery.method: import` depuis
  l'ancien service pg, avant sa suppression). À défaut, on documente une remise à zéro, acceptable pour
  un poste de développement.

### 4.4 Extraits de values validés au rendu (autres services)

NATS (`nats/nats` 2.15.2) :

```yaml
config:
  jetstream:
    enabled: true
    fileStore:
      pvc: { size: 1Gi, storageClassName: local-path }
  monitor: { enabled: true }
service:
  ports:
    monitor: { enabled: true }
    leafnodes: { enabled: false }
    websocket: { enabled: false }
    mqtt: { enabled: false }
  merge:
    spec: { type: NodePort }
  patch:
    - { op: add, path: /spec/ports/0/nodePort, value: 30010 }   # client 4222
    - { op: add, path: /spec/ports/1/nodePort, value: 30011 }   # monitoring 8222
natsBox: { enabled: false }
```

WireMock (`wiremock/wiremock` 1.11.0) :

```yaml
image: { repository: holomekc/wiremock-gui, tag: "3.13.217-alpine" }
service: { type: NodePort, internalPort: 8080, externalPort: 8080, nodePort: 30030 }
args: ["--port=8080", "--max-request-journal=1000", "--local-response-templating", "--root-dir=/home/wiremock/storage"]
mappingsFromConfigmap: false
responsesFromConfigmap: false
persistence:
  mappings:  { enabled: true, size: 50Mi, storageClassName: local-path }
  responses: { enabled: true, size: 50Mi, storageClassName: local-path }
serviceAccount: { create: false }
automountServiceAccountToken: false
```

SFTP (`bjw-s/app-template` 5.3.0) :

```yaml
controllers:
  main:
    initContainers:
      chown:
        image: { repository: alpine, tag: "3.24" }
        command: ["sh", "-c", "chown -R 1001:1001 /home/bigbox/upload"]
    containers:
      main:
        image:
          repository: atmoz/sftp
          tag: "latest@sha256:0960390462a4441dbb63698d7c185b76a41ffcee7b78ff4adf275f3e66f9c475"
        args: ["bigbox::1001"]
service:
  main:
    controller: main
    type: NodePort
    ports:
      sftp: { port: 2222, targetPort: 22, nodePort: 30020 }
persistence:
  data:
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 250Mi
    storageClass: local-path
    globalMounts: [{ path: /home/bigbox/upload }]
  client-key:
    type: secret
    name: bigbox-sftp-auth
    globalMounts: [{ path: /home/bigbox/.ssh/keys/bigbox.pub, subPath: clientPublicKey, readOnly: true }]
```

NUI suit le même modèle sur app-template : image `ghcr.io/nats-nui/nui` épinglée, contexte NATS
(`bigbox.json`, URL `nats://bigbox-nats:4222`) monté depuis un Secret, PVC de 250 Mi et NodePort 30012.

### 4.5 Comment la Bigbox consomme ces charts

1. **Épinglage** : chaque chart est référencé par `dépôt + nom + version + digest sha256` dans un
   fichier unique (ex. `charts/charts.lock.yaml`). Les tags d'images restent épinglés dans les values,
   comme aujourd'hui.
2. **Vendoring** : une cible `go generate` (ou `make charts`) télécharge les `.tgz` et vérifie
   leur digest. En Go, ils sont embarqués via `go:embed` : l'installation ne dépend ni du réseau vers
   les dépôts Helm ni de leur disponibilité future.
3. **Secrets hors values** : la Bigbox crée les `Secret` avec client-go avant le déploiement, et les
   charts les référencent par nom : `bigbox-pg-auth` (type `kubernetes.io/basic-auth`, clés
   `username`/`password`) et `bigbox-sftp-auth` (clé publique du client). Plus de mot de passe ni de
   clé dans les values.
4. **Écarts résiduels** : si un chart officiel n'expose pas un réglage, on utilise d'abord ses points
   d'extension (`merge`/`patch` de NATS, `extraObjects`…). En dernier recours, le SDK Helm accepte un
   **post-renderer** écrit en Go (patch JSON du manifeste rendu), sans fork du chart.
5. **Noms stables** : `fullnameOverride: bigbox-<nom>` conserve des noms prévisibles pour les
   Services référencés entre modules (NUI → NATS).

> Cette bascule des charts **ne dépend pas de Go**. Elle peut se faire dès maintenant sur la Bigbox
> Bash (`helm upgrade --install … --repo … --version …`), ce qui réduit d'autant le périmètre de la
> réécriture et se valide avec les TU sandbox existants.

### 4.6 Points d'attention de la bascule

- **Données existantes** : passer d'un chart à l'autre change les objets de la release. Helm
  supprime les objets qui ne figurent plus dans le nouveau rendu, **PVC compris** (et `local-path`
  détruit le volume). Pour NATS, WireMock, SFTP et NUI, annoter les PVC actuels avec
  `helm.sh/resource-policy: keep` avant le premier upgrade. Pour pg, la bascule vers CNPG crée de
  toute façon un nouveau PVC géré par l'opérateur : import ou remise à zéro (section 4.3).
- **Deployment → StatefulSet** (NATS) : le nommage des PVC change (`volumeClaimTemplates`) ; même
  traitement que ci-dessus.
- **`stop`** : scale à 0 conservé pour les Deployments et StatefulSets (`kutils_release_stop` doit
  aussi cibler les StatefulSets), **hibernation** pour le `Cluster` pg.
- **TU** : les assertions qui vérifient des noms d'objets k8s sont à revoir (aucune trouvée sur les
  noms de Services dans `tests/` à date). Le TU `pg` doit couvrir l'hibernation et la reprise.
- **Alternative k3s** : le `helm-controller` intégré à k3s (CRD `HelmChart`) sait aussi déployer des
  charts de façon déclarative. Il est écarté, car on perdrait le contrôle direct (attente,
  erreurs, hibernation) dont les actions `start`/`stop` ont besoin.

## 5. Plan de migration

| Étape | Contenu | Validation |
|---|---|---|
| 0a | **Retrait de Hoppscotch** de la Bigbox Bash (section 5.1) | TU `deps`, `full` sur 24.04 et 26.04 |
| 0b | **Charts tiers sur la Bigbox Bash** (section 4) : nouveau module `cnpg`, `pg` sur `cnpg/cluster`, suppression des charts maison restants | TU `pg` (avec hibernation), `full` sur 24.04 et 26.04 |
| 1 | Squelette Go : CLI cobra, logs, registre d'état, graphe de modules, watchdog par `context`. Les modules sont encore les scripts Bash, appelés par le binaire | TU sandbox inchangés, verts |
| 2 | Modules de services en Go (SDK Helm + client-go, charts embarqués) : cnpg, pg, nats, sftp, wiremock, nui | TU + tests unitaires (Runner factice) |
| 3 | Modules système : system, core, docker, k8s/k3s | TU `deps`, `full` |
| 4 | Outillage shell : qol, starship, catppucin (dotfiles embarqués) | TU `qol` |
| 5 | Livraison : goreleaser (archives + `.deb`, amd64/arm64), suppression du Bash | installation du `.deb` dans la sandbox |
| 6 | Lanceur `bigbox.exe` pour WSL2 | test manuel sur Windows 11 |

Les TU sandbox (`tests/run.sh`) sont des tests boîte noire indépendants du langage : ils restent le
filet de non-régression de bout en bout. Seul le mode d'invocation change (`./bigbox` → binaire
copié dans la VM).

### 5.1 Retrait de Hoppscotch : ce qu'il faudra toucher côté Bash

Recensé le 2026-11-06, à appliquer à l'étape 0a :

- `modules/hoppscotch/` : supprimer le module (script, `module.json`, chart).
- `tests/cases/deps.sh` : 5 assertions de résolution citent hoppscotch (`install`/`start -m hoppscotch`,
  `uninstall -m pg`, `uninstall`/`stop -m k8s`).
- `tests/cases/full.sh` : ports NodePort 30040–30042 à retirer.
- `README.md` : exemple `uninstall -m pg` (« désinstalle aussi hoppscotch ») et liste des services
  exposés.
- `CLAUDE.md` : exemple `uninstall -m pg retire aussi hoppscotch`, liste des modules de services.
- `core/menu.sh` (aide de `-m`) et `core/module.sh` (commentaire sur la résolution `reverse`) :
  remplacer l'exemple. Après l'étape 0b, `uninstall -m cnpg` retire pg en devient un bon.
- `core/utils.sh` : `get_host_ip` n'a plus d'appelant, à supprimer.
- Postes déjà installés : la désinstallation doit encore nettoyer une release `bigbox-hoppscotch`
  restante et le fichier `~/.config/bigbox/hoppscotch/hoppscotch.key` (par exemple dans
  l'uninstall de `k8s` et de `core`, conditionné au registre de propriété).

## 6. Risques et décisions ouvertes

- **Cas limites déjà réglés en Bash** (poste préexistant, uninstall partiel, paquets non possédés) :
  c'est le vrai coût de la réécriture. Les TU actuels les couvrent, d'où l'importance de les garder.
- **Poids de CNPG** sur des postes modestes ou sous WSL2 (opérateur, webhooks, 11 CRD). Repli prévu :
  `groundhog2k/postgres` (section 4.2).
- **Montées de version majeures de PostgreSQL** avec CNPG (17 → 18) : vérifier ce que l'opérateur
  1.30 permet par simple changement d'`imageName`, sinon passer par un import.
- **Épinglage de l'image `ghcr.io/cloudnative-pg/postgresql`** : suivre les tags datés (immuables)
  et les faire évoluer comme les autres `BB_*_VERSION`.
- **Accès superutilisateur PostgreSQL** : désactivé par défaut (rôle `bigbox` avec `createdb`). Le
  réactiver (`enableSuperuserAccess` + secret dédié) si des usages le demandent.
- **SDK Helm v3 ou v4** : à trancher au démarrage de l'étape 2 selon la maturité de l'API v4.
- **Lanceur Windows** : utile seulement si des utilisateurs démarrent depuis Windows sans connaître
  WSL. À confirmer avant d'investir.
- **Maintenance des charts tiers** : `cnpg`, `nats/nats` et `wiremock/wiremock` sont actifs.
  `app-template` est très utilisé (homelab, GitOps), mais il sort des versions majeures (4 → 5) qui
  demandent une adaptation des values.

## Sources

- Charts CloudNativePG : <https://github.com/cloudnative-pg/charts>
- CNPG, hibernation déclarative : <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/docs/src/declarative_hibernation.md>
- CNPG, services managés : <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/docs/src/service_management.md>
- CNPG, ports des services additionnels (`WithServicePortNoOverwrite`) : <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/pkg/specs/services.go>
- Images PostgreSQL CNPG : <https://github.com/cloudnative-pg/postgres-containers>
- Chart NATS officiel : <https://github.com/nats-io/k8s/tree/main/helm/charts/nats>
- Chart WireMock officiel : <https://wiremock.github.io/helm-charts/>
- Chart NUI : <https://github.com/nats-nui/k8s>
- Chart PostgreSQL groundhog2k (repli) : <https://github.com/groundhog2k/helm-charts>
- app-template (bjw-s) : <https://bjw-s-labs.github.io/helm-charts/docs/app-template>
- Changement du catalogue Bitnami : <https://github.com/bitnami/charts/issues/35164>, <https://github.com/bitnami/containers/issues/83267>
