---
name: ecrire-tu-sandbox
description: Écrire ou modifier un test (TU) de la Bigbox dans tests/cases/, joué dans la sandbox QEMU/KVM. À utiliser pour ajouter un scénario install/uninstall d'un module, couvrir un bug corrigé par un test de non-régression, ou ajuster les assertions d'un cas existant.
---

# Écrire un TU de la Bigbox (sandbox)

Un TU est un fichier `tests/cases/<nom>.sh` joué par `tests/run.sh` dans une VM jetable. **Ne jamais lancer `./bigbox` ni un cas de test sur l'hôte** : la Bigbox modifie réellement la machine.

## 1. Choisir le type de cas

| Type | Variables | Fonctions | Exemple |
|---|---|---|---|
| Scénario | `TEST_INSTALL_ARGS`, `TEST_UNINSTALL_ARGS` | `test_after_install`, `test_after_uninstall` | `qol.sh`, `pg.sh`, `full.sh` |
| Assertions seules (rien n'est installé) | `TEST_RESET=false` si la VM n'est pas modifiée | `test_run` | `deps.sh` |

Variables communes : `TEST_DESCRIPTION` (une ligne, reprise dans le rapport), et `TEST_ACTION_TIMEOUT` (défaut 120 s, à ne relever que si une mesure le justifie, avec un commentaire qui la cite, comme `full.sh` à 300 s).

Déroulé d'un scénario par le lanceur : reset au snapshot `pristine` → `tests/lib/prepare_desktop.sh` (htop, fzf, contexte NATS, base zoxide et config bat personnels) → install → `test_after_install` → uninstall (jouée même si l'install a échoué) → `test_after_uninstall`.

## 2. Modèle

```bash
# shellcheck shell=bash
# shellcheck disable=SC2034 # Les variables TEST_* et BB_TEST_* sont lues par tests/run.sh et les fonctions du cas
# <Ce que le cas couvre et pourquoi>
TEST_DESCRIPTION="install -m <module>, puis uninstall -m <module>"
TEST_INSTALL_ARGS="install -m <module>"
TEST_UNINSTALL_ARGS="uninstall -m <module>"

BB_TEST_<NOM>_PACKAGES=(paquet1 paquet2)

test_after_install() {
    section "Install"
    assert_pkg_installed "${BB_TEST_<NOM>_PACKAGES[@]}"
    assert "service répond" "<commande bornée>"
}

test_after_uninstall() {
    section "Uninstall"
    assert_pkg_absent "${BB_TEST_<NOM>_PACKAGES[@]}"
    assert_desktop_preserved     # toujours : l'uninstall ne doit rien retirer au poste existant
    section "Orphelins"
    assert_no_orphans            # toujours : apt autoremove n'a plus rien à faire
}
```

## 3. Assertions disponibles (`tests/lib/assert.sh`)

`assert "<libellé>" "<commande>"` est la primitive. La commande est une **chaîne** évaluée par `bash -c` dans la VM, bornée à 10 s. `timeout` n'exécute pas les fonctions shell, d'où la chaîne.

Raccourcis : `assert_pkg_installed|assert_pkg_absent <paquets>`, `assert_exists|assert_absent <chemins>`, `assert_command <cmds>`, `assert_no_process <noms exacts>`, `assert_port_open|assert_port_closed <ports>`, `assert_no_orphans`, `assert_desktop_preserved`, `section "<titre>"`.

Le libellé devient le nom du testcase JUnit et la clé de la détection de régression : il doit être **stable** (pas de date, de PID, de durée) et unique dans sa phase.

## 4. Pièges connus (tous rencontrés)

- **Le fichier du cas s'exécute dans la VM** : `$HOME` vaut `/home/bigbox`. N'écrire aucun chemin de l'hôte (`/home/<vous>`). Un `assert_absent` sur un mauvais chemin passe toujours : c'est un faux positif silencieux.
- **Quoting** : dans `assert "..." "..."`, `$HOME` est développé à la définition (dans la VM, donc correct). Ce qui doit être évalué par le `bash -c` s'échappe : `"[[ \$(stat -L -c %a '$HOME/.kube/config') == 600 ]]"`.
- **Liens symboliques** : `~/.kube/config` est un lien vers `unified-configs.yaml`. `stat` sans `-L` renvoie 777.
- **PATH** : les assertions tournent dans un shell de login sans la config Bigbox. `~/go/bin/nats` n'est pas dans le PATH : tester le chemin complet.
- **Différences entre releases** : gcc-13 (24.04) contre gcc-15 (26.04), golang-1.22 contre 1.26, starship en binaire GitHub avant 25.04 et en paquet apt ensuite. Ne pas asserter un nom de paquet versionné, ni un mode d'installation propre à une release.
- **Le paquet crée la ressource** : un `getent group docker` après l'install ne prouve pas que la Bigbox a créé le groupe. Asserter l'effet attendu côté utilisateur, et à l'uninstall l'absence de ce que la Bigbox a créé.
- **Pas d'attente** : jamais de boucle `until` ni de `sleep`. Un service doit répondre au moment de l'assertion (les releases Helm sont attendues par `--wait`). Utiliser des sondes à délai court : `pg_isready -t 5`, `_port_open` (2 s).
- **Couverture de l'uninstall** : vérifier aussi les fichiers système (dépôts apt, clés, binaires dans `/usr/local/bin`), les processus et les ports, pas seulement les paquets.

## 5. Valider le TU

1. Lint (hôte) : `shellcheck -x tests/*.sh tests/lib/*.sh tests/cases/*.sh`
2. Jouer le cas seul sur une release (skill `jouer-tu-sandbox`) : `timeout 900 tests/run.sh -r 24.04 <nom>`
3. **Vérifier que le test sait échouer** : inverser temporairement une assertion (`assert_pkg_absent` à la place de `assert_pkg_installed`, par exemple) et constater le ❌ dans `report.md`, puis rétablir. Un test qui ne peut pas échouer ne protège de rien.
4. Jouer le cas sur toutes les releases supportées : `tests/run.sh -r 24.04,26.04 <nom>`.
5. Mettre à jour le tableau des cas dans `README.md` (section Tests) pour tout nouveau cas.

## 6. Test de non-régression d'un bug

Nommer l'assertion d'après le comportement attendu, pas d'après le bug (« clé PGDG retirée », pas « bug postgresql.asc »). Ajouter le chemin ou la condition qui a révélé le bug à la liste du cas existant le plus proche plutôt que de créer un cas : chaque scénario coûte un reset et une install.
