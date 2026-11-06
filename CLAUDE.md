# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Vue d'ensemble

La Bigbox est un outil 100 % Bash qui installe, désinstalle et pilote un environnement de développement local sur Ubuntu >= 24 (standalone, conteneur ou WSL2). Elle gère Docker, un cluster k3s, des services déployés via Helm (PostgreSQL, NATS, SFTP, Wiremock, Hoppscotch, NUI) et l'outillage du shell. Le projet est entièrement en **français** : commentaires, messages de log, README. Les échanges avec l'utilisateur et tout nouvel ajout doivent aussi être en français.

## Commandes

**Ne jamais lancer `./bigbox` (même `-h`) directement sur le poste de développement.** L'outil lance `sudo -v` dès le démarrage et modifie réellement la machine : apt, systemd, `~/.bashrc`, `~/.kube`, `~/.ssh/bigbox`, `~/.config`. Toute exécution passe par la sandbox QEMU/KVM :

```sh
tools/sandbox/sandbox.sh create [24.04|26.04]   # VM jetable + snapshot "pristine"
tools/sandbox/sandbox.sh run install            # rsync du dépôt puis ./bigbox install dans la VM
tools/sandbox/sandbox.sh run start -m pg,nats   # n'importe quels arguments de la Bigbox
tools/sandbox/sandbox.sh exec '<commande>'      # commande arbitraire dans ~/Bigbox de la VM
tools/sandbox/sandbox.sh reset                  # retour à une Ubuntu vierge
```

Actions de la Bigbox : `install`/`uninstall` (tous les modules, pas de `-m`), `start|stop|upgrade -m mod1,mod2`, options `-d` (debug), `-s` (silencieux), `-h`, `-v`, `-b`.

Il n'y a pas de suite de tests. Lint, à lancer sur l'hôte (doit rester sans avertissement) :

```sh
shellcheck -x bigbox core/*.sh modules/*/*.sh modules/*/dotfiles/*.sh tools/sandbox/*.sh
helm lint modules/<nom>/helm            # dans la VM si helm n'est pas installé sur l'hôte
```

## Architecture

**Déroulé d'une exécution :** `bigbox` définit `SCRIPT_DIR`, source `core/libs.sh` (l'ordre de chargement compte : `constant.sh` doit passer en premier) et appelle `parse_args` (`core/utils.sh`). Il passe ensuite les variables globales de contrôle en `readonly`, puis appelle `menu_show` et `action_execute`. Ce dernier enchaîne `module_load` et `module_run` (`core/module.sh`).

**Actions :** elles sont déclarées dans `resources/action.json` avec trois propriétés :
- `order` (`asc`/`desc`) : sens d'exécution selon la priorité des modules.
- `reboot` : affiche en fin d'action un avertissement pour recharger le shell.
- `modulable` : autorise ou non le filtrage `-m/--module`.

`parse_args` refuse toute action absente de ce fichier.

**Modules :** chaque module vit dans `modules/<nom>/`, un seul module par répertoire.
- `module.json` contient :
  - `name`
  - `priority` : entier unique (une collision arrête `module_load` avec une erreur).
  - `entrypoint` : le fichier `.sh` du module.
  - `actions` : la liste des actions supportées.
- Le point d'entrée n'est sourcé que si le module déclare l'action courante et passe la whitelist. Il doit définir une fonction `<nom>_<action>` pour chaque action déclarée, sinon l'exécution s'arrête.
- Nommage : les fonctions privées prennent le préfixe `_<nom>_`, les constantes du module le préfixe `BB_<NOM>_`. Le répertoire de base se calcule via `$(dirname "${BASH_SOURCE[0]}")`.
- Chaque action doit être idempotente. Dans un `uninstall`, les purges apt se terminent par `|| true`, et on ne touche à k8s que si `kutils_is_api_available` réussit.
- Priorités actuelles : system −100, core 0, docker 100, k8s 200, services 300–340, nui 500, starship 800, qol 1000, catppucin 1001.

