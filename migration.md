# Migration de la Bigbox : du Shell vers Go

> Étude de cadrage, branche `feat/go`, novembre 2026.
> Point de départ : `feat/refacto_bash` (≈ 3 000 lignes de Bash, 13 modules, 6 charts Helm maison).

## 1. Pourquoi sortir du Shell

La Bigbox Bash fonctionne, et la refonte récente l'a rendue robuste (registre de propriété, watchdog,
tests rejouables en sandbox). Mais une bonne partie de cette robustesse est du code qui compense le
langage :

| Limite du Shell | Ce qu'elle coûte aujourd'hui |
|---|---|
| Gestion d'erreurs par `set -e` + trap ERR | règle « ne jamais tester `$?` », `\|\| true` partout, uninstall « best effort » difficile à écrire |
| Pas de types ni de structures | `module.json` / `action.json` relus à l'exécution, vérifications de priorités et de dépendances faites à la main (`_module_index`) |
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
| Client Kubernetes | ✅ `client-go` (k3s est lui-même en Go) | ⚠️ `kube-rs` | ⚠️ | ⚠️ |
| Embarquer charts / dotfiles / values | ✅ `go:embed` | ✅ | ⚠️ | ❌ |
| Compilation croisée amd64/arm64/windows | ✅ `GOOS`/`GOARCH` | ✅ (plus lourd) | ❌ | ❌ |
| Courbe d'apprentissage | faible (Go est déjà installé par le module `core`) | élevée | faible | moyenne |

