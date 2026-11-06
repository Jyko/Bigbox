# Bigbox

La Bigbox est une boîte à outils pour les développeurs travaillant sur la base du nouveau socle.
La Bigbox `install` de manière idempotent, reproductible, sans configuration et en quelques secondes, un environnement de développement prêt à l'emploi.
La Bigbox `uninstall` l'environnement de développement en laissant les configurations utilisateurs en l'état.
La Bigbox permet de piloter les outils installés en quelques commandes simples (`start`, `stop`, `upgrade`).

## Pré-requis

Il est nécessaire de disposer d'une distribution Ubuntu (ou un kernel Debian) de version majeure `>= 24`. La dernière LTS et les dernières versions edge sont donc des cibles parfaites.
Cette distribution peut être utilisée sous la forme d'un conteneur, d'une distribution WSL2 ou d'une installation standard standalone.
Il est nécessaire de disposer d'une connexion au réseau publique, de `systemd` d'installé (mais pas obligatoire démarré).
Pour le reste des pré-requis des outils, la Bigbox est autonome et saura installer et configurer seules les différents modules.

## Usage

Une fois le projet récupéré sur la distribution cible via un `git clone`, nous rendons le script `./bigbox` executable :

```sh
chmod +x ./bigbox
```

Nous lançons ensuite l'installation de la Bigbox :

```sh
./bigbox install
```
Nous désinstallons la Bigbox :

```sh
./bigbox uninstall
```

Toutes les actions acceptent une liste de modules avec `-m`. Les dépendances sont résolues automatiquement :

```sh
./bigbox install -m pg          # installe aussi system, core et k8s (k3s)
./bigbox uninstall -m pg        # désinstalle aussi hoppscotch, qui dépend de pg ; k3s est conservé
./bigbox uninstall -m k8s       # désinstalle k3s et tous les services qui en dépendent
```

La désinstallation ne retire que ce que la Bigbox a elle-même installé : un paquet, un Docker, un k3s, un dépôt apt ou un fichier de configuration présents avant elle sont conservés. Elle se termine par un `apt autoremove`.

Nous éteignons les outils dont nous ne nous servons pas pour libérer des ressources :
```sh
./bigbox stop
```

Nous rallumons les outils :
```sh
./bigbox start
```

Si l'on souhaite, nous ajoutons la Bigbox au PATH afin de l'appeler en tant que commande :  
>.bashrc
```sh
export PATH=$PATH:{chemin_vers_la}/bigbox
```

## Sécurité

La Bigbox est pensée pour un poste de développement. Quelques points à connaître :

- **Services exposés sur le réseau** : les services du cluster (PostgreSQL, NATS, SFTP, Wiremock, Hoppscotch, NUI) sont publiés en `NodePort`, donc sur **toutes les interfaces réseau** de la machine, avec des identifiants par défaut (`bigbox`/`bigbox` pour PostgreSQL). Sur une installation standalone connectée à un réseau partagé, ils sont joignables par les autres machines de ce réseau. Restreignez l'accès avec un pare-feu si nécessaire.
- **Groupe `docker`** : l'utilisateur est ajouté au groupe `docker`, ce qui revient à lui donner un accès équivalent à root sur la machine.
- **Désinstallation de Docker** : `./bigbox uninstall` supprime `/var/lib/docker` et `/var/lib/containerd`, donc **toutes** les images, conteneurs et volumes Docker de la machine, y compris ceux qui ne viennent pas de la Bigbox.
- **Versions épinglées** : les outils téléchargés hors des dépôts apt (k3s, kubecolor, lazygit, zoxide, nats-cli) et les images des services ont une version fixée dans leur module. Les mettre à jour se fait en modifiant ces constantes.

## Cheatsheet

### Raccourcis

| Raccourcis | Contexte    | Description                                                                   |
| ---------- | ----------- | ----------------------------------------------------------------------------- |
| `Ctrl + R` | Shell       | Rechercher les dernières commandes passées via la FuzzySearch                 |
| `Ctrl + T` | Shell       | Rechercher par son nom un fichier depuis ce répertoire via la FuzzySearch     |
| `Ctrl + F` | Shell       | Rechercher par son contenu un fichier depuis ce répertoire via la FuzzySearch |
| `Ctrl + E` | FuzzySearch | Ouvrir le fichier selectionné dans l'éditeur configuré (`$EDITOR`)            |
| `Enter`    | FuzzySearch | Ecrire le chemin du fichier selectionné dans le Shell                         |
| `Ctrl + Q` | FuzzySearch | Quitter la FuzzySearch et revenir au Shell                                    |

