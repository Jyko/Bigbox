#!/usr/bin/env bash
# shellcheck shell=bash

BB_HOPPSCOTCH_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_HOPPSCOTCH_MODULE_HELM_DIR="$BB_HOPPSCOTCH_MODULE_BASE_DIR/helm"
BB_HOPPSCOTCH_HELM_CHART_NAME=bigbox-hoppscotch
BB_HOPPSCOTCH_HELM_RELEASE_NAME=bigbox-hoppscotch
BB_HOPPSCOTCH_PG_TIMEOUT=30
BB_HOPPSCOTCH_RETRY_DELAY=1

# TODO !
BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE="$BB_CFG_DIR/hoppscotch/hoppscotch.key"

hoppscotch_install() {

    _hoppscotch_create_database
    _hoppscotch_create_encryption_key

    # On failfast en tentant de récupérer l'IP de l'Host en amont
    local host_ip
    host_ip=$(get_host_ip)

    if [[ "$?" -ne 0 ]] || [[ -z "$host_ip" ]]; then
        log_error "L'IP de l'Host est inconnue\n"
        return 2
    fi

    run_cmd kutils_release_upgrade "$BB_HOPPSCOTCH_HELM_RELEASE_NAME" "$BB_HOPPSCOTCH_MODULE_HELM_DIR" \
        --set database.dataEncryptionKey="$(<"$BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE")" \
        --set hostIp="$host_ip"
}

hoppscotch_uninstall() {
    if run_cmd_silently kutils_is_api_available; then
        run_cmd kutils_release_uninstall \
            "$BB_HOPPSCOTCH_HELM_RELEASE_NAME" \
            "$BB_HOPPSCOTCH_HELM_CHART_NAME"
    fi

    _hoppscotch_delete_encryption_key
    _hoppscotch_drop_database
}

hoppscotch_upgrade() {

    _hoppscotch_create_database
    _hoppscotch_create_encryption_key

    # On failfast en tentant de récupérer l'IP de l'Host en amont
    local host_ip
    host_ip=$(get_host_ip)

    if [[ "$?" -ne 0 ]] || [[ -z "$host_ip" ]]; then
        log_error "L'IP de l'Host est inconnue\n"
        return 2
    fi

    run_cmd kutils_release_upgrade \
        "$BB_HOPPSCOTCH_HELM_RELEASE_NAME" \
        "$BB_HOPPSCOTCH_MODULE_HELM_DIR" \
        --set database.dataEncryptionKey="$(<"$BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE")" \
        --set hostIp="$host_ip" \
        
}

hoppscotch_start() {

    _hoppscotch_create_database
    _hoppscotch_create_encryption_key

    # On failfast en tentant de récupérer l'IP de l'Host en amont
    local host_ip
    host_ip=$(get_host_ip)

    if [[ "$?" -ne 0 ]] || [[ -z "$host_ip" ]]; then
        log_error "L'IP de l'Host est inconnue\n"
        return 2
    fi

    run_cmd kutils_release_upgrade \
        "$BB_HOPPSCOTCH_HELM_RELEASE_NAME" \
        "$BB_HOPPSCOTCH_MODULE_HELM_DIR" \
        --set database.dataEncryptionKey="$(<"$BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE")" \
        --set hostIp="$host_ip"
}

hoppscotch_stop() {
    run_cmd kutils_release_stop \
        "$BB_HOPPSCOTCH_HELM_RELEASE_NAME" \
        "$BB_HOPPSCOTCH_HELM_CHART_NAME" \
        "$BB_HOPPSCOTCH_MODULE_HELM_DIR"
}

# --------------------
# Encryption Key
# --------------------

_hoppscotch_create_encryption_key() {
    # Générer une clé d'encryption unique si elle n'existe pas.
    if [[ ! -f "$BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE" ]]; then

        mkdir -p "$(dirname "$BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE")"

        log_debug "Le fichier $BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE n'existe pas.\n"
        log_debug "Génération de la clé d'encryption\n"

        openssl rand -hex 16 > "$BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE"

        log_debug "La clé a été générée et écrite dans le fichier $BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE\n"
    else
        log_debug "Le fichier $BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE de la clé d'encryption existe déjà.\n"
    fi
}

_hoppscotch_delete_encryption_key() {
    log_debug "Suppression du fichier $BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE contenant la clé d'encryption des données\n"
    rm -rf "$BB_HOPPSCOTCH_ENCRYPTION_KEY_FILE"
}

# --------------------
# Database
# --------------------

# FIXME : Ecrire un système de dépendance
# FIXME : Utiliser des secrets Vault ou K8S pour récupérer les login/password

_hoppscotch_create_database() {
    # Créer la database hoppscotch seulement si elle n'existe pas.    
    _hoppscotch_wait_postgresql_available
    PGPASSWORD="bigbox" psql -U bigbox -h localhost -p 30001 -d bigbox -c "CREATE DATABASE hoppscotch;" >/dev/null 2>&1 || true
}

_hoppscotch_drop_database() {
    _hoppscotch_wait_postgresql_available
    PGPASSWORD="bigbox" psql -U bigbox -h localhost -p 30001 -d bigbox -c "DROP DATABASE IF EXISTS hoppscotch;" >/dev/null 2>&1
}

_hoppscotch_wait_postgresql_available() {
    local seconds_passed=0

    while ! PGPASSWORD="bigbox" pg_isready -U bigbox -h localhost -p 30001 > /dev/null 2>&1; do
        sleep $BB_HOPPSCOTCH_RETRY_DELAY
        (( seconds_passed += BB_HOPPSCOTCH_RETRY_DELAY ))
        if [[ $seconds_passed -ge $BB_HOPPSCOTCH_PG_TIMEOUT ]]; then
            log_error "Les tentatives de connexion à l'instance postgresql sont arrivées au terme du timeout de ${BB_HOPPSCOTCH_PG_TIMEOUT}s"
            return 1
        fi
    done

    return 0
}