**L'argument décisif est le SDK Helm** : la Bigbox Go embarque les charts et les déploie elle-même
sur k3s. `helm` et `kubectl` ne sont plus des prérequis de la Bigbox (ils restent installés pour
l'utilisateur, comme outils de confort).

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
modules/<nom>/           un package Go par module (system, core, docker, k8s, pg, nats…)
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
| `kutils_release_upgrade/stop/uninstall` | `kube.Release{…}.Upgrade/Stop/Uninstall(ctx)` via le SDK Helm |
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
| **NATS** | `nats/nats` (officiel, nats-io/k8s) | 2.15.2 | ✅ remplace le chart maison | JetStream, PVC, monitoring natifs. Pas de clé `nodePort` : passe par `service.merge` / `service.patch` (prévu par le chart). Ajoute un config-reloader et un PDB. |
| **PostgreSQL** | `groundhog2k/postgres` | 1.6.8 (PG 18.6 par défaut) | ✅ remplace le chart maison | Image `postgres` **officielle** (on garde `17-alpine`), `service.nodePort`, identifiants via `existingSecret`, sécurité durcie (non-root, rootfs en lecture seule). Peut réutiliser un PVC existant. |
| **WireMock** | `wiremock/wiremock` (officiel) | 1.11.0 | ✅ remplace le chart maison | `service.nodePort`, PVC mappings/fichiers, sondes `/__admin/health`. L'image `holomekc/wiremock-gui` se surcharge. |
| **SFTP** | `bjw-s/app-template` (générique) | 5.3.0 | ✅ | Aucun chart officiel pour `atmoz/sftp`. app-template décrit le déploiement en values seulement (initContainer, secret, PVC, NodePort). |
| **Hoppscotch** | `hoppscotch/hoppscotch-community` (officiel) | 0.2.17 (2026.10.0) | ⚠️ déconseillé → `app-template` | Pensé pour Ingress/LoadBalancer : pas de NodePort ni de `hostAliases`. Images **codées en dur** et non surchargeables (`alpine/kubectl:latest`, `postgres:15-alpine`), clé de chiffrement et URL de base en values en clair (pas d'`existingSecret`), RBAC pour attendre le Job de migration. Contraire aux règles d'épinglage et de secrets du projet. |
| **NUI** | `nats-nui/nui` (officiel) | 0.1.6 (appli `latest`) | ⚠️ déconseillé → `app-template` | Marqué expérimental, pas de `nodePort`, `pullPolicy: Always` et tag `latest` par défaut. Le contexte NATS (ConfigMap `bigbox.json`) passerait par un Secret. |

**Bilan : zéro chart maison.** Trois charts officiels ou communautaires dédiés (NATS, PostgreSQL,
WireMock) et un chart générique, `app-template`, pour les trois services sans chart satisfaisant
(SFTP, Hoppscotch, NUI). Chaque module ne fournit plus qu'un fichier de values.

Alternative écartée pour PostgreSQL : **CloudNativePG** (opérateur + CRD). Excellent en production,
mais surdimensionné pour une instance de développement (opérateur, webhooks, CRD à désinstaller
proprement).

### 4.3 Extraits de values validés au rendu

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

PostgreSQL (`groundhog2k/postgres` 1.6.8), identifiants dans un Secret créé par la Bigbox :

```yaml
image: { tag: "17-alpine" }
service: { type: NodePort, nodePort: 30001 }
settings:
  existingSecret: bigbox-pg-auth
  superuser: { secretKey: user }
  superuserPassword: { secretKey: password }
userDatabase:
  existingSecret: bigbox-pg-auth
  name: { secretKey: database }
  user: { secretKey: user }
  password: { secretKey: password }
storage: { requestedSize: 1Gi, className: local-path }
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

Hoppscotch et NUI suivent le même modèle sur app-template : initContainer `prisma migrate deploy`,
`hostAliases` et trois ports NodePort (30040–30042) pour Hoppscotch ; contexte NATS monté depuis un
Secret et NodePort 30012 pour NUI.

### 4.4 Comment la Bigbox consomme ces charts

1. **Épinglage** : chaque chart est référencé par `dépôt + nom + version + digest sha256` dans un
   fichier unique (ex. `charts/charts.lock.yaml`). Les tags d'images restent épinglés dans les values,
   comme aujourd'hui.
2. **Vendoring** : une cible `go generate` (ou `make charts`) télécharge les `.tgz` et vérifie
   leur digest. En Go, ils sont embarqués via `go:embed` : l'installation ne dépend ni du réseau vers
   les dépôts Helm ni de leur disponibilité future.
3. **Secrets hors values** : la Bigbox crée les `Secret` (`bigbox-pg-auth`, `bigbox-sftp-auth`,
   `bigbox-hoppscotch-auth`) avec client-go avant le déploiement, et les charts les référencent par
   `existingSecret`. Plus de mot de passe ni de clé dans les values.
4. **Écarts résiduels** : si un chart officiel n'expose pas un réglage, on utilise d'abord ses points
   d'extension (`merge`/`patch` de NATS, `extraObjects`…). En dernier recours, le SDK Helm accepte un
   **post-renderer** écrit en Go (patch JSON du manifeste rendu), sans fork du chart.
5. **Noms stables** : `fullnameOverride: bigbox-<nom>` conserve des noms prévisibles pour les
   Services référencés entre modules (Hoppscotch → pg, NUI → NATS).

> Cette bascule des charts **ne dépend pas de Go**. Elle peut se faire dès maintenant sur la Bigbox
> Bash (`helm upgrade --install … --repo … --version …`), ce qui réduit d'autant le périmètre de la
> réécriture et se valide avec les TU sandbox existants.

### 4.5 Points d'attention de la bascule

- **Données existantes** : passer d'un chart à l'autre change les objets de la release. Helm
  supprime les objets qui ne figurent plus dans le nouveau rendu, **PVC compris** (et `local-path`
  détruit le volume). Avant le premier upgrade, annoter les PVC actuels avec
  `helm.sh/resource-policy: keep`. Pour pg, les rattacher ensuite via `storage.persistentVolumeClaimName`.
  Sinon, documenter qu'un `uninstall`/`install` remet les services à zéro, ce qui est acceptable
  pour un poste de développement.
- **Deployment → StatefulSet** (NATS, PostgreSQL) : le nommage des PVC change (`volumeClaimTemplates`) ;
  même traitement que ci-dessus.
- **`kutils_release_stop`** (scale à 0) doit cibler des StatefulSets en plus des Deployments.
- **TU** : les assertions qui vérifient des noms d'objets k8s sont à revoir (aucune trouvée sur les
  noms de Services dans `tests/` à date).
- **Alternative k3s** : le `helm-controller` intégré à k3s (CRD `HelmChart`) sait aussi déployer des
  charts de façon déclarative. Il est écarté, car on perdrait le contrôle direct (attente,
  erreurs, scale down) dont l'action `stop` a besoin.

## 5. Plan de migration

| Étape | Contenu | Validation |
|---|---|---|
| 0 | **Charts tiers sur la Bigbox Bash** (section 4), suppression des 6 charts maison | TU sandbox `pg`, `full` sur 24.04 et 26.04 |
| 1 | Squelette Go : CLI cobra, logs, registre d'état, graphe de modules, watchdog par `context`. Les modules sont encore les scripts Bash, appelés par le binaire | TU sandbox inchangés, verts |
| 2 | Modules de services en Go (SDK Helm + client-go, charts embarqués) : pg, nats, sftp, wiremock, hoppscotch, nui | TU + tests unitaires (Runner factice) |
| 3 | Modules système : system, core, docker, k8s/k3s | TU `deps`, `full` |
| 4 | Outillage shell : qol, starship, catppucin (dotfiles embarqués) | TU `qol` |
| 5 | Livraison : goreleaser (archives + `.deb`, amd64/arm64), suppression du Bash | installation du `.deb` dans la sandbox |
| 6 | Lanceur `bigbox.exe` pour WSL2 | test manuel sur Windows 11 |

Les TU sandbox (`tests/run.sh`) sont des tests boîte noire indépendants du langage : ils restent le
filet de non-régression de bout en bout. Seul le mode d'invocation change (`./bigbox` → binaire
copié dans la VM).

## 6. Risques et décisions ouvertes

- **Cas limites déjà réglés en Bash** (poste préexistant, uninstall partiel, paquets non possédés) :
  c'est le vrai coût de la réécriture. Les TU actuels les couvrent, d'où l'importance de les garder.
- **SDK Helm v3 ou v4** : à trancher au démarrage de l'étape 2 selon la maturité de l'API v4.
- **Lanceur Windows** : utile seulement si des utilisateurs démarrent depuis Windows sans connaître
  WSL. À confirmer avant d'investir.
- **Maintenance des charts tiers** : `nats/nats`, `wiremock/wiremock` et `groundhog2k/postgres` sont
  actifs. `app-template` est très utilisé (homelab, GitOps), mais il sort des versions majeures
  (4 → 5) qui demandent une adaptation des values.

## Sources

- Chart NATS officiel : <https://github.com/nats-io/k8s/tree/main/helm/charts/nats>
- Chart WireMock officiel : <https://wiremock.github.io/helm-charts/>
- Charts Hoppscotch : <https://hoppscotch.github.io/helm-charts>, <https://docs.hoppscotch.io/documentation/self-host/helm-chart-deployment/getting-started>
- Chart NUI : <https://github.com/nats-nui/k8s>
- Chart PostgreSQL groundhog2k : <https://github.com/groundhog2k/helm-charts>
- app-template (bjw-s) : <https://bjw-s-labs.github.io/helm-charts/docs/app-template>
- Changement du catalogue Bitnami : <https://github.com/bitnami/charts/issues/35164>, <https://github.com/bitnami/containers/issues/83267>
