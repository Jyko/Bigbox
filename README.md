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

Une fois le projet récupéré sur la distribution cible via un `git clone`, nous rendons le script `./bigbox.sh` executable :

```sh
chmod +x ./bigbox.sh
```

Nous lançons ensuite l'installation de la Bigbox :

```sh
./bigbox.sh install
```
Nous désinstallons la Bigbox :

```sh
./bigbox.sh uninstall
```

Nous éteignons les outils dont nous ne nous servons pas pour libérer des ressources :
```sh
./bigbox.sh stop
```

Nous rallumons les outils :
```sh
./bigbox.sh start
```

Si l'on souhaite, nous ajoutons la Bigbox au PATH afin de l'appeler en tant que commande :  
>.bashrc
```sh
export PATH=$PATH:{chemin_vers_la}/bigbox.sh
```

## Outils

La Bigbox installe deux types d'outils :
- Des utilitaires linux pour un usage plus aisé de la distribution Ubuntu (ex: *yazi, eza, bat ...*)
- Des outils de développement lourd, utilisé comme dépendances externes par nos applications (ex: *NATS, PostgreSQL ...*)

Nous ne ferons ici que la liste des outils de développement.

| Outil | Mode | Port d'accès | Infos utiles |
| --- | --- | --- | --- |
| GoLang | package | N/A | SDK GoLang pour compiler des binaires depuis leurs sources |
| Docker | package | N/A | Moteur de conteneurisation, installé selon les préconisations de la documentation officielle |
| Kubernetes | script | N/A | Orchestrateur de conteneur, installé et managé par `k3s` via les scripts de la documentation officielle |
| PostgreSQL | Helm | `30001` | SGBDR |
| Nats JetStream | Helm | Client:`30010` Monitoring:`30011` | Broker message |
| NUI | Helm | `30012` | Client web pour NATS préconfiguré avec le contexte du NATS local |
| SFTP | Helm | `30020` | Serveur SFTP |

## Principes et Architecture

La Bigbox en elle mêle n'est qu'un framework permettant le développement de modules d'installation de nouveaux outils. Elle n'a pour vocation que de servir de chargeur et executeur de modules indépendants.

Les modules sont indépendants les uns des autres. Ils doivent disposer de fonction répondant aux actions principales (`install`, `uninstall`, `stop`, `start`). Celle-ci doivent pouvoir être jouer de manière idempotent.

Les modules disposent d'un ordre de lancement, qui doit pouvoir être inversé pour les besoins de certaines actions (`uninstall` et `stop`). Celui-ci ne doit pas entrer en conflit avec celui d'un autre module, sous peine de voir l'un des deux modules ne pas être chargé.

Les scripts situés dans le répertoire `./core` servent de librairies d'outils communes. Nous y retrouvons pêle-mêle des fonctions de chargement de variable d'environnement, de scale down de deployment Kubernetes et autres joyeusetés. Si une fonction doit être partagé entre plusieurs modules, il est conseillé de l'implémenter dans l'une des librairies du `./core`.

Les répertoires situés sous `./modules` sont les hôtes des différents modules indépendants. Chaque répertoire peut contenir un module et un seul. Un module se matérialise par un fichier `*.sh` portant son nom et implémentant les fonctions principales de la Bigbox. L'organisation interne du dossier est libre, si le module nécessite des ressources, nous pouvons les déposer en respectant une hiérarchie qui nous est propre.

Les fichiers situés dans le répertoire `./resources` sont les ressources spécifiques à la Bigbox et son core. Aucune ressource des modules ne doit se trouver dans ce répertoire.