### Aliases

| Alias     | Commande    | Description                                                         |
| --------- | ----------- | ------------------------------------------------------------------- |
| `ls`      | `eza`       | Remplaçant de `ls`                                                  |
| `lt`      | `eza`       | L'arborescence de fichier sur 3 niveaux de profondeurs              |
| `ll`      | `eza`       | Remplaçant light de `ll`                                            |
| `lll`     | `eza`       | Remplaçant complet de `ll`                                          |
| `bat`     | `batcat`    | `batcat` en plus court                                              |
| `cat`     | `batcat`    | Remplaçant de `cat` (100% compatible)                               |
| `fd`      | `fd-find`   | `fd-find` en plus court                                             |
| `k`       | `kubecolor` | `kubectl` mais avec de la couleur, plus court et 100% compatible    |
| `kubectl` | `kubecolor` | Remplaçcant de `kubectl` mais avec de la couleur et 100% compatible |
| `kn`      | `kubens`    | `kubens` en plus court                                              |
| `kc`      | `kubectx`   | `kubectx` en plus court                                             |
| `h`       | `helm`      | `helm` en plus court                                                |
| `hr`      | `helm`      | `helm repo update` en plus court                                    |
| `hu`      | `helm`      | `helm upgrade --install` en plus court                              |

## Modules

### System

Le module System :
- Vérifie les pré-requis système de l'environnement d'execution de la Bigbox
- Active `systemd` si celui-ci ne l'est pas

### Core

Le module Core :

- Installe les packages suivants :

