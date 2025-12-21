parse_args() {

    for arg in "$@"; do
        if is_valid_action "$arg"; then

            verify_action
            ACTION="$arg"
            ACTION_SET=true

        else
            case "$arg" in
                -d|--debug)
                    DEBUG=true
                    ;;
                --nb|--no-banner)
                    SHOW_BANNER=false
                    ;;
                --ee|--easter-eggs)
                    SHOW_EASTER_EGGS=true
                    ;;
                *)
                    echo "Argument non supporté : $arg"
                    exit 1
                    ;;
            esac
        fi
    done
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
    sudo env DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

# Décorateur pour snapd afin de gérer les installations déjà existantes
# $1 cmd : La commande Snapd à exécuter
# $2 snap : Le package Snap contre lequel jouer la commande Snapd
# $3 flags... : Les flags supplémentaires (optionnal)
snap_wrapper() {
    local cmd="$1"
    local snap="$2"
    local flags="${3:-}"

    case "$cmd" in
        install|refresh|remove)
            ;;
        *)
            echo "Commande non supportée: $cmd" >&2
            return 1
            ;;
    esac

    local installed=$(snap list "$snap" >/dev/null 2>&1 && echo 1 || echo 0 )

    # Vérifier si le snap est déjà installé
    if [[ "$cmd" == "install" ]] && (( installed )); then
        return 0
    fi

    # Installer le snap si il ne l'est pas lors d'une tentative de refresh
    if [[ "$cmd" == "refresh" ]] && (( ! $installed )); then
        cmd="install"
    fi

    # Ne rien faire si le snap est déjà désintallé
    if [[ "$cmd" == "remove" ]] && (( ! $installed )); then
        return 0
    fi

    sudo snap $cmd $snap $flags
    
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

    echo "$result";

}

# Vérifier qu'un répertoire existe à ce chemin
# $1 path   : Le path à vérifier
verify_existing_dir() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "Aucun chemin fourni de répertoire fourni, impossible de vérifier son existence" >&2
        return 1
    elif [[ -d "$path" ]]; then
        return 0
    else
        echo "Le chemin $path ne pointe pas vers un dossier" >&2
        return 1
    fi

}

verify_existing_file() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "Aucun chemin fourni de fichier, impossible de vérifier son existence" >&2
        return 1
    elif [[ -f "$path" ]]; then
        return 0
    else
        echo "Le chemin $path ne pointe pas vers un fichier" >&2
        return 1
    fi
}

# Vérifier que ce fichier existe, sinon le créer.
# $1 file_path  : Le chemin de ce fichier
assure_existing_file() {
    local file_path="$1"

    if [[ -z "$file_path" ]]; then
        echo "Aucun chemin de fichier fourni, impossible de vérifier son existence et de le créer" >&2
        return 1
    elif [[ -d "$file_path" ]]; then
        echo "Le chemin $file_path est un répertoire et non un chemin de fichier comme attendu" >&2
        return 1
    elif [[ ! -f "$file_path " ]]; then
        touch "$file_path"
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