**Gestion des erreurs :** `bigbox` tourne en `set -euo pipefail`. `module_run` pose un trap ERR (avec errtrace) qui affiche `❌ [module] action` à la première commande en échec. Ne jamais tester `$?` après coup (code mort avec errexit) : utiliser `if ! cmd`, `cmd || status=$?` ou `|| true` pour un échec toléré.

**Garde contre les attentes :** chaque action de module est surveillée par un watchdog (`_module_watchdog_start` dans `core/module.sh`). Au-delà de `BB_MODULE_TIMEOUT` secondes (900 par défaut, surchargeable par variable d'environnement), il tue les commandes en cours et l'action échoue avec `❌`. Les wrappers kubectl et helm sont aussi bornés (`--request-timeout`, `timeout`). Ne jamais lancer de `kubectl delete` qui attend (`--wait`, actif par défaut) sans `--timeout`, ni de boucle d'attente sans délai maximum.

**Librairies partagées (`core/`) :** une fonction utile à plusieurs modules va ici. Conventions :
- Exécuter les commandes externes via `run_cmd` (sortie capturée hors debug, stderr affiché en cas d'échec) ou via `run_cmd_silently` (pour les tests de condition). Passer par `apt_wrapper install|purge ...` pour apt. Ne pas rediriger la sortie de `run_cmd` (ni utiliser `run_cmd cmd > fichier`) : elle est capturée et le log d'erreur disparaîtrait.
- Logger uniquement via `log_debug/info/warn/error/success` (`core/log.sh`). Les messages portent eux-mêmes leur mise en forme `\n`/`\r\t`.
- Beaucoup de fonctions prennent des options au format `-k=valeur`, parsées par une boucle `for arg in "$@"; case`. Suivre le même style.
- Kubernetes : toujours passer par les fonctions `kutils_*` (`core/kubernetes_utils.sh`). Leurs wrappers kubectl/helm forcent le contexte `bigbox`.
  - `kutils_release_upgrade` : installe ou met à jour une release (sert aussi pour `start`).
  - `kutils_release_stop` : scale down.
  - `kutils_release_uninstall` : supprime la release.

**Modules de services Helm** (pg, nats, sftp, wiremock, hoppscotch, nui) : chacun embarque un chart local dans `modules/<nom>/helm/`. La release s'appelle `bigbox-<nom>` et se déploie dans le namespace `bigbox` du cluster k3s `bigbox`. Chaque service est exposé sur un NodePort à partir de 30000 : pg 30001, nats 30010/30011, nui 30012, sftp 30020. Le stockage utilise la storage class `local-path`.

**Configuration du shell utilisateur :**
- Le module `core` crée `~/.config/bigbox/bigbox.sh` et ajoute une ligne `source` dans `~/.bashrc`. Ce point d'entrée source chaque `*.sh` présent dans `~/.config/bigbox/dotfiles/`.
- Un module fournit sa config shell dans `modules/<nom>/dotfiles/<nom>_{env,alias,completion,keybinding}.sh`. Il la copie avec `cfg_copy_dotfile` à l'install et la retire avec `cfg_delete_dotfile` à l'uninstall.
- Les variables d'environnement partagées passent par `cfg_modify_env`, qui écrit `dotfiles/env.sh`.
- Si un module suivant a besoin d'une modification du PATH dans la même exécution, il faut aussi faire l'`export` dans le processus courant, comme le fait `core` pour Go.

**Sécurité :** les versions des outils téléchargés hors apt (k3s, kubecolor, lazygit, zoxide, starship, nats-cli) et les tags d'images des charts sont épinglés dans des constantes `BB_*_VERSION` ou dans les `values.yaml`. Jamais de `curl | sh`, ni de fichier temporaire à chemin prévisible : télécharger dans un `mktemp -d`. Les secrets passent par des `Secret` k8s et des fichiers en `600`, et tout `rm -rf "$VAR"` est protégé par `${VAR:?}`.

**Constantes globales** (chemins, contexte et namespace k8s, répertoire SSH) : elles sont dans `core/constant.sh`. La version affichée par `-v` vient de `info.json`.
