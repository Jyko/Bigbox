#!/usr/bin/env bash
# shellcheck shell=bash

###################################
# Utilitaires communs génériques #
###################################

# Wrapper universel de commandes
# Contrôle les flux stdin/stdout/stderr des commandes executés.
# $@        : La commande à executer
run_cmd() {

    # En débug nous ne contrôlons pas stdout ou stderr et laissons le comportement par défaut.
    if log_is_debug; then
        "$@"
    else
        # En info et silent nous capturons stdout et stderr pour éviter de log toutes les commandes
        local output
        output="$("$@" 2>&1)"
        local status=$?
        
        # En cas d'erreur, nous loggons stderr
        if (( status != 0 )); then
            log_error "🧨 code:${status:-1} '$@'"
            # Réinjection du stderr sans modifier son format pour une meilleure compréhension des erreurs
            printf "%s\n" "$output" >&2
        fi

        return $status
    fi
}

is_valid_action() {
    local action="$1"

    for a in "${BB_ALLOWED_ACTIONS[@]}"; do
        [[ "$a" == "$action" ]] && return 0
    done

    return 1
}

verify_action() {

    if [[ "$ACTION_SET" == true ]]; then
        echo "Une seule action est autorisée à la fois"
        echo "Pour obtenir de l'aide : bigbox.sh help"
        exit 1
    fi

}

# Décorateur pour apt-get afin que celui-ci passe en mode non-interractif complet et
# ne redirige aucun flux vers /dev/tty, bloquant ainsi les scripts.
apt_wrapper() {
    if log_is_debug; then
        # Comportement normal
        sudo apt-get -y "$@"
    else 
        # Mode silencieux complet
        sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -qq "$@" </dev/null
    fi
}

# Retourne la nouvelle valeur d'une variable d'env après la concaténation de cette valeur
# avec les anciennes connues. Ne modifie pas cette variable d'env.
#
# $1 var        : Le nom de cette variable d'env
# $2 value      : La nouvelle valeur de cette variable d'env à concaténer ou remplacer
# $3 separator  : Le séparateur entre chaque valeur de la variable d'env, si celui-ci est différent
#                 de ":" (optionnal) (default: ":")
#
# Exemple :
#
# KUBECONFIG:$HOME/.kube/config
# echo "$(add_value_to_varenv KUBECONFIG "$HOME/.kube/nouvelle_valeur)"
# $ $HOME/.kube/config:$HOME/.kube/nouvelle_valeur
# echo KUBECONFIG
# $ $HOME/.kube/config
append_value_to_var() {
    local var="$1"
    local value="$2"
    local separator="${3:-:}"

local current_value="${!var}"
    local result

    case "$separator$current_value$separator" in
        *"$separator$value$separator"*)
            result="$current_value"
            ;;
        *)
            if [[ -n "$current_value" ]]; then
                result="$current_value$separator$value"
            else
                result="$value"
            fi
            ;;
    esac

    printf "%s" "$result";

}

# Vérifier qu'un répertoire existe à ce chemin
# $1 path   : Le path à vérifier
verify_existing_dir() {
    local path="$1"

    if [[ -z "$path" ]]; then
        log_error "Aucun chemin fourni de répertoire fourni, impossible de vérifier son existence \n"
        return 2
    elif [[ -d "$path" ]]; then
        return 0
    else
        log_error "Le chemin $path ne pointe pas vers un dossier \n"
        return 2
    fi

}

verify_existing_file() {
    local path="$1"

    if [[ -z "$path" ]]; then
        log_error "Aucun chemin fourni de fichier, impossible de vérifier son existence \n"
        return 2
    elif [[ -f "$path" ]]; then
        return 0
    else
        log_error "Le chemin $path ne pointe pas vers un fichier \n"
        return 2
    fi
}


# Vérifier que ce fichier existe, sinon le créer.
# $1 file_path  : Le chemin de ce fichier
assure_existing_file() {
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

delete_empty_file() {
    local file_path="$1"

    if [[ -z "$file_path" ]]; then
        log_error "Aucun chemin de fichier fourni, impossible de vérifier son existence et de le créer \n"
        return 2
    elif [[ -d "$file_path" ]]; then
        log_error "Le chemin $file_path est un répertoire et non un chemin de fichier comme attendu \n"
        return 2
    elif [[ -f "$file_path " && -s "$file_path" ]]; then
        rm -f "$file_path"
        log_debug "Le fichier vide $file_path a été supprimé \n"
    fi

    return 0
}

# Ajouter une instruction "source" de ce fichier candidat dans ce fichier cible
# 
# $1 candidat       : Le fichier candidat à l'ajout dans ce fichier cible
# $2 target         : Le fichier cible dans lequel ce fichier va être sourcé
source_file() {
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
unsource_file() {
    local candidat="$1"
    local target="$2"

    if grep -Fxq "source $candidat" "$target"; then
        sed -i "\|^source[[:space:]]\+$candidat$|d" "$target"
    fi
    
}

# Ensemble de fonctions utiles pour générer, copier, déplacer, modifier des fichiers de configs dit dotfile.

# Installer un Dotfile de la BigBox dans le dossier de configuration standard
# $1 dotfile    : Le nom du Dotfile
# $2 module     : Le module installant ce Dotfile
# $3 src_path   : Le répertoire source contenant ce Dotfile
install_dotfile() {
    local dotfile="$1"
    local module="$2"
    local src_dir="$3"

    # Vérifier que le Dotfile source existe bien
    verify_existing_file "$src_dir/$dotfile"

    local dst_dir=$(printf '%s' "${BB_CFG_DIR}${module:+/$module}")

    # Créer les répertoires si manquants
    if ! verify_existing_dir "$dst_dir"; then
        mkdir -p "$dst_dir" || { echo "Impossible de créer $dst_dir" >&2; exit 1; }
    fi

    # Copie du fichier Dotfile dans le répertoire d'installation standard
    cp "$src_dir/$dotfile" "$dst_dir/$dotfile"
    chmod 644 "$dst_dir/$dotfile"

    assure_existing_file "$BB_CFG_MAIN_DOTFILE"

    source_file "$dst_dir/$dotfile" "$BB_CFG_MAIN_DOTFILE"

}

# Ajouter à ce texte à ce fichier en utilisant le wrapper de commande
#
# $1        : Le chemin du fichier dans lequel ajouter ce contenu
# $...      : Le contenu à ajouter
file_append() {
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
file_replace() {
    local file="$1"
    shift

    local tmpfile=$(mktemp)

    cat > "$tmpfile" "$@"

    run_cmd sudo tee -a "$file" >/dev/null < "$tmpfile"

    # Nettoyage du fichier temporaire
    rm "$tmpfile"
}