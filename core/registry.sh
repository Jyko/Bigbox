#!/usr/bin/env bash
# shellcheck shell=bash

# --------------------
# Registres de configuration interne
# --------------------
declare -A REG_VALUE
declare -A REG_IS_SECRET

# --------------------
# API de manipulation du registre
# --------------------

reg_get() {
    local key="$1"

    if [[ -z "${REG_VALUE[$key]+x}" ]]; then
        log_error "La clé de registre \"$key\" n'est pas enregistrée\n"
        exit 2
    fi

    echo "${REG_VALUE[$key]}"
}

reg_bootstrap() {

    _reg_define

    _reg_hydrate

    # Nous validons que les variables enregistrées ont toutes une valeur associée
    _reg_validate
}

# --------------------
# Définition des règles du registre
# --------------------
_reg_define() {

    # PG
    _reg_define_key "BB_PG_VERSION"
    _reg_define_key "BB_PG_USERNAME"
    _reg_define_key "BB_PG_PASSWORD" secret
    _reg_define_key "BB_PG_DATABASE"

    # NATS
    _reg_define_key "BB_NATS_VERSION"

    # NUI
    _reg_define_key "BB_NUI_VERSION"

    # SFTP
    _reg_define_key "BB_SFTP_VERSION"
    _reg_define_key "BB_SFTP_USERNAME"
    _reg_define_key "BB_SFTP_BASE_DIRECTORY"

    # WIREMOCK
    _reg_define_key "BB_WIREMOCK_VERSION"

    # HOPPSCOTCH
    _reg_define_key "BB_HOPPSCOTCH_VERSION"
}

# Définir une clé de registre à renseigner par l'utilisateur.
# Elle peut être renseignée via un fichier de configuration .env ou l'export de variables d'environnement.
_reg_define_key() {
    local key="$1"
    shift 1

    for arg in "$@"; do
        case "$arg" in
        secret)    REG_IS_SECRET["$key"]=1 ;;
        *)
            log_error "Argument \"'$arg'\" pour la clé de registre \"$key\" est invalide\n"
            exit 2
            ;;
        esac
    done

    REG_VALUE["$key"]=""
}

# --------------------
# Hydratation du registre
# --------------------

# Hydrater le registre depuis des sources multiples en conservant un ordre de priorité
# Dans l'ordre descendant de priorité :
# 1. Fichier .env
#   b. .env standard
#   a. .env passé par l'utilisateur
# 2. Variables environnement
# 3. Prompts (secrets manquants)
_reg_hydrate() {

    if [[ -n "$BB_CFG_REGISTRY_DEFAULT_FILE" ]]; then
        log_debug "Chargement dans le registre du fichier par défaut \"$BB_CFG_REGISTRY_DEFAULT_FILE\"\n"
        _reg_load_env_file "$BB_CFG_REGISTRY_DEFAULT_FILE"
    else
        log_error "Le fichier de configuration par défaut \"$BB_CFG_REGISTRY_DEFAULT_FILE\" n'existe pas\n"
        exit 2
    fi

    if [[ -n "$BB_CFG_REGISTRY_USER_FILE" ]]; then
        log_debug "Chargement dans le registre du fichier utilisateur \"$BB_CFG_REGISTRY_USER_FILE\"\n"
        _reg_load_env_file "$BB_CFG_REGISTRY_USER_FILE"
    else
        log_debug "Aucun fichier de configuration utilisateur fourni"
    fi
    
    _reg_load_var_env

    _reg_load_prompt
}

# Hydratation du registre par chargement d'un fichier .env
# $1 file   : Le chemin du fichier .env à charger
_reg_load_env_file() {
    local file="$1"

    # Le fichier à charger doit exister
    if [[ ! -f "$file" ]]; then
        log_error "Le fichier d'environnement \"$file\" à charger n'existe pas\n"
        exit 2
    fi

    # Pour chaque paire composant le fichier
    while IFS='=' read -r key value; do

        # FIXME : Plus robuste :/
        [[ "$key" =~ ^#|^$ ]] && continue

        # Si la clé n'a pas été définie dans le registre, nous ne pouvons pas l'injectée depuis le fichier
        # Protection contre la réécriture de variable non désirée et leurs effets de bord
        if [[ -z "${REG_VALUE[$key]+x}" ]]; then 
            log_error "La clé de registre \"${key}\" n'est pas enregistrée\n"
            exit 2
        fi

        # Surcharge la valeur de la clé
        REG_VALUE["$key"]="$value"

    done < "$file"

    return 0
}

# Hydratation du registre par les variables d'environnement connues
_reg_load_var_env() {

    # Pour chaque clé enregistrée, on va tester si il existe une variable d'environnement dans ce shell avec une valeur non nulle/blanche
    for key in "${!REG_VALUE[@]}"; do
        # Surcharge la valeur de la clé
        [[ -n "${!key:-}" ]] && REG_VALUE["$key"]="${!key}"
    done

    return 0
}

# Hydratation du registre par le prompt utilisateur
_reg_load_prompt() {

    # Pour chaque clé enregistrée :
    # - Si aucune valeur
    # - Si secret
    # - Si LOG_LEVEL != SILENT
    # Alors nous proposons un prompt à l'utilisateur pour le renseigner
    for key in "${!REG_VALUE[@]}"; do
        if [[ -z "${REG_VALUE[$key]:-}" ]]; then
            if [[ "${REG_IS_SECRET[$key]:-0}" == 1 ]]; then
                if [[ -t 0 ]] && log_is_info; then
                    printf "Entrez le secret pour la clé %s: " "$key" >&2
                    read -s REG_VALUE["$key"] <&0
                    printf "\n" >&2
                fi
            fi
        fi
    done

    return 0
}

_reg_validate() {

  for key in "${!REG_VALUE[@]}"; do
    local value="${REG_VALUE[$key]}"

    log_debug "$key=$value"

    # Pour le moment, aucune clé ne peut se retrouver nulle/blanche
    if [[ -z "$value" ]]; then
        log_error "La clé de registre \"$key\" ne dispose pas de valeur\n"
        exit 2
    fi

  done
}
