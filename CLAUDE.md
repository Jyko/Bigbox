# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Vue d'ensemble

La Bigbox est un outil 100 % Bash qui installe, désinstalle et pilote un environnement de développement local sur Ubuntu >= 24 (standalone, conteneur ou WSL2). Elle gère Docker, un cluster k3s, des services déployés via Helm (PostgreSQL, NATS, SFTP, Wiremock, Hoppscotch, NUI) et l'outillage du shell. Le projet est entièrement en **français** : commentaires, messages de log, README. Les échanges avec l'utilisateur et tout nouvel ajout doivent aussi être en français.

## Commandes

Il n'y a ni étape de build ni suite de tests. On valide une modification avec le linter, puis en lançant l'outil sur une vraie machine Ubuntu (ou une machine jetable).

```sh
./bigbox install                        # tous les modules, priorité croissante (pas de -m)
./bigbox uninstall                      # tous les modules, priorité décroissante (pas de -m)
./bigbox start|stop|upgrade -m pg,nats  # seulement les modules listés
./bigbox install -d                     # debug : affiche la sortie de toutes les commandes
./bigbox -h | -v | -b                   # aide / version / bannière

shellcheck bigbox core/*.sh modules/*/*.sh modules/*/dotfiles/*.sh   # lint (installé par le module core)
helm lint modules/<nom>/helm            # vérifier le chart d'un module
```

`./bigbox` lance `sudo -v` dès le démarrage et modifie réellement la machine : apt, systemd, `~/.bashrc`, `~/.kube`, `~/.ssh/bigbox`, `~/.config/bigbox`. Ne pas l'exécuter à la légère.

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
  - `priority` : entier unique. Deux modules de même priorité s'écrasent dans le tableau associatif `MODULES`, et l'un des deux disparaît sans erreur.
  - `entrypoint` : le fichier `.sh` du module.
  - `actions` : la liste des actions supportées.
- Le point d'entrée n'est sourcé que si le module déclare l'action courante et passe la whitelist. Il doit définir une fonction `<nom>_<action>` pour chaque action déclarée, sinon l'exécution s'arrête.
- Nommage : les fonctions privées prennent le préfixe `_<nom>_`, les constantes du module le préfixe `BB_<NOM>_`. Le répertoire de base se calcule via `$(dirname "${BASH_SOURCE[0]}")`.
- Chaque action doit être idempotente. Dans un `uninstall`, les purges apt se terminent par `|| true`, et on ne touche à k8s que si `kutils_is_api_available` réussit.
- Priorités actuelles : system −100, core 0, docker 100, k8s 200, services 300–340, nui 500, starship 800, qol 1000, catppucin 1001.

**Librairies partagées (`core/`) :** une fonction utile à plusieurs modules va ici. Conventions :
- Exécuter les commandes externes via `run_cmd` (sortie capturée hors debug, stderr affiché en cas d'échec) ou via `run_cmd_silently` (pour les tests de condition). Passer par `apt_wrapper install|purge ...` pour apt.
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

**Constantes globales** (chemins, contexte et namespace k8s, répertoire SSH) : elles sont dans `core/constant.sh`. La version affichée par `-v` vient de `info.json`.

## Incohérences connues

- L'aide affiche `-q|--quiet`, mais `parse_args` n'accepte que `-s|--silent`.
- `modules/system/module.json` déclare une action `info` absente de `resources/action.json`.
- Le FIXME de `_core_bigbox_configuration_uninstall` semble obsolète. Il dit que la config des modules est supprimée avant qu'ils aient pu faire leur nettoyage. Or `uninstall` s'exécute maintenant en ordre décroissant, donc `core` (priorité 0) passe après tous les autres modules qui ont une action d'uninstall.
