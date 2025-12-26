#!/usr/bin/env bash
# shellcheck shell=bash

_cfg_list_contains() {
    local list="" value="" separator=":"

    for arg in "$@"; do
        case "$arg" in
            -l=*) list="${arg#-l=}" ;;
            -v=*) value="${arg#-v=}" ;;
            -s=*) separator="${arg#-s=}" ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    if [[ -z "$value" ]]; then 
        log_error "Une valeur dont tester la présence est obligatoire \n"
        return 2
    fi

    IFS="$separator" read -ra items <<< "$list"
    for item in "${items[@]}"; do
        [[ "$item" == "$value" ]] && return 0
    done

    return 1
}

_cfg_list_append() {
    local list="" value="" separator=":"

    for arg in "$@"; do
        case "$arg" in
            -l=*) list="${arg#-l=}" ;;
            -v=*) value="${arg#-v=}" ;;
            -s=*) separator="${arg#-s=}" ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    if [[ -z "$value" ]]; then
        log_error "Une valeur à ajouter est obligatoire \n"
        return 2
    fi

    if _cfg_list_contains -l="$list" -v="$value" -s="$separator"; then
        echo "$list"
    elif [[ -n "$list" ]]; then
        echo "${list}${separator}${value}"
    else
        echo "$value"
    fi

    return 0
}

_cfg_list_remove() {
    local list="" value="" separator=":"

    for arg in "$@"; do
        case "$arg" in
            -l=*) list="${arg#-l=}" ;;
            -v=*) value="${arg#-v=}" ;;
            -s=*) separator="${arg#-s=}" ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    if [[ -z "$value" ]]; then
        log_error "Une valeur à supprimer est obligatoire \n"
        return 2
    fi

    local result="" item

    IFS="$separator" read -ra items <<< "$list"

    # Nous ne supprimons pas directement, nous reconstruisons une nouvelle liste sans l'éventuelle valeur à supprimer. C'est plus simple pour gérer le séparateur.
    for item in "${items[@]}"; do
        # L'item est la valeur que nous souhaitons supprimer, nous sautons la boucle, nous ne la concaténons pas à notre nouvelle liste.
        [[ "$item" == "$value" ]] && continue
        result=$(list_append -l="$result" -v="$item" -s="$separator")
    done

    echo "$result"
}

_cfg_get_line() {
    local pattern="" file="" strict=0

    for arg in "$@"; do
        case "$arg" in
            -p=*) pattern="${arg#-p=}" ;;
            -f=*) file="${arg#-f=}" ;;
            -s) strict=1 ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        log_error "Un pattern est obligatoire \n" && return 2 ;
    fi

    if [[ -z "$file" || ! -f "$file" ]]; then
        log_error "Le chemin de fichier fourni $file n'est pas valide \n" && return 2 ;
    fi

     # Récupérer toutes les lignes correspondantes
    mapfile -t lines < <(grep -E "$pattern" "$file")
    local count=${#lines[@]}
    if (( count == 0 )); then
        log_debug "Aucune ligne d'instruction pour le pattern \"$pattern\" dans le fichier $file \n"
        echo ""
        return 0
    elif (( strict )) && (( count > 1 )); then
        log_error "$count lignes d'instruction pour le pattern \"$pattern\" dans le fichier $file \n"
        return 2
    fi

    echo "${lines[0]}"

    return 0
}

_cfg_set_line() {
    local pattern=""
    local line=""
    local file=""

    for arg in "$@"; do
        case "$arg" in
            -p=*) pattern="${arg#-p=}" ;;
            -l=*) line="${arg#-l=}" ;;
            -f=*) file="${arg#-f=}" ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        log_error "Un pattern est obligatoire \n" && return 2 ;
    fi

    if [[ -z "$file" || ! -f "$file" ]]; then
        log_error "Le chemin de fichier fourni $file n'est pas valide \n" && return 2 ;
    fi

    # Suppression de la ligne actuelle
    log_debug "Suppression de la ligne d'instruction matchant le pattern \"$pattern\" dans le fichier $file\n"
    sed -i -E "\|$pattern|d" "$file"

    # Nous n'écrivons une nouvelle instruction que si la nouvelle ligne n'est pas blanche/nulle
    if [[ -n "$line" ]]; then
        printf '%s\n' "$line" >> "$file"
    fi

    return 0
}

_cfg_env_get_value() {
    local key=""

    for arg in "$@"; do
        case "$arg" in
            -k=*) key="${arg#-k=}" ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    assure_existing_file "$BB_CFG_ENV_FILE"

    [[ -z "$key" ]] && return 1

    local pattern="^[[:space:]]*export[[:space:]]+$key="

    local line

    # Récupération de la ligne de configuration correspondant à l'export de la variable
    line=$(_cfg_get_line -p="$pattern" -f="$BB_CFG_ENV_FILE" -s) || { return $? ; }

    log_debug "line=$line \n"

    # Extraction de la valeur
    echo "${line#*=}"
    
    return 0
}

cfg_modify_env() {
    local key="" value="" mode=""

    for arg in "$@"; do
        case "$arg" in
            -k=*) key="${arg#-k=}" ;;
            -v=*) value="${arg#-v=}" ;;
            -a) mode="a" ;;
            -r) mode="r" ;;
            -d) mode="d" ;;
            *) log_error "Argument non supporté \n" && return 2 ;;
        esac
    done

    if [[ -z "$key" ]]; then
        log_error "Un nom de variable d'environnement est obligatoire \n" && return 2;
    fi

    if [[ -z "$mode" ]]; then 
        log_error "Un mode de modification est obligatoire \n" && return 2;
    fi

    assure_existing_file "$BB_CFG_ENV_FILE"

    local pattern current_value new_value 

    pattern="^[[:space:]]*export[[:space:]]+$key="
    current_value="$(_cfg_env_get_value -k="$key" || true)"

    log_debug "\n\nvalue=$value \ncurrent_value=$current_value \n"

    case "$mode" in
        a) new_value=$(_cfg_list_append -l="$current_value" -v="$value") ;;
        r) new_value="$value" ;;
        d) new_value=$(_cfg_list_remove -l="$current_value" -v="$value") ;;
        *) log_error "Erreur mode inconnu \n" && return 2 ;;
    esac

    log_debug "value=$value \ncurrent_value=$current_value \nnew_value=$new_value \n"

    # Si la nouvelle valeur est blanche à la suite de l'application des modifications, nous supprimons la ligne d'instruction dans le fichier de configuration.
    # Sinon nous ajoutons la ligne avec la nouvelle valeur
    if [[ -z "$new_value" ]]; then
        _cfg_set_line -p="$pattern" -l="" -f="$BB_CFG_ENV_FILE"
        delete_empty_file "$BB_CFG_ENV_FILE"
    else
        _cfg_set_line -p="$pattern" -f="$BB_CFG_ENV_FILE" -l="export $key=$new_value"
    fi

    return 0

}
