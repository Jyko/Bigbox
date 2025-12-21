# METADATA du module
MODULE_NAME="k8s"
MODULE_PRIORITY=200
# Workaround le temps que je charge les modules sans effacer MODULE_NAME et MODULE_PRIORITY à chaque fois
BB_K8S_MODULE_NAME="k8s"
BB_K8S_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_K8S_MODULE_DOTFILES_DIR="$BB_K8S_MODULE_BASE_DIR/dotfiles"
BB_K8S_MICROK8S_TIMEOUT=30

# Installer microk8s et kubectx
k8s_install() {

    snap_wrapper install microk8s --classic

    # Ajouter le $USER au groupe pour ne plus avoir à sudo, ne prend effet qu'après un redémarrage du WSL2 ou un reboot OS
    sudo usermod -a -G microk8s $USER

    ######################################
    # INSTALLATION des outils Kubernetes #
    ######################################

    # Kubectl et Helm non wrap dans microk8s
    snap_wrapper install kubectl --classic
    snap_wrapper install helm --classic

    # Kubectx
    apt_wrapper install -y kubectx

    # Kubecolor
    if ! command -v kubecolor >/dev/null 2>&1; then
        wget -O /tmp/kubecolor.deb https://kubecolor.github.io/packages/deb/pool/main/k/kubecolor/kubecolor_$(wget -q -O- https://kubecolor.github.io/packages/deb/version)_$(dpkg --print-architecture).deb
        sudo dpkg -i /tmp/kubecolor.deb
        apt_wrapper update
    fi

    ##############################
    # CONFIGURATION des DOTFILES #
    ##############################

    # Créer le répertoire de configuration K8S et rendre $USER propriétaire
    mkdir -p "$BB_K8S_CONFIG_DIR"
    sudo chown -f -R $USER "$BB_K8S_CONFIG_DIR"

    # Installer et sourcer les aliases et de l'autocomplétion
    install_dotfile "kubernetes_aliases.sh" "$BB_K8S_MODULE_NAME" "$BB_K8S_MODULE_DOTFILES_DIR"
    install_dotfile "kubernetes_autocompletion.sh" "$BB_K8S_MODULE_NAME" "$BB_K8S_MODULE_DOTFILES_DIR"

    ############################################
    # CONFIGURATION du $HOME/.kube/config.yaml #
    ############################################
    
    local standard_file="$BB_K8S_CONFIG_DIR/config"
    local unified_file="$BB_K8S_CONFIG_DIR/unified-configs.yaml"
    local backup_file="$BB_K8S_CONFIG_DIR/backup-config.yaml"
    local bigbox_file="$BB_K8S_CONFIG_DIR/bigbox.yaml"

    # Backup des anciennes configurations et des symlinks si il en existe
    if [ -f "$standard_file" ] && [ ! -L "$standard_file" ]; then
        mv "$standard_file" "$backup_file"
    fi

    # Est-ce qu'il existe déjà un contexte BigBox dans l'ancienne configuration ?
    local need_merge=1

    if sudo kubectl --kubeconfig="$backup_file" config get-contexts -o name 2>&1 \
        | grep -q "^$BB_K8S_CONTEXT$"; then

        # Pas besoin de merge l'ancienne configuration avec une nouvelle, le contexte bigbox est déjà configuré
        echo "▬ Le contexte $BB_K8S_CONTEXT est déjà présent dans l'ancienne configuration Kubenertes"
        need_merge=1
    else
        # Il va falloir merge l'ancienne configuration avec une nouvelle pour y ajouter le contexte bigbox
        echo "✚ Le contexte $BB_K8S_CONTEXT n'existe pas dans l'ancienne configuration Kubenertes"
        need_merge=0

        # Générer le fichier de configuration
        sudo microk8s config > "$bigbox_file"
        # Renommer le contexte pour éviter les conflits et éviter les duplicats
        sudo kubectl --kubeconfig="$bigbox_file" config rename-context microk8s "$BB_K8S_CONTEXT"
    fi

    # Génération de la configuration unifiée avec ou sans merge
    KUBECONFIG="$backup_file${need_merge:+:$bigbox_file}" kubectl config view --merge --flatten > "$unified_file"

    # Symlink sur config.yaml, comme çà c'est propre et portable 👍
    ln -sf "$unified_file" "$standard_file"

    #####################################
    # CONFIGURATION du noeud Kubernetes #
    #####################################

    # Activer :
    #   - La persitance sur le FS du Host pour que des volumes persistants puissent être créer
    #   - Le service de métrologie (Prometheus)
    sudo microk8s enable hostpath-storage metrics-server

    # Créer le namespace si celui-ci n'existe pas afin d'éviter les conflits et petit accident (coucou la PRD :D),
    # puis switch dedans (même si le wrapper forcera l'utilisation de ce dernier partout)
    kutils_kubectl_wrapper get namespace "$BB_K8S_NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$BB_K8S_NAMESPACE"
    kutils_verify_kube_context
}

# TODO, y a du taff'
# k8s_uninstall() { return 0 }

# A refléchir
# k8s_upgrade() { return 0 }

k8s_start() {

    k8s_verify_microk8s_install

    microk8s start >/dev/null 2>&1 || true

    # Attendre que microk8s soit prêt avec timeout 30s
    if ! timeout "$BB_K8S_MICROK8S_TIMEOUT" microk8s status --wait-ready >/dev/null 2>&1; then
        echo -e "\r\t🕙 microk8s n'est pas prêt après ${BB_K8S_MICROK8S_TIMEOUT}s 💥 Vérifiez les logs avec 'sudo microk8s inspect' 🤓"
        return 2
    fi
}

k8s_stop() {

    k8s_verify_microk8s_install
    
    microk8s stop >/dev/null 2>&1 || true
}

k8s_verify_microk8s_install() {

    if ! command -v microk8s >/dev/null 2>&1; then
        echo -e "\r\t🧐 microk8s n'est pas installé"
        return 1
    fi
}