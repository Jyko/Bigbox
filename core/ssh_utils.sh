#!/usr/bin/env bash
# shellcheck shell=bash

################################
# Utilitaires communs pour SSH #
################################

# Créer le répertoire des clés SSH de la Bigbox, accessible uniquement par l'utilisateur
ssh_verify_directory() {
    mkdir -p "$BB_SSH_DIR"
    chmod 700 "$BB_SSH_DIR"
}

# Obtenir le chemin standard d'une clé SSH de la Bigbox
# $1 key_name   : Le nom de la SSH Key
ssh_get_key_path() {
    local key_name="$1"

    if [[ -z "$key_name" ]]; then
        log_error "Le nom de la clé SSH est obligatoire \n"
        return 2
    fi

    echo "$BB_SSH_DIR/$key_name"
}

# Générer une paire de clés SSH ed25519 sans passphrase, si elle n'existe pas déjà
# $1 key_name   : Le nom de la clé SSH
ssh_generate_key() {
    local key_name="$1"

    if [[ -z "$key_name" ]]; then
        log_error "Le nom de la clé SSH est obligatoire \n"
        return 2
    fi

    ssh_verify_directory

    local private_key_path public_key_path

    private_key_path=$(ssh_get_key_path "$key_name")
    public_key_path=$(ssh_get_key_path "$key_name.pub")

    # Si au moins l'une des clés de la paire est manquante, nous effaçons et regénérons une paire complète.
    if [[ ! -f "$private_key_path" || ! -f "$public_key_path" ]]; then
        rm -f "$private_key_path" "$public_key_path"
        ssh-keygen -t ed25519 -f "$private_key_path" -N "" -q
        chmod 600 "$private_key_path"
        chmod 644 "$public_key_path"
    fi
}

# Supprimer une paire de clés SSH de la Bigbox
# $1 key_name   : Le nom de la clé SSH
ssh_delete_key() {
    local key_name="$1"

    if [[ -z "$key_name" ]]; then
        log_error "Le nom de la clé SSH est obligatoire \n"
        return 2
    fi

    local private_key_path public_key_path

    private_key_path=$(ssh_get_key_path "$key_name")
    public_key_path=$(ssh_get_key_path "$key_name.pub")

    rm -f "$private_key_path" "$public_key_path"

    # Retirer le répertoire des clés Bigbox s'il est désormais vide
    rmdir --ignore-fail-on-non-empty "$BB_SSH_DIR" 2>/dev/null || true
}