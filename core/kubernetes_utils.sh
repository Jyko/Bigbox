#!/usr/bin/env bash
# shellcheck shell=bash

#######################################
# Utilitaires communs pour KUBERNETES #
#######################################

# Assert le contexte Kubernetes, retourne une erreur et arrête le script si le contexte n'est pas celui du noeud Kubernetes BigBox.
kutils_assert_kube_context() {

    local current_kubectx
    current_kubectx="$(kubectl config current-context 2>/dev/null || true)"

    if [[ "$current_kubectx" != "$BB_K8S_CONTEXT" ]]; then
        log_error "Mauvais contexte Kubernetes 🚨 \n"
        log_error "Attendu : $BB_K8S_CONTEXT \n"
        log_error "Actuel  : ${current_kubectx:-<aucun>} \n"
        exit 1
    fi

    return 0
}

# Vérifier et switch de contexte Kubernetes si celui-ci est différent de celui du noeud Kubernetes de la BigBox
kutils_verify_kube_context() {

    if ! kutils_assert_kube_context; then
        kubectx "$BB_K8S_CONTEXT" >/dev/null 2>&1 || {
            log_error "Impossible de passer au contexte $BB_K8S_CONTEXT via kubectx \n"
            exit 1
        }
    fi

    return 0
}

# Décorateur pour kubectl afin de toujour s'assurer que les commandes sont jouées dans le bon contexte (pas la PRD :D)
kutils_kubectl_wrapper() {

    run_cmd kubectl \
        --context "$BB_K8S_CONTEXT" \
        "$@"

}

# Décorateur pour helm afin de toujours s'assurer que les commandes sont jouées dans le bon contexte (toujours pas la PRD :D)
kutils_helm_wrapper() {

    run_cmd helm \
        --kube-context "$BB_K8S_CONTEXT" \
        "$@"

}

kutils_is_api_available() {

    if ! command -v kubectl >/dev/null 2>&1; then
        log_warn "kubectl n'est pas installé \n" ;
        return 1
    fi

    # Check rapide pour voir si l'API Kubernetes du cluster Bigbox est joignable
    if ! run_cmd kutils_kubectl_wrapper get node; then
        log_warn "L'API Kubernetes n'est pas joignable \n"
        return 1
    fi

    return 0
}

kutils_wait_api_available() {

    # Check du service k3s, çà permet de failfast si le service k3s n'est pas installé ;)
    if ! grep -q '^k3s\.service' <(systemctl list-unit-files); then
        log_warn "Le service k3s n'est pas installé \n"
        return 1
    fi

    local start
    start=$(date +%s)

    while ! kutils_is_api_available; do
        sleep 1
        if (( $(date +%s) - start >= "$BB_K8S_KUBECTL_TIMEOUT" )); then
            log_warn "L'API Kubernetes n'est toujours pas joignable après $BB_K8S_KUBECTL_TIMEOUT secondes \n"
            return 1
        fi
    done

    return 0
}

# Mettre à jour ou installer une release Helm.
#
# $1 release_name   : Le nom de la release Helm à mettre à jour
# $3 helm_dir       : Le répertoire dans lequel se trouve la Chart.yaml de la release à mettre à jour
kutils_release_upgrade() {
    local release_name="$1"
    local helm_dir="$2"
    shift 2

    if ! kutils_is_api_available; then
        log_error "L'installation de la release $release_name ne peut être réalisée \n"
        return 2
    fi

    if [[ -z "$release_name" || -z "$helm_dir" ]]; then
        log_error "Le nom de la release et son répertoire ne peuvent être null \n"
        return 2
    fi

    kutils_helm_wrapper upgrade --install \
        "$release_name" \
        "$helm_dir" \
        -f "$helm_dir/values.yaml" \
        --namespace "$BB_K8S_NAMESPACE" \
        "$@"

    return 0
}

# Désinstaller une release Helm avec suppression de toutes les ressources construites (PV compris)
#
# $1 release_name   : Le nom de la release Helm à désinstaller
# $2 chart_name     : Le nom de la Chart Helm de la release à désinstaller
kutils_release_uninstall() {
    local release_name="$1"
    local chart_name="$2"

    if ! kutils_is_api_available; then
        log_warn "La désinstallation de la release $release_name ne peut être réalisée \n"
        return 2
    fi

    if [[ -z "$release_name" || -z "$chart_name" ]]; then
        log_error "Le nom de la release et de sa Chart ne peuvent être null \n"
        return 2
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

    # Si l'API Kubernetes n'est pas joignable pour l'arrêt, nous skippons, le cluster est déjà arrêté.
    if ! kutils_is_api_available; then
        log_warn "L'arrêt de la release $release_name ne peut être réalisée et est passée \n"
        return 0
    fi

    if [[ -z "$release_name" || -z "$chart_name" || -z "$helm_dir" ]]; then
        log_error "Le nom de la release, sa Chart et son répertoire ne peuvent être null \n"
        return 2
    fi

    local selector="app.kubernetes.io/instance=${release_name},app.kubernetes.io/name=${chart_name}"

    # Passage des replicas à 0 pour libérer les ressources
    for kind in deployment statefulset; do
        for name in $(kutils_kubectl_wrapper -n "$BB_K8S_NAMESPACE" get "$kind" -l "$selector" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
            kutils_kubectl_wrapper -n "$BB_K8S_NAMESPACE" scale "$kind/$name" --replicas=0 || true
        done
    done

    # Supprimer les pods restants pour libérer les ressources immédiatement
    kutils_kubectl_wrapper -n "$BB_K8S_NAMESPACE" delete pods -l "$selector" --wait=true --ignore-not-found || true

    return 0
}