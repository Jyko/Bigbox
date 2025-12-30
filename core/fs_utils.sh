#!/usr/bin/env bash
# shellcheck shell=bash

# Vérifier qu'un répertoire existe à ce chemin
# $1 path   : Le path à vérifier
fs_verify_existing_dir() {
    local path="$1"

    if [[ -z "$path" ]]; then
        log_error "Aucun chemin fourni de répertoire fourni, impossible de vérifier son existence \n"
        return 2
    elif [[ -d "$path" ]]; then
        log_debug "Le chemin $path pointe vers un dossier existant \n"
        return 0
    else
        log_error "Le chemin $path ne pointe pas vers un dossier \n"
        return 3
    fi

}

fs_verify_existing_file() {
    local path="$1"

    if [[ -z "$path" ]]; then
        log_error "Aucun chemin fourni de fichier, impossible de vérifier son existence \n"
        return 2
    elif [[ -f "$path" ]]; then
        log_debug "Le chemin $path pointe vers un fichier existant \n"
        return 0
    else
        log_error "Le chemin $path ne pointe pas vers un fichier \n"
        return 2
    fi
}


# Vérifier que ce fichier existe, sinon le créer.
# $1 file_path  : Le chemin de ce fichier
fs_assure_existing_file() {
    local file_path="$1"

    if [[ -z "$file_path" ]]; then
        log_error "Aucun chemin de fichier fourni, impossible de vérifier son existence et de le créer \n"
        return 2
    elif [[ -d "$file_path" ]]; then
        log_error "Le chemin $file_path est un répertoire et non un chemin de fichier comme attendu \n"
        return 2
    elif [[ ! -f "$file_path " ]]; then
        mkdir -p "$(dirname -- "$file_path")"
        touch "$file_path"
    fi

    return 0
}

fs_delete_empty_file() {
    local file_path="$1"

    if [[ -z "$file_path" ]]; then
        log_error "Aucun chemin de fichier fourni, impossible de vérifier son existence et de le créer \n"
        return 2
    elif [[ -d "$file_path" ]]; then
        log_error "Le chemin $file_path est un répertoire et non un chemin de fichier comme attendu \n"
        return 2
    elif [[ -f "$file_path " ]]; then
        if [[ -s "$file_path" ]]; then
            rm -f "$file_path"
            log_debug "Le fichier vide $file_path a été supprimé \n"
        else
            log_debug "Le fichier $file_path n'est pas vide et n'a pas été supprimé \n"
        fi
    fi

    return 0
}

# Ajouter une instruction "source" de ce fichier candidat dans ce fichier cible
# 
# $1 candidat       : Le fichier candidat à l'ajout dans ce fichier cible
# $2 target         : Le fichier cible dans lequel ce fichier va être sourcé
fs_source_file() {
    local candidat="$1"
    local target="$2"

    # Ajouter la commande source du fichier candidat que si elle n'existe pas déjà dans la cible
    if ! grep -Fxq "source $candidat" "$target"; then
        echo "source $candidat" >> "$target"
    fi

}

# Effacer une instruction "source" de ce fichier candidat dans ce fichier cible
# 
# $1 candidat       : Le fichier candidat à la suppression dans ce fichier cible
# $2 target         : Le fichier cible dans lequel ce fichier va arrêter d'être sourcé
fs_unsource_file() {
    local candidat="$1"
    local target="$2"

    if grep -Fxq "source $candidat" "$target"; then
        sed -i "\|^source[[:space:]]\+$candidat$|d" "$target"
    fi
    
}

# Ajouter à ce texte à ce fichier en utilisant le wrapper de commande
#
# $1        : Le chemin du fichier dans lequel ajouter ce contenu
# $...      : Le contenu à ajouter
fs_file_append() {
    local file="$1"
    shift

    local tmpfile=$(mktemp)

    cat > "$tmpfile" "$@"

    run_cmd sudo tee -a "$file" >/dev/null < "$tmpfile"

    # Nettoyage du fichier temporaire
    rm "$tmpfile"
}

# Remplacer ce fichier par ce contenu en utilisant le wrapper de commande
#
# $1        : Le chemin du fichier dans lequel ajouter ce contenu
# $...      : Le contenu à ajouter
fs_file_replace() {
    local file="$1"
    shift

    local tmpfile=$(mktemp)

    cat > "$tmpfile" "$@"

    run_cmd sudo tee -a "$file" >/dev/null < "$tmpfile"

    # Nettoyage du fichier temporaire
    rm "$tmpfile"
}