#######################################
# Utilitaires communs pour KUBERNETES #
#######################################

# Assert le contexte Kubernetes, retourne une erreur et arrête le script si le contexte n'est pas celui du noeud Kubernetes BigBox.
kutils_assert_kube_context() {

    local current_kubectx="$(kubectl config current-context 2>/dev/null || true)"

    if [[ "$current_kubectx" != "$BB_K8S_CONTEXT" ]]; then
        echo "\r\t🚨 Mauvais contexte Kubernetes 🚨"
        echo "\r\t\tAttendu : $BB_K8S_CONTEXT"
        echo "\r\t\tActuel  : ${current_kubectx:-<aucun>}"
        exit 1
    fi

    return 0
}

# Vérifier et switch de contexte Kubernetes si celui-ci est différent de celui du noeud Kubernetes de la BigBox
kutils_verify_kube_context() {

    if ! kutils_assert_kube_context; then
        kubectx "$BB_K8S_CONTEXT" >/dev/null 2>&1 || {
            echo -e "\r\t❌ Impossible de passer au contexte $BB_K8S_CONTEXT via kubectx"
            exit 1
        }
    fi

    return 0
}

# Décorateur pour kubectl afin de toujour s'assurer que les commandes sont jouées dans le bon contexte (pas la PRD :D)
kutils_kubectl_wrapper() {

    kubectl \
        --context "$BB_K8S_CONTEXT" \
        "$@"

}

# Décorateur pour helm afin de toujours s'assurer que les commandes sont jouées dans le bon contexte (toujours pas la PRD :D)
kutils_helm_wrapper() {

    helm \
        --kube-context "$BB_K8S_CONTEXT" \
        "$@"

}

# Mettre à jour ou installer une release Helm.
#
# $1 release_name   : Le nom de la release Helm à mettre à jour
# $3 helm_dir       : Le répertoire dans lequel se trouve la Chart.yaml de la release à mettre à jour
kutils_release_upgrade() {
    local release_name="$1"
    local helm_dir="$2"

    if [[ -z "$release_name" || -z "$helm_dir" ]]; then
        echo "Le nom de la release et son répertoire ne peuvent être null" >&2
        return 1
    fi

    kutils_helm_wrapper upgrade --install "$release_name" "$helm_dir" -f "$helm_dir/values.yaml" --namespace "$BB_K8S_NAMESPACE"

    return 0
}

# Désinstaller une release Helm avec suppression de toutes les ressources construites (PV compris)
#
# $1 release_name   : Le nom de la release Helm à désinstaller
# $2 chart_name     : Le nom de la Chart Helm de la release à désinstaller
kutils_release_uninstall() {
    local release_name="$1"
    local chart_name="$2"

    if [[ -z "$release_name" || -z "$chart_name" ]]; then
        echo "Le nom de la release et de sa Chart ne peuvent être null" >&2
        return 1
    fi

    kutils_helm_wrapper uninstall "$release_name" --namespace "$BB_K8S_NAMESPACE"

    # Récupération et suppression des PVs associés à la release
    local label_selector="app.kubernetes.io/instance=${release_name},app.kubernetes.io/name=${chart_name}"

    for pv in $(kutils_kubectl_wrapper get pv -l "$label_selector" -o jsonpath='{.items[*].metadata.name}'); do
        [[ -n "$pv" ]] && kutils_kubectl_wrapper delete pv "$pv" || true
    done

    return 0
}

# Arrêter une release Helm sans la désinstaller : scale des controllers à 0 et suppression
# agressive des pods pour libérer les ressources. Ne touche pas aux PVCs ni à la release.
#
# $1 release_name   : Le nom de la release Helm à arrêter
# $2 chart_name     : Le nom de la Chart Helm de la release à arrêter
# $3 helm_dir       : Le répertoire dans lequel se trouve la Chart.yaml de la release à arrêter
kutils_release_stop() {
    local release_name="$1"
    local chart_name="$2"
    local helm_dir="$3"

    if [[ -z "$release_name" || -z "$chart_name" || -z "$helm_dir" ]]; then
        echo "Le nom de la release, sa Chart et son répertoire ne peuvent être null" >&2
        return 1
    fi

    local selector="app.kubernetes.io/instance=${release_name},app.kubernetes.io/name=${chart_name}"

    # Passage des replicas à 0 pour libérer les ressources
    for kind in deployment statefulset; do
        for name in $(kubectl_wrapper -n "$BB_K8S_NAMESPACE" get "$kind" -l "$selector" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
            kubectl_wrapper -n "$BB_K8S_NAMESPACE" scale "$kind/$name" --replicas=0 || true
        done
    done

    # Supprimer les pods restants pour libérer les ressources immédiatement
    kubectl_wrapper -n "$BB_K8S_NAMESPACE" delete pods -l "$selector" --wait=true --ignore-not-found || true

    return 0
}