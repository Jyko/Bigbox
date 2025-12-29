#!/usr/bin/env bash
# shellcheck shell=bash

list_contains() {
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

list_append() {
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

    if list_contains -l="$list" -v="$value" -s="$separator"; then
        echo "$list"
    elif [[ -n "$list" ]]; then
        echo "${list}${separator}${value}"
    else
        echo "$value"
    fi

    return 0
}

list_remove() {
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