| Package                                                             | Infos utiles                                                                     |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| [bash-completion](https://github.com/scop/bash-completion)          | Autocomplète les commandes qui disposent d'un script d'autocomplétion enregistré |
| [curl](https://github.com/curl/curl)                                |                                                                                  |
| [golang](https://github.com/golang/go)                              | Le path d'installation des binaires ($HOME/go/bin) est ajouté au PATH            |
| [jq](https://github.com/jqlang/jq)                                  | Manipule du JSON                                                                 |
| [shellcheck](https://github.com/koalaman/shellcheck)                | Linter bash                                                                      |
| [yq](https://github.com/mikefarah/yq)                               | Manipule du YAML (même contrat que jq)                                           |
| [wget](https://manpages.ubuntu.com/manpages/focal/man1/wget.1.html) |                                                                                  |

- Exporte `$HOME/go/bin` dans le `PATH` du `$USER`

### Docker

Le module Docker :
- Installe `docker-ce` et ses dépendances
- Crée la configuration nécessaire pour que le `$USER` puisse utiliser `docker` sans sudoer
- Assure le lancement des services `docker` et `containerd`

### K8S

Le module K8S :
- Installe `k3s` et son cluster Kubernetes `bigbox`
- Installe `kubectl`, `kubens`, `kubectx`, `kubecolor` et les alias et autocomplétions liés
- Crée une configuration unifiée Kubernetes respectueuse des contextes déjà existants
- Crée un namespace `bigbox` dans le cluster `bigbox`

#### TL;DR ?

| Key         | Valeur      |
| ----------- | ----------- |
| `hostname`  | `localhost` |
| `port`      | `6443`      |
| `context`   | `bigbox`    |
| `namespace` | `bigbox`    |

### PG

Le module PG :
- Déploye une stack `bigbox-pg` dans le cluster `bigbox` et le namespace `bigbox`
- Installe les packages suivants :

| Package                                                                              | Infos utiles                                                        |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| [postgresql-client-{version}](https://www.postgresql.org/docs/current/app-psql.html) | Client psql standard de même version majeure que le serveur déployé |

La version majeure actuelle de PostgreSQL utilisée est la 17. Dans le futur, un paramétrage sera possible afin de pouvoir contrôler la version désirée.
La PostgreSQL installée l'est en single-node. Elle est accessible par défaut avec la paire user|pwd `bigbox`. Dans le futur, cette authentification sera déportée vers un secret-manager.
La database par défaut est la `bigbox` et le schéma `public`. Le volume de persistance est limité à `1Gi` pour les phases d'alpha/beta, mais risque de vite passer à `4Gi` pour la release.

#### TL;DR ?

```sh
SPRING_DATASOURCE_URL=jdbc:posgresql://localhost:30001/bigbox
SPRING_DATASOURCE_USERNAME=bigbox
SPRING_DATASOURCE_PASSWORD=bigbox
```

| Key        | Valeur      |
| ---------- | ----------- |
| `hostname` | `localhost` |
| `port`     | `30001`     |
| `username` | `bigbox`    |
| `password` | `bigbox`    |
| `database` | `bigbox`    |

### NATS

Le module NATS :
- Déploye une stack `bigbox-nats` dans le cluster `bigbox` et le namespace `bigbox`
- Installe le binaire go `nats-cli`
- Crée un contexte de connexion pour la `nats-cli` et l'instance `nui` future

Le NATS est déployé en single node en mode JetStream (flag `-js`). Le volume de persistence est limité à `1Gi` se qui devrait être suffisant.
Il est possible que certains messages publiés soient trop volumineux pour la configuration de base du NATS. Nous ajusterons en phase de beta.

#### TL;DR ?

```sh
NATS_SERVER_URLS=nats://localhost:30010
```

| Key               | Valeur      |
| ----------------- | ----------- |
| `hostname`        | `localhost` |
| `port` client     | `30010`     |
| `port` monitoring | `30011`     |

### SFTP

Le module SFTP :
- Crée une pair de clés SSH `$HOME/.ssh/bigbox/bigbox-sftp` sans passphrase
- Déploye une stack `bigbox-sftp` dans le cluster `bigbox` et le namespace `bigbox`
- Configure le volume de persistence pour que le user `bigbox` ai les permissions suffisantes pour écrire et lire dessus

#### TL;DR ?

```sh
sftp -i "$HOME/.ssh/bigbox/bigbox-sftp" bigbox@localhost:30020/upload
```

| Key         | Valeur                          |
| ----------- | ------------------------------- |
| `hostname`  | `localhost`                     |
| `directory` | `upload`                        |
| `port`      | `30020`                         |
| `user`      | `bigbox`                        |
| `ssh key`   | `$HOME/.ssh/bigbox/bigbox-sftp` |

### NUI

Le module NUI :
- Déploye une stack `bigbox-nui` dans le cluster `bigbox` et le namespace `bigbox`
- Importe le contexte du NATS Bigbox

#### TL;DR ?

[NUI en local](http://localhost:30012/)

### QOL

Le module Quality of Life :
- Installe les packages suivants :

| Package                                          | Infos utiles                                              |
| ------------------------------------------------ | --------------------------------------------------------- |
| [bat](https://github.com/sharkdp/bat)            | Remplace `cat`                                            |
| [eza](https://github.com/eza-community/eza)      | Remplace `ls`                                             |
| [fd](https://github.com/sharkdp/fd)              | Remplace `find`                                           |
| [fzf](https://github.com/jqlang/jq)              | Manipule du JSON                                          |
| [fzf](https://github.com/junegunn/fzf)           | Réalise des fuzzy search (recherche full-text à la volée) |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Remplace `grep`                                           |

- Crée des alias et des raccourcis utiles
- Charge des scripts d'autocomplétion pour certains packages installés
- Exporte des variables d'environnement utiles

#### TL;DR ?

Va voir [la cheatsheet](#cheatsheet)


### Catppucin

Le module de la malveillance extrême :
- Colorise **TOUT**

:sdk: Et si t'aimes pas, je m'en fous :sdk:

## Principes et Architecture

La Bigbox en elle mêle n'est qu'un framework permettant le développement de modules d'installation de nouveaux outils. Elle n'a pour vocation que de servir de chargeur et executeur de modules indépendants.

Les modules sont indépendants les uns des autres. Ils doivent disposer de fonction répondant aux actions principales (`install`, `uninstall`, `stop`, `start`). Celle-ci doivent pouvoir être jouer de manière idempotent.

Les modules disposent d'un ordre de lancement, qui doit pouvoir être inversé pour les besoins de certaines actions (`uninstall` et `stop`). Celui-ci ne doit pas entrer en conflit avec celui d'un autre module, sous peine de voir l'un des deux modules ne pas être chargé.

Les scripts situés dans le répertoire `./core` servent de librairies d'outils communes. Nous y retrouvons pêle-mêle des fonctions de chargement de variable d'environnement, de scale down de deployment Kubernetes et autres joyeusetés. Si une fonction doit être partagé entre plusieurs modules, il est conseillé de l'implémenter dans l'une des librairies du `./core`.

Les répertoires situés sous `./modules` sont les hôtes des différents modules indépendants. Chaque répertoire peut contenir un module et un seul. Un module se matérialise par un fichier `*.sh` portant son nom et implémentant les fonctions principales de la Bigbox. L'organisation interne du dossier est libre, si le module nécessite des ressources, nous pouvons les déposer en respectant une hiérarchie qui nous est propre.

Les fichiers situés dans le répertoire `./resources` sont les ressources spécifiques à la Bigbox et son core. Aucune ressource des modules ne doit se trouver dans ce répertoire.

## Développer sur la Bigbox

La Bigbox modifie réellement la machine sur laquelle elle tourne (`.bashrc`, `~/.config`, apt, systemd ...). Pour la tester sans toucher à son poste, le script `tools/sandbox/sandbox.sh` crée une VM Ubuntu jetable avec QEMU/KVM.

Pré-requis sur le poste : `qemu-system-x86_64`, `qemu-img`, un accès à `/dev/kvm`, `ssh`, `rsync`, `python3`, `curl`.

```sh
tools/sandbox/sandbox.sh create                 # VM Ubuntu 24.04, snapshot "pristine"
tools/sandbox/sandbox.sh -r 26.04 create        # une autre VM, en Ubuntu 26.04
tools/sandbox/sandbox.sh run install            # synchronise le dépôt puis lance ./bigbox install dans la VM
tools/sandbox/sandbox.sh -r 26.04 run stop -m pg  # n'importe quels arguments de la Bigbox
tools/sandbox/sandbox.sh ssh                    # shell dans la VM
tools/sandbox/sandbox.sh reset                  # retour à une Ubuntu vierge
tools/sandbox/sandbox.sh status                 # état de toutes les VM
tools/sandbox/sandbox.sh -r 26.04 destroy       # suppression de la VM
```

Chaque release a sa propre VM (`-r`, 24.04 par défaut) : plusieurs peuvent tourner en même temps. Une VM utilise 2 vCPU, 4 Go de RAM et au plus 20 Go de disque (variables `BB_SANDBOX_CPUS`, `BB_SANDBOX_MEMORY`, `BB_SANDBOX_DISK_SIZE`).

Seul le port SSH de la VM est redirigé vers l'hôte (`127.0.0.1:22404` pour 24.04, `22604` pour 26.04) : les services de la Bigbox ne sont joignables que depuis la VM.

### Tests

Les tests se rejouent dans la sandbox avec `tests/run.sh`, qui renvoie un code non nul si un cas échoue :

```sh
tests/run.sh                  # tous les cas, sur Ubuntu 24.04
tests/run.sh -r 24.04,26.04   # tous les cas, sur 24.04 et 26.04 en parallèle
tests/run.sh -r 26.04 pg      # un cas, sur Ubuntu 26.04
```

| Cas | Ce qui est vérifié |
|---|---|
| `deps` | Résolution des dépendances avec `-m` (sans rien installer) |
| `qol` | `install -m catppucin` puis `uninstall -m qol` |
| `pg` | `install -m pg` (k3s installé automatiquement) puis `uninstall -m k8s` |
| `full` | Install complète puis uninstall complète |

Avant chaque scénario, la VM revient à son état vierge et un poste déjà utilisé est simulé (htop, fzf, fichiers personnels) : l'uninstall ne doit rien en retirer. Chaque install et chaque uninstall est limitée à 120 s (300 s pour l'install complète, `-t` pour forcer une autre durée). Les logs sont dans `~/.cache/bigbox-sandbox/logs/`.

Le code est vérifié avec `shellcheck` :

```sh
shellcheck -x bigbox core/*.sh modules/*/*.sh modules/*/dotfiles/*.sh tools/sandbox/*.sh tests/*.sh tests/lib/*.sh tests/cases/*.sh
```