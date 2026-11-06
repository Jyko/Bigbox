# Migration de la Bigbox : du Shell vers Go

> Étude de cadrage, branche `feat/go`, novembre 2026.
> Point de départ : `feat/refacto_bash` (≈ 3 000 lignes de Bash, 13 modules, 6 charts Helm maison).
> Tout ce qui est marqué « validé au rendu » a été vérifié avec `helm template` (Helm 3.20), sans
> déploiement. Rien n'a encore été joué dans la sandbox.

## Décisions

| Date | Décision | Statut |
|---|---|---|
| 2026-11-06 | **Go** comme langage cible, binaire Linux statique, lanceur WSL2 optionnel (sections 1 à 3) | décidé |
| 2026-11-06 | **Plus aucun chart Helm maison** : charts officiels, values par défaut réutilisées au maximum (section 4) | décidé |
| 2026-11-06 | **PostgreSQL via CNPG** (opérateur CloudNativePG + un `Cluster`), module `cnpg` séparé dont dépend `pg` (section 4.4) | décidé |
| 2026-11-06 | **Retrait de Hoppscotch** (section 12.1) | décidé |
| 2026-11-06 | SFTP : chart officiel **SFTPGo** au lieu d'atmoz/sftp (section 4.5) | proposé |
| 2026-11-06 | UI NATS : **application de bureau NUI** hors cluster, NUI dans k3s en repli (section 4.6) | proposé |
| 2026-11-06 | Exposition : **Traefik (HTTP) + ServiceLB (TCP)** de k3s, fin des NodePorts 30000+ (section 5) | proposé |
| 2026-11-06 | **Modèle déclaratif** `bigbox.yaml` + réconciliation à la demande (section 3.3) | proposé |
| 2026-11-06 | Ressources : arrêt complet de k3s à la demande, hibernation par service, Sablier pour les UI HTTP ; KEDA écarté (section 6) | proposé |
| 2026-11-06 | Secrets générés aléatoirement, jamais dans les values ni dans argv, k3s chiffré au repos (section 7) | proposé |
| 2026-11-06 | Revue paquet par paquet avant migration (section 8), **profil Desktop** (section 9), **dotfiles à plat** (section 10) | proposé |

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
| Impératif | chaque action décrit *comment* faire ; aucune vue de l'état attendu ni de la dérive |

## 2. Cible recommandée : Go

### 2.1 Comparatif

| Critère | **Go** | Rust | Python | Ansible |
|---|---|---|---|---|
| Binaire unique, sans runtime | ✅ statique | ✅ | ❌ (PyInstaller fragile) | ❌ |
| SDK Helm utilisable comme librairie | ✅ officiel | ❌ | ❌ | ⚠️ appelle le binaire `helm` |
| Client Kubernetes | ✅ `client-go` (k3s et CNPG sont eux-mêmes en Go) | ⚠️ `kube-rs` | ⚠️ | ⚠️ |
| Embarquer charts / dotfiles / values | ✅ `go:embed` | ✅ | ⚠️ | ❌ |
| Compilation croisée amd64/arm64/windows | ✅ `GOOS`/`GOARCH` | ✅ (plus lourd) | ❌ | ❌ |
| Courbe d'apprentissage | faible | élevée | faible | moyenne |

**L'argument décisif est le SDK Helm** : la Bigbox Go embarque les charts et les déploie elle-même
sur k3s. `helm` et `kubectl` ne sont plus des prérequis de la Bigbox (ils restent des outils proposés
à l'utilisateur). Les types Go de CNPG (`api/v1`) sont aussi utilisables directement avec client-go.

Ansible est l'alternative crédible pour l'idempotence, mais il ne produit pas de livrable autonome et
reste dépendant de Python. Nix / home-manager est la référence du déclaratif pur pour les paquets et
les dotfiles, mais il est trop intrusif sur une Ubuntu existante (store `/nix`, démon, apprentissage)
pour le public visé.

### 2.2 « Multiplateforme » : ce que cela veut dire ici

Ubuntu Desktop et WSL2 font tourner **le même noyau Linux** : la cible réelle n'est pas
Linux + Windows, mais :

1. **`bigbox` (linux/amd64, linux/arm64)** : un binaire statique qui fonctionne tel quel sur
   Ubuntu Desktop, en conteneur et dans WSL2. Livré en archive et en `.deb` (goreleaser + nfpm).
2. **`bigbox.exe` (windows/amd64), optionnel** : un lanceur minimal qui vérifie WSL2 (et propose
   `wsl --install -d Ubuntu-24.04`), copie le binaire Linux dans la distribution et relaie les
   commandes (`bigbox.exe apply` → `wsl -d Ubuntu-24.04 -- bigbox apply`). Il peut aussi installer
   côté Windows les applications de bureau qui ont du sens (UI NATS, section 4.6).

## 3. Architecture cible

### 3.1 Arborescence proposée

```
cmd/bigbox/              point d'entrée (cobra)
cmd/bigbox-win/          lanceur Windows (optionnel)
internal/spec/           schéma de bigbox.yaml (état désiré), validation, valeurs par défaut
internal/reconcile/      boucle observe → plan → apply, rapport de dérive
internal/feature/        interface Feature, registre, graphe de dépendances
internal/state/          registre de propriété (~/.config/bigbox/state/owned, JSON, écriture atomique)
internal/run/            Runner (ex-run_cmd), élévation sudo ciblée, mode --dry-run
internal/apt/            paquets possédés / préexistants
internal/kube/           client-go + SDK Helm, contexte "bigbox" forcé, post-renderers
internal/secret/         génération, stockage, restitution des secrets (section 7)
internal/download/       téléchargements épinglés + vérification sha256
internal/shell/          génération des dotfiles à plat (section 10)
internal/log/            journalisation
features/<nom>/          un package Go par feature (docker, k3s, cnpg, pg, nats, sftp, qol, desktop…)
charts/                  charts tiers épinglés (.tgz) + values Bigbox, embarqués (go:embed)
tests/                   TU sandbox conservés : filet de non-régression de bout en bout
```

### 3.2 Correspondance Bash → Go

| Bash actuel | Go |
|---|---|
| `module.json` + fonctions `<nom>_<action>` | interface `Feature` vérifiée à la compilation |
| `priority` entière unique + `dependencies` | graphe de dépendances ; l'ordre se déduit, les priorités disparaissent |
| `order: asc/desc`, `dependencies: forward/reverse` | parcours du graphe dans un sens ou dans l'autre |
| trap ERR, `❌ [module] action` | `error` retournée et enveloppée avec la feature et l'étape |
| watchdog `BB_MODULE_TIMEOUT`, `timeout` sur kubectl/helm | `context.WithTimeout` propagé jusqu'aux appels réseau et `exec.CommandContext` |
| `run_cmd` / `run_cmd_silently` | `Runner.Run(ctx, cmd…)` : sortie capturée, stderr restitué en cas d'échec, implémentation factice en test |
| `sudo -v` au démarrage | binaire lancé en utilisateur ; élévation uniquement pour apt/systemctl/usermod |
| `curl` + `mktemp -d` + `BB_*_VERSION` | `net/http` + version **et sha256** épinglés, vérifiés avant usage |
| `kutils_release_upgrade/stop/uninstall` | `kube.Release` via le SDK Helm ; arrêt = scale à 0 ou hibernation CNPG |
| `cfg_copy_dotfile` / `cfg_delete_dotfile` | dotfiles régénérés en bloc depuis l'état désiré (section 10) |
| menu `menu.sh` | `huh` / `bubbletea` (édition guidée de `bigbox.yaml`) |

**Ce qui reste un appel externe :** `apt-get`, `systemctl`, `usermod`, `gsettings`, l'installeur
k3s. Ils passent par le `Runner`.

### 3.3 Du modèle impératif au modèle déclaratif

Aujourd'hui l'utilisateur dit *quoi faire* (`install -m pg`, `stop -m nats`). La cible : il décrit
*ce qu'il veut*, et la Bigbox calcule et applique l'écart.

**État désiré** : `~/.config/bigbox/bigbox.yaml`.

```yaml
apiVersion: bigbox.dev/v1
profile: desktop            # desktop | wsl | minimal : préremplit les features
features:
  docker: {}
  k3s:
    autostart: false        # k3s démarré à la demande (section 6)
  pg:
    state: running          # running | stopped | absent
  nats:
    state: stopped
  sftp:
    state: absent
  qol:
    tools: [bat, eza, fd, fzf, ripgrep, zoxide, lazygit]
  desktop:
    clipboard: copyq
    filecopy: ultracopier
    tiling: tiling-assistant
```

**Contrat d'une feature :**

```go
type Feature interface {
    Name() string
    Dependencies() []string
    Observe(ctx context.Context, env *Env) (Observed, error)        // état réel, sans effet de bord
    Plan(desired Spec, observed Observed) []Step                    // écart → étapes ordonnées
    Apply(ctx context.Context, env *Env, steps []Step) error        // idempotent
}
```

**Commandes :**

| Commande | Rôle |
|---|---|
| `bigbox plan` | affiche l'écart entre `bigbox.yaml` et la machine, sans rien toucher (comme `terraform plan`) |
| `bigbox apply` | applique l'écart, dans l'ordre du graphe (création dans un sens, suppression dans l'autre) |
| `bigbox status` | état observé et dérive (ex. paquet retiré à la main, release Helm absente) |
| `bigbox enable/disable <feature>`, `start/stop <feature>` | raccourcis impératifs : modifient `bigbox.yaml` puis lancent `apply` |

**Boucle de réconciliation :** pas de démon permanent. Il consommerait des ressources en continu,
contrairement à l'objectif de la section 6, et Kubernetes réconcilie déjà ce qui tourne dans le
cluster. La réconciliation se fait à la demande (`apply`), plus en option un timer systemd
utilisateur qui lance `bigbox status --notify` pour signaler une dérive sans la corriger.

**Ce qui reste nécessaire :** le registre de propriété. Le déclaratif dit ce qui doit exister ; le
registre dit ce que la Bigbox a le droit de retirer (un paquet préexistant n'est jamais purgé).

**Côté cluster :** les releases Helm restent pilotées par la Bigbox (SDK Helm), car elle a besoin de
contrôler l'attente, l'arrêt et l'hibernation. Le `helm-controller` de k3s (CRD `HelmChart`) donne
une réconciliation gratuite dans le cluster et reste une option à réévaluer une fois le modèle
déclaratif en place.

## 4. Services du cluster : uniquement des charts officiels

### 4.1 Constat

Les 6 charts maison font tous la même chose : un Deployment, un Service NodePort, un PVC
`local-path`, parfois un Secret. **Bitnami est écarté** : depuis le 28 août 2025, Broadcom ne publie
plus gratuitement les images ni les charts OCI Bitnami (images versionnées déplacées dans
`bitnamilegacy`, sans mises à jour).

### 4.2 Principe : réutiliser les values des charts, y compris les ports

- Les values Bigbox ne contiennent **que l'écart** avec les valeurs par défaut du chart : storage
  class, taille de PVC, épinglage des images, secret, nom d'hôte, type de Service.
- **Les ports par défaut des charts sont conservés** (4222/8222 pour NATS, 5432 pour PostgreSQL,
  9021 pour WireMock, 8080 pour l'UI SFTPGo). Le seul écart justifié : le SFTP en 2022, car le port 22
  est pris par le `sshd` de l'hôte.
- Plus aucun `nodePort` : l'exposition passe par Traefik et ServiceLB (section 5), qui s'appuient sur
  les clés natives des charts (`ingress`, `service.type`).
- Points d'extension du chart d'abord (`merge`/`patch` de NATS, `extraObjects`), post-renderer Go en
  dernier recours, jamais de fork.

### 4.3 Bilan par service

| Service | Chart retenu | Version | Exposition |
|---|---|---|---|
| **PostgreSQL** | `cnpg/cloudnative-pg` (opérateur) + `cnpg/cluster` | 0.29.1 (opérateur 1.30.1) + 0.9.0 | TCP 5432 (ServiceLB) |
| **NATS** | `nats/nats` (officiel) | 2.15.2 | TCP 4222, monitoring 8222 (ServiceLB) |
| **SFTP** | `oci://ghcr.io/sftpgo/helm-charts/sftpgo` (officiel) | 0.48.0 (SFTPGo 2.7.5) | SFTP 2022 (ServiceLB), UI `sftp.bigbox.localhost` (Traefik) |
| **WireMock** | `wiremock/wiremock` (officiel) | 1.11.0 | `wiremock.bigbox.localhost` (Traefik) |
| **UI NATS** | hors cluster : application de bureau NUI (section 4.6) | 0.10.0 | — |
| ~~Hoppscotch~~ | retiré | — | — |

**Bilan : zéro chart maison, et plus aucun usage d'`app-template`** dans le scénario nominal. Il reste
le repli pour NUI dans le cluster et pour atmoz/sftp.

### 4.4 PostgreSQL avec CNPG

#### Découpage

| Feature | Contenu | Dépend de |
|---|---|---|
| `cnpg` | opérateur CloudNativePG, 11 CRD, 2 webhooks, namespace `cnpg-system`, déployé **avec attente** (le webhook doit répondre avant la création de tout `Cluster`) | `k3s` |
| `pg` | `Cluster` `bigbox-pg` dans `bigbox`, secret d'authentification, client `postgresql-client-17` sur le poste | `cnpg` |

`pg` est toujours supprimé avant `cnpg`. C'est indispensable : désinstaller l'opérateur retire les CRD
et, en cascade, tout `Cluster` restant et ses données.

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
  # Tag daté et immuable (dernier 17.x au 2026-11-06), à faire suivre comme les autres versions épinglées
  imageName: ghcr.io/cloudnative-pg/postgresql:17.11-202611020810-standard-trixie
  storage: { size: 1Gi, storageClass: local-path }
  enablePDB: false              # un PDB sur une instance unique bloque le drain du nœud
  enableSuperuserAccess: false
  monitoring: { enabled: false }
  initdb:
    database: bigbox
    owner: bigbox
    secret: { name: bigbox-pg-auth }   # Secret kubernetes.io/basic-auth créé par la Bigbox
  roles:                               # garder la création de bases depuis le poste
    - { name: bigbox, ensure: present, login: true, createdb: true, passwordSecret: { name: bigbox-pg-auth } }
  services:
    disabledDefaultServices: ["ro", "r"]
    additional:
      - selectorType: rw
        serviceTemplate:
          metadata: { name: bigbox-pg-lb }
          spec: { type: LoadBalancer }  # port 5432 ajouté par l'opérateur
  resources:
    requests: { cpu: 250m, memory: 256Mi }
    limits: { memory: 512Mi }
backups: { enabled: false }
```

Pour les services additionnels, l'opérateur ajoute le port `postgres` (5432) sans écraser les ports
éventuellement déclarés par l'utilisateur (`WithServicePortNoOverwrite`, correctif de l'issue CNPG
#6389). Il n'y a donc aucun port à écrire.

#### Ce qui change par rapport au PostgreSQL actuel

- **Arrêt = hibernation** : annotation `cnpg.io/hibernation=on` sur le `Cluster` (puis `off`). Les pods
  sont supprimés, les PVC conservés. Un scale à 0 ne fonctionne pas, car les pods sont gérés par
  l'opérateur.
- **Services** : `bigbox-pg-rw` (ClusterIP) et `bigbox-pg-lb` (LoadBalancer, port 5432 sur l'hôte).
- **Droits** : `bigbox` n'est plus superutilisateur (c'était le cas avec `POSTGRES_USER` de l'image
  `postgres`). Il garde `createdb` grâce au rôle géré.
- **Empreinte** : un pod opérateur en plus (128 Mi demandés, 256 Mi au maximum) et des webhooks.
- **Reprise d'une Bigbox existante** : import (`mode: recovery`, `recovery.method: import`) depuis
  l'ancien service avant sa suppression, ou remise à zéro documentée.
- **Repli** si CNPG pèse trop : `groundhog2k/postgres` 1.6.8 (image `postgres` officielle, validé au
  rendu lors de la première passe de l'étude).

### 4.5 SFTP : étude approfondie

| Candidat | Chart | Image | Activité (2026-11-06) | Verdict |
|---|---|---|---|---|
| **atmoz/sftp** | ❌ aucun chart officiel. Seuls existent des manifestes dans une PR non fusionnée et des gists | `atmoz/sftp`, **pas de tags versionnés** (épinglage par digest obligatoire) | 1,9 k★, dernier push 2026-01 | repli via `app-template` |
| **emberstack/docker-sftp** | ✅ `emberstack/sftp` (chart + image du même projet) | `emberstack/sftp`, tag `latest` et `pullPolicy: Always` par défaut, utilisateur `demo/demo` par défaut | 214★, **dernière release v5.1.71 le 2024-07-06** | ❌ projet à l'arrêt |
| **SFTPGo** | ✅ **chart officiel** `oci://ghcr.io/sftpgo/helm-charts/sftpgo` 0.48.0 (repris de sagikazarmark par le projet) | `ghcr.io/drakkan/sftpgo`, tags versionnés (`v2.7.5`) | 12,8 k★, release v2.7.6 le 2026-09-19, chart poussé le 2026-11-06 | ✅ **recommandé** |
| Charts communautaires SFTPGo (TrueCharts, `sagikazarmark/sftpgo`, coderollers) | tiers | idem | remplacés par le chart officiel | ❌ |

**Pourquoi SFTPGo :**
- **Valeurs natives pour tout ce dont on a besoin** : `service.type`, `service.ports.sftp.port`,
  `persistence`, `ui.ingress`, `api.ingress` et même `gatewayApi.httpRoutes` (prêt pour Gateway API,
  section 5).
- **Interface web d'administration** (utilisateurs, clés, quotas, navigation dans les fichiers) : un
  vrai plus pour un environnement de développement.
- **Protocoles activables** : SFTP (actif), FTP et WebDAV (désactivés par défaut), HTTP.
- **Utilisateurs déclaratifs** : l'administrateur par défaut se crée via les variables
  `SFTPGO_DATA_PROVIDER__CREATE_DEFAULT_ADMIN`, `SFTPGO_DEFAULT_ADMIN_USERNAME` et
  `SFTPGO_DEFAULT_ADMIN_PASSWORD`. Les utilisateurs (dont `bigbox` avec la clé publique
  `~/.ssh/bigbox.pub`) se chargent depuis un fichier JSON (`SFTPGO_LOADDATA_FROM`) monté depuis un
  Secret. **Mécanisme à valider en sandbox.**

Values validées au rendu :

```yaml
fullnameOverride: bigbox-sftp
image: { tag: "v2.7.5" }
service:
  type: LoadBalancer
  ports:
    sftp: { port: 2022 }     # seul écart de port : 22 est pris par le sshd de l'hôte
ui:
  ingress:
    enabled: true
    className: traefik
    hosts:
      - host: sftp.bigbox.localhost
        paths: [{ path: /, pathType: Prefix }]
persistence:
  enabled: true
  pvc:
    resources: { requests: { storage: 250Mi } }
    storageClassName: local-path
envFrom:
  - secretRef: { name: bigbox-sftp-auth }   # identifiants admin, générés par la Bigbox
serviceAccount: { create: false }
```

Le rendu produit un Service `LoadBalancer` en 2022, l'Ingress Traefik `sftp.bigbox.localhost` et un
PVC `local-path`. L'image est épinglée sur `ghcr.io/drakkan/sftpgo:v2.7.5`.

**Coût du changement** : le SFTP devient un serveur Go, et non plus OpenSSH (même protocole pour les
clients). Le TU `full` (connexion par clé) reste le juge de paix.

### 4.6 UI pour explorer NATS sans chart personnalisé

| Option | Où | Atouts | Limites | Verdict |
|---|---|---|---|---|
| **Application de bureau NUI** (release officielle v0.10.0 du 2026-10-21 : `linux-amd64-nui-app`, variante `gtk40`, `windows-amd64-nui-app.exe`, macOS) | poste (Desktop) ou Windows (WSL2, via le lanceur) | même NUI que dans le cluster ; **zéro pod** ; se connecte à `nats://localhost:4222` exposé par ServiceLB | pas de fichier de sommes de contrôle publié : la Bigbox épingle elle-même le sha256 à chaque montée de version | ✅ **recommandé** |
| **NUI en conteneur Docker** sur l'hôte (`ghcr.io/nats-nui/nui`, lancé à la demande) | poste, via la feature `docker` | aucun chart ; démarre et s'arrête avec une commande | un service de plus à gérer hors k3s | ✅ alternative pour WSL2 sans lanceur Windows |
| **`nats` CLI** (déjà installé) : `nats stream ls`, `nats sub`, `nats kv`… | terminal | aucun coût | pas d'UI graphique | complément |
| NATS Studio (Tauri, AppImage et `.deb` signés, v0.3.0) | poste | paquets signés | jeune (20★) | à surveiller |
| NatsDash, Easy NATS | poste | binaires Linux | NatsDash inactif depuis 2024-11 | ❌ |
| **NUI dans k3s via `app-template`** | cluster | intégré au cluster | un pod en permanence, chart officiel `nats-nui/nui` expérimental | **repli** |

### 4.7 Autres values validées au rendu

NATS (`nats/nats` 2.15.2), ports par défaut conservés :

```yaml
fullnameOverride: bigbox-nats
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
    spec: { type: LoadBalancer }   # 4222 et 8222 sur l'hôte via ServiceLB
natsBox: { enabled: false }
```

WireMock (`wiremock/wiremock` 1.11.0), port par défaut 9021 conservé derrière Traefik :

```yaml
fullnameOverride: bigbox-wiremock
image: { repository: holomekc/wiremock-gui, tag: "3.13.217-alpine" }
mappingsFromConfigmap: false
responsesFromConfigmap: false
persistence:
  mappings:  { enabled: true, size: 50Mi, storageClassName: local-path }
  responses: { enabled: true, size: 50Mi, storageClassName: local-path }
ingress:
  enabled: true
  className: traefik
  hosts:
    - host: wiremock.bigbox.localhost
      paths: [{ path: /, pathType: Prefix }]
serviceAccount: { create: false }
automountServiceAccountToken: false
```

### 4.8 Comment la Bigbox consomme ces charts

1. **Épinglage** : `dépôt + nom + version + digest sha256` dans `charts/charts.lock.yaml` (ex. SFTPGo
   0.48.0 : `sha256:4bde21dbd935a627d06a4eca7cfae3f61d967ef9f4a0e600027aea1475c60a87`). Les images sont
   épinglées par tag, et idéalement par digest.
2. **Vendoring** : `go generate` télécharge les `.tgz`, vérifie leur digest, et ils sont embarqués
   (`go:embed`). L'installation ne dépend plus de la disponibilité des dépôts Helm.
3. **Secrets hors values** : créés par la Bigbox avant le déploiement et référencés par nom
   (section 7).
4. **Noms stables** : `fullnameOverride: bigbox-<nom>`.

> La bascule des charts **ne dépend pas de Go** : elle peut se faire dès maintenant sur la Bigbox
> Bash, et les TU sandbox existants la valident.

### 4.9 Points d'attention de la bascule

- **Données existantes** : Helm supprime les objets absents du nouveau rendu, **PVC compris**. Il faut
  annoter les PVC actuels avec `helm.sh/resource-policy: keep` avant le premier upgrade, ou documenter
  une remise à zéro. Pour pg (CNPG) et SFTP (SFTPGo), les données ne suivent pas : import ou remise à
  zéro.
- **Deployment → StatefulSet** (NATS) : le nommage des PVC change.
- **Arrêt** : scale à 0 pour les Deployments et StatefulSets, hibernation pour le `Cluster` pg.

## 5. Exposer les services : Traefik et ServiceLB plutôt que les NodePorts

### 5.1 Problèmes des NodePorts actuels

Plage 30000–32767 imposée (`localhost:30001` pour PostgreSQL), ports à retenir, écoute sur **toutes
les interfaces**, et un `nodePort` à maintenir dans chaque chart, ce qui empêche de garder leurs values
par défaut.

### 5.2 Ce que k3s fournit déjà

k3s est installé avec ses composants par défaut (aucun `--disable` dans `modules/k8s/k8s.sh`) :

- **Traefik** (ingress controller) écoute sur 80 et 443. Les Ingress `className: traefik` fonctionnent
  sans rien installer. Le provider Gateway API s'active par un `HelmChartConfig` k3s.
- **ServiceLB** (ex-Klipper) : chaque Service `type: LoadBalancer` est publié sur le **port du Service**
  de l'hôte (DaemonSet `svclb` en `hostPort`). Si le port est déjà pris, le Service reste `Pending`.

### 5.3 Recommandation

| Trafic | Mécanisme | Adresse côté poste | Values utilisées |
|---|---|---|---|
| HTTP (UI WireMock, UI SFTPGo, futures UI) | Ingress Traefik, puis `HTTPRoute` Gateway API | `http://<service>.bigbox.localhost` | `ingress` ou `gatewayApi` natifs des charts |
| TCP (PostgreSQL, NATS, SFTP) | Service `type: LoadBalancer` via ServiceLB | `localhost:5432`, `localhost:4222`, `localhost:2022` | `service.type` natif (ou `merge` pour NATS, `serviceTemplate` pour CNPG) |

- **`*.localhost`** est réservé au bouclage (RFC 6761). Les navigateurs et `systemd-resolved` le
  résolvent vers 127.0.0.1 : pas de `/etc/hosts` à modifier. Sous WSL2, le transfert `localhost` rend
  ces ports joignables depuis Windows (à valider pour le DNS `*.localhost` depuis un navigateur
  Windows).
- **Gateway API** est la cible pérenne (standard Kubernetes, déjà prévu par le chart SFTPGo). Pour le
  TCP, `TCPRoute` est encore dans le canal expérimental et la CRD n'est pas livrée par le chart Traefik
  de k3s : ServiceLB reste plus simple pour le TCP.
- **Conflits de ports** sur un poste Desktop (PostgreSQL local sur 5432, sshd sur 22) : `bigbox plan`
  détecte le port occupé, et `bigbox.yaml` permet de changer le port exposé (ex.
  `pg.expose.port: 15432`).
- **Alternative** : entrypoints TCP Traefik (`IngressRouteTCP` avec `HostSNI(*)`), soit un seul proxy
  mais un entrypoint à déclarer par port. Elle ne s'impose que si ServiceLB devait être désactivé.

## 6. Libérer les ressources inutilisées

k3s, ses composants système (coredns, traefik, local-path, metrics-server, svclb) et les services
occupent de la mémoire en continu, même quand on ne développe pas. **Première étape : mesurer** (RAM
au repos de k3s seul, puis par service) dans la sandbox, pour chiffrer les gains ci-dessous.

| Niveau | Mécanisme | Gain | Coût |
|---|---|---|---|
| 1. Arrêt complet | `bigbox stop` : `systemctl stop k3s` **puis `k3s-killall.sh`** (arrêter le service seul laisse tourner les conteneurs) ; k3s non démarré au boot (`systemctl disable k3s`, `k3s.autostart: false`) ; `bigbox start` relance | maximal | quelques dizaines de secondes au démarrage |
| 2. Par service | `bigbox stop <feature>` : scale à 0 (NATS, WireMock, SFTPGo), hibernation CNPG (pg) ; état mémorisé dans `bigbox.yaml` | proportionnel | manuel |
| 3. Mise en veille automatique des UI HTTP | **Sablier** (v1.19.1, 3,1 k★) : middleware Traefik qui scale à 0 après inactivité et réveille au premier appel, avec une page d'attente | UI WireMock, SFTPGo | un pod Sablier + plugin Traefik ; HTTP uniquement |
| 4. Mise en veille des services TCP | timer systemd utilisateur : si aucune connexion depuis N minutes (`pg_stat_activity`, `/connz` NATS), on hiberne ou on scale à 0 ; réveil manuel ou par `bigbox start` | pg, NATS | pas de réveil transparent à la connexion |
| 5. Réglage de k3s | `--disable metrics-server` si `kubectl top` n'est pas utilisé, requests/limits revues à la baisse | faible à moyen | — |

- **KEDA est écarté** : le scale-to-zero piloté par le trafic passe par l'add-on HTTP, toujours en
  **bêta** et non recommandé en production par ses mainteneurs, et limité au HTTP. Sur un nœud unique,
  l'opérateur KEDA et son intercepteur consommeraient plus que ce qu'ils libèrent. Sablier couvre le
  même besoin HTTP plus simplement.
- **Docker** : le paquet `docker-ce` fournit `docker.socket`. Si `docker.service` n'est pas activé au
  boot, le démon ne démarre qu'au premier appel (à vérifier sur l'installation actuelle).
- **WSL2** : la VM garde la mémoire libérée par Linux. Recommander `autoMemoryReclaim` dans
  `.wslconfig` (via le lanceur Windows ou la documentation).

## 7. Sécurité et gestion des secrets

### 7.1 Existant

| Élément | Situation actuelle | Problème |
|---|---|---|
| Mot de passe PostgreSQL | `bigbox`/`bigbox` en clair dans `values.yaml` | identique sur tous les postes, publié dans le dépôt |
| Clé SFTP | `~/.ssh/bigbox` générée par la Bigbox | bonne pratique, à conserver |
| Valeurs sensibles passées à helm | `--set` / `--set-file` | visibles dans `ps` / `/proc/<pid>/cmdline` le temps de la commande |
| kubeconfig | `K3S_KUBECONFIG_MODE=600`, copie dans `~/.kube` | correct |
| Secrets k8s | Secret k8s, mais non chiffrés au repos dans la base de k3s | lisibles par qui lit la base sur disque |
| Exposition | NodePorts sur toutes les interfaces, NATS sans authentification | services joignables depuis le réseau local |

### 7.2 Cible

1. **Génération** : chaque secret (mot de passe pg, admin SFTPGo, éventuel jeton NATS) est généré
   aléatoirement à l'installation (`crypto/rand`). Aucune valeur par défaut partagée.
2. **Source de vérité** : le `Secret` Kubernetes, créé par la Bigbox via client-go avant le déploiement
   et référencé par les charts (`existingSecret`, `envFrom`, `initdb.secret`). Il n'apparaît ni dans
   les values ni dans argv, car le SDK Helm reçoit les values en mémoire.
3. **Accès depuis le poste** :
   - `bigbox secret get <nom>` pour afficher (et `rotate` pour régénérer, mettre à jour le Secret et
     redémarrer le service concerné) ;
   - PostgreSQL : entrée gérée dans `~/.pgpass` (600). `psql -h localhost -U bigbox` se connecte sans
     mot de passe à taper ni variable d'environnement ;
   - Desktop : copie facultative dans le trousseau Secret Service (GNOME Keyring, via `go-keyring`).
     WSL2 n'a pas de Secret Service par défaut, d'où le repli sur des fichiers 600 sous
     `~/.config/bigbox/secrets/`.
4. **k3s** : configuration dans `/etc/rancher/k3s/config.yaml` (fichier possédé par la Bigbox) avec
   `secrets-encryption: true` **dès l'installation** (k3s ne gère pas simplement l'activation après
   coup) et `write-kubeconfig-mode: "0600"`.
5. **Exposition** : limiter l'écoute au bouclage. Pistes à valider : `hostIP` 127.0.0.1 sur les ports
   Traefik, `--bind-address` de k3s pour l'API, ou des règles nftables posées par la Bigbox.
   L'authentification NATS (utilisateur/mot de passe ou nkey) reste une option de `bigbox.yaml`.
6. **Chaîne d'approvisionnement** : sha256 épinglé pour tout téléchargement (y compris les binaires
   sans somme publiée comme NUI), charts épinglés par digest, images par digest à terme, aucune
   exécution `curl | sh`.
7. **Journalisation** : masquage des valeurs sensibles dans les logs, y compris en `--debug`.
8. **Désinstallation** : secrets k8s, fichiers de secrets, entrée `~/.pgpass` et entrée du trousseau
   retirés. Le registre de propriété dit quoi retirer.

## 8. Revue des paquets avant migration

Chaque paquet doit être revalidé un par un : **à quoi sert-il, pour qui, et est-ce encore utile en
Go ?** Catégories : **D** = dépendance de la Bigbox, **B** = build, **Q** = QoL utilisateur,
**O** = outil de développement de l'utilisateur.

| Paquet | Feature actuelle | Cat. | Usage aujourd'hui | Proposition |
|---|---|---|---|---|
| `apt-transport-https` | core | D | transport HTTPS d'apt | **retirer** : intégré à apt depuis la 1.5, paquet de transition |
| `ca-certificates` | core | D | TLS | garder (déjà présent sur toute Ubuntu) |
| `curl` | core | D | téléchargements du Bash | inutile à la Bigbox Go ; **Q** facultatif |
| `wget` | core | D | doublon de curl | **retirer** |
| `gnupg` | core | D | conversion des clés apt | **retirer** : apt accepte les clés ASCII (`.asc`) dans `signed-by`, comme le fait déjà le module pg |
| `jq`, `yq` | core | D | lecture des JSON de la Bigbox Bash | inutiles à la Bigbox Go ; **Q** facultatifs |
| `openssl` | core | D | génération de la clé Hoppscotch | **retirer** (Hoppscotch retiré, `crypto/rand` en Go) |
| `tar` | core | D | archives lazygit / starship | inutile en Go (`archive/tar`) ; déjà présent |
| `make` | core | B | aucun usage trouvé dans la Bigbox | **à justifier**, sinon option |
| `golang-go` | core | B | `go install` de nats-cli | **retirer de core** : nats-cli publie des `.deb` (v0.5.1) ; Go devient une option **O** |
| `shellcheck` | core | B | lint du code de la Bigbox elle-même | **retirer** : outil des mainteneurs, pas des utilisateurs |
| `bash-completion` | core | Q | complétions | garder dans la feature shell |
| `docker-ce`, `-cli`, `containerd.io`, `buildx`, `compose` | docker | O | Docker | garder |
| `docker-ce-rootless-extras` | docker | O | mode rootless | **à justifier** (Docker n'est pas utilisé en rootless) |
| `kubectl`, `kubectx`, `helm`, `kubecolor` | k8s | O | outils k8s | garder en **O** (plus prérequis de la Bigbox) ; dépôts apt k8s et helm à réévaluer face aux binaires épinglés |
| `postgresql-client-17` | pg | O | `psql` | garder ; dépôt PGDG à conserver |
| `nats` (CLI) | nats | O | client NATS | passer au `.deb` officiel épinglé |
| `bat`, `eza`, `fd-find`, `fzf`, `ripgrep`, `htop` | qol | Q | outils modernes | garder, chacun désactivable dans `bigbox.yaml` |
| `lazygit`, `zoxide` | qol | Q | binaires GitHub | garder (versions épinglées + sha256) |
| `starship` | starship | Q | prompt | garder |
| `vivid` | catppucin | Q | couleurs `LS_COLORS` | garder, regroupé avec le thème |

**Priorités** : les priorités entières disparaissent avec le graphe de dépendances (section 3.2). Les
features `starship` et `catppucin` se regroupent dans une feature `shell` (prompt, thème,
complétions), et `qol` devient une liste d'outils déclarés.

## 9. Profil Desktop

Un profil `desktop` (Ubuntu Desktop uniquement, ignoré sous WSL2 et en conteneur) ajoute des
features orientées confort de bureau. Paquets vérifiés dans les dépôts Ubuntu 26.04 (universe) le
2026-11-06 :

| Besoin | Proposition | Source | Remarques |
|---|---|---|---|
| Copie de fichiers avec file d'attente, pause, reprise (équivalent SuperCopier) | **Ultracopier** 2.2.6 | apt | successeur direct de SuperCopier, même auteur |
| Presse-papier avec historique | **CopyQ** 13.0.0 ou **GPaste** 45.3 (extension GNOME) | apt | CopyQ : scriptable, multi-environnement. GPaste : mieux intégré à GNOME sous Wayland. **Choix à valider sous Wayland** (surveillance du presse-papier restreinte) |
| Tiling | **Ubuntu Tiling Assistant** (livré avec Ubuntu Desktop depuis 23.10, toujours par défaut en 26.04), réglé par `gsettings` ; option **Tiling Shell** (extensions.gnome.org) | préinstallé / extension | ne pas activer les deux ensemble |
| Captures d'écran annotées | **Flameshot** 13.3 | apt | — |
| Police pour le prompt | Nerd Font (téléchargement épinglé) | GitHub | nécessaire aux symboles de starship |
| UI NATS | **application de bureau NUI** (section 4.6) | GitHub | lanceur `.desktop` généré |

**Mise en œuvre** : paquets via apt (registre de propriété), réglages GNOME via `gsettings`/`dconf`
avec sauvegarde de la valeur d'origine pour la restituer à la désinstallation, extensions via
`gnome-extensions`. Chaque élément est une option de `desktop:` dans `bigbox.yaml`. Sous WSL2, le
lanceur Windows pourrait proposer les équivalents Windows (hors périmètre initial).

## 10. Dotfiles : une arborescence à plat

### 10.1 Existant

11 fichiers éclatés par module (`modules/<nom>/dotfiles/<nom>_{env,alias,completion,keybinding}.sh`),
copiés un par un dans `~/.config/bigbox/dotfiles/`. Les complétions sont **régénérées à chaque
ouverture de shell** (`source <(kubectl completion bash)`, idem pour helm et nats), ce qui ralentit
le démarrage du shell.

### 10.2 Cible

```
~/.bashrc                      une seule ligne : source ~/.config/bigbox/bigbox.sh
~/.config/bigbox/
├── bigbox.sh                  point d'entrée unique : source les fichiers ci-dessous dans l'ordre
├── env.sh                     PATH et variables (généré)
├── aliases.sh                 alias (généré)
├── completions.sh             charge les scripts en cache (généré)
├── keybindings.sh             raccourcis readline / fzf (généré)
├── prompt.sh                  starship, thème, LS_COLORS (généré)
├── local.sh                   surcharges de l'utilisateur, jamais modifié par la Bigbox
├── cache/completions/         kubectl.bash, helm.bash, nats.bash… régénérés à l'apply
├── bigbox.yaml                état désiré (section 3.3)
├── state/                     registre de propriété
└── secrets/                   fichiers 600 (repli sans trousseau)
```

- **Regroupement par nature, pas par module** : une feature déclare ses fragments (alias, variables,
  complétions) et la Bigbox régénère **tous** les fichiers en bloc à chaque `apply`, par écriture
  atomique. Chaque fragment porte en commentaire la feature qui l'a produit. Plus de
  `cfg_copy_dotfile` / `cfg_delete_dotfile` : une feature désactivée disparaît simplement du rendu
  suivant.
- **Complétions en cache** : générées une fois à l'apply (et à chaque montée de version de l'outil),
  puis simplement sourcées.
- **Nettoyage trivial** : supprimer `~/.config/bigbox/` et la ligne du `~/.bashrc`.
- **Configurations d'outils** (`starship.toml`, configuration de bat, etc.) : elles restent à leur
  emplacement XDG standard, possédées via le registre, pour que les outils les trouvent sans variable
  supplémentaire.

## 11. Plan de migration

| Étape | Contenu | Validation |
|---|---|---|
| 0a | **Retrait de Hoppscotch** de la Bigbox Bash (section 12.1) | TU `deps`, `full` |
| 0b | **Charts officiels** sur la Bigbox Bash : `cnpg` + `pg`, NATS, WireMock, SFTPGo ; suppression des charts maison | TU `pg`, `full` sur 24.04 et 26.04 |
| 0c | **Exposition** Traefik + ServiceLB, fin des NodePorts ; mesure de la consommation au repos | TU `full` (ports natifs, `*.bigbox.localhost`) |
| 0d | **Revue des paquets** (section 8) appliquée au Bash : retraits sans risque, nats-cli en `.deb` | TU `deps`, `qol` |
| 1 | Squelette Go : CLI, `bigbox.yaml`, `plan`/`apply`/`status`, registre, graphe, Runner ; features encore en Bash appelées par le binaire | TU sandbox inchangés |
| 2 | Features de services en Go (SDK Helm, client-go, charts embarqués, secrets générés, hibernation) | TU + tests unitaires |
| 3 | Features système (docker, k3s avec `config.yaml`, chiffrement des secrets) | TU `deps`, `full` |
| 4 | Shell : dotfiles à plat, complétions en cache, outils QoL | TU `qol` |
| 5 | Ressources : `start`/`stop` global, timer de mise en veille, Sablier pour les UI | mesures avant/après |
| 6 | Profil Desktop (VM sandbox avec Ubuntu Desktop) | TU dédié `desktop` |
| 7 | Livraison goreleaser (`.deb`, archives), suppression du Bash ; lanceur Windows | installation du `.deb` en sandbox, test manuel Windows 11 |

Les TU sandbox (`tests/run.sh`) sont des tests boîte noire, indépendants du langage. Ils restent le
filet de non-régression de bout en bout.

## 12. Annexes

### 12.1 Retrait de Hoppscotch : ce qu'il faudra toucher côté Bash

Recensé le 2026-11-06, à appliquer à l'étape 0a :

- `modules/hoppscotch/` : supprimer le module (script, `module.json`, chart).
- `tests/cases/deps.sh` : 5 assertions de résolution citent hoppscotch.
- `tests/cases/full.sh` : ports 30040–30042.
- `README.md` : exemple `uninstall -m pg` et liste des services exposés.
- `CLAUDE.md` : exemple `uninstall -m pg retire aussi hoppscotch`, liste des modules de services.
- `core/menu.sh` (aide de `-m`) et `core/module.sh` (commentaire sur la résolution `reverse`) :
  nouvel exemple, `uninstall -m cnpg` retire pg.
- `core/utils.sh` : `get_host_ip` n'a plus d'appelant.
- Postes déjà installés : nettoyer la release `bigbox-hoppscotch` et le fichier
  `~/.config/bigbox/hoppscotch/hoppscotch.key`.

### 12.2 Risques et décisions ouvertes

- **Cas limites déjà réglés en Bash** (poste préexistant, uninstall partiel) : c'est le vrai coût de la
  réécriture. Les TU actuels les couvrent.
- **Poids de CNPG** sur les petits postes et sous WSL2 : repli `groundhog2k/postgres`.
- **SFTPGo** : valider le chargement déclaratif des utilisateurs et la connexion par clé.
- **`*.bigbox.localhost` depuis Windows** (WSL2) : valider la résolution dans les navigateurs Windows.
- **Écoute sur le bouclage uniquement** : choisir le mécanisme (section 7.2, point 5).
- **Presse-papier sous Wayland** : CopyQ ou GPaste.
- **Montée majeure PostgreSQL** (17 → 18) avec CNPG ; suivi des tags d'image datés.
- **SDK Helm v3 ou v4** : à trancher au démarrage de l'étape 2.
- **Lanceur Windows** : à confirmer selon le besoin réel.

## Sources

- Charts CloudNativePG : <https://github.com/cloudnative-pg/charts>
- CNPG, hibernation : <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/docs/src/declarative_hibernation.md>
- CNPG, services managés : <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/docs/src/service_management.md>
- CNPG, ports des services additionnels : <https://github.com/cloudnative-pg/cloudnative-pg/blob/main/pkg/specs/services.go>
- Images PostgreSQL CNPG : <https://github.com/cloudnative-pg/postgres-containers>
- Chart SFTPGo officiel : <https://github.com/sftpgo/helm-chart>, SFTPGo : <https://github.com/drakkan/sftpgo>
- atmoz/sftp : <https://github.com/atmoz/sftp> ; EmberStack : <https://github.com/emberstack/docker-sftp>
- NUI (application de bureau) : <https://github.com/nats-nui/nui/releases> ; chart NUI : <https://github.com/nats-nui/k8s>
- NATS Studio : <https://github.com/himanshu-systems/nats-studio> ; NatsDash : <https://github.com/solidpulse/natsdash>
- nats-cli (paquets `.deb`) : <https://github.com/nats-io/natscli/releases>
- Chart NATS officiel : <https://github.com/nats-io/k8s/tree/main/helm/charts/nats>
- Chart WireMock officiel : <https://wiremock.github.io/helm-charts/>
- Traefik et Gateway API : <https://doc.traefik.io/traefik/providers/kubernetes-gateway/>
- k3s, ServiceLB et Traefik : <https://docs.k3s.io/networking/networking-services>
- k3s, chiffrement des secrets : <https://docs.k3s.io/cli/secrets-encrypt>
- Sablier : <https://github.com/sablierapp/sablier>
- KEDA HTTP add-on : <https://github.com/kedacore/http-add-on>
- Ubuntu Tiling Assistant : <https://itsfoss.com/ubuntu-tiling-windows/>
- app-template (bjw-s, repli) : <https://bjw-s-labs.github.io/helm-charts/docs/app-template>
- Changement du catalogue Bitnami : <https://github.com/bitnami/charts/issues/35164>, <https://github.com/bitnami/containers/issues/83267>
