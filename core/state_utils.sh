#!/usr/bin/env bash
# shellcheck shell=bash

#######################################################################################
# Registre de ce que la Bigbox a elle-même installé ou créé sur la machine.
#
# L'uninstall ne doit retirer que ces éléments : un paquet, un fichier, un groupe ou un
# k3s présents avant la Bigbox (ex. htop sur un Ubuntu Desktop) doivent rester intacts.
#
# Un élément est une chaîne libre, préfixée par sa nature :
#   apt:<paquet>    file:<chemin>    group:<nom>    k3s
#######################################################################################

# Marquer un élément comme installé par la Bigbox
# $1 item : L'élément
state_mark_owned() {
    local item="${1:-}"

    if [[ -z "$item" ]]; then
        log_error "L'élément à enregistrer est obligatoire \n"
        return 2
    fi

    mkdir -p "$(dirname "$BB_STATE_FILE")"
    touch "$BB_STATE_FILE"

    if ! grep -Fxq -- "$item" "$BB_STATE_FILE"; then
        printf '%s\n' "$item" >> "$BB_STATE_FILE"
    fi
}

# Retourne 0 si l'élément a été installé par la Bigbox, sinon 1
# $1 item : L'élément
state_is_owned() {
    local item="${1:-}"

    [[ -n "$item" && -f "$BB_STATE_FILE" ]] && grep -Fxq -- "$item" "$BB_STATE_FILE"
}

# Retirer un élément du registre (après sa désinstallation)
# $1 item : L'élément
state_unmark() {
    local item="${1:-}"

    if [[ -z "$item" || ! -f "$BB_STATE_FILE" ]]; then
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    grep -Fxv -- "$item" "$BB_STATE_FILE" > "$tmp" || true
    cat "$tmp" > "$BB_STATE_FILE"
    rm -f "$tmp"
}

# Créer un fichier système (avec élévation de privilèges) à partir de stdin, et l'enregistrer
# comme appartenant à la Bigbox uniquement s'il n'existait pas avant.
# Un fichier déjà présent (ex. un kubernetes.list créé par l'utilisateur) n'est pas modifié.
# $1 file  : Le chemin du fichier
# stdin    : Le contenu
state_create_file() {
    local file="${1:-}"

    if [[ -z "$file" ]]; then
        log_error "Le chemin du fichier à créer est obligatoire \n"
        return 2
    fi

    if [[ -e "$file" ]] && ! state_is_owned "file:$file"; then
        log_debug "Le fichier $file existe déjà et n'appartient pas à la Bigbox, il est conservé \n"
        cat > /dev/null
        return 0
    fi

    fs_file_replace "$file"
    state_mark_owned "file:$file"
}

# Supprimer ces fichiers s'ils ont été créés par la Bigbox
# $@ : Les chemins des fichiers
state_remove_owned_files() {
    local file

    for file in "$@"; do
        if state_is_owned "file:$file"; then
            sudo rm -f "$file"
            state_unmark "file:$file"
        fi
    done
}
