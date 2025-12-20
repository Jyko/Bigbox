# Ensemble de fonctions utiles pour générer, copier, déplacer, modifier des fichiers de configs dit dotfile.

# Ajouter une instruction "source" de ce Dotfile dans le .bashrc de l'utilisateur courant
# $1 filename   : Le nom du Dotfile
# $2 category   : La catégorie de ce Dotfile (optionnal) (default: "")
source_dotfile() {
    local filename="$1"
    local category="${2:-}"

    local dotfile_path=$(get_file_path "$BB_CFG_DIR" "$filename" "$category")

    verify_file "$BB_CFG_MAIN_DOTFILE"

    source_file "$dotfile_path" "$BB_CFG_MAIN_DOTFILE"

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

# Installer un Dotfile de la BigBox dans le dossier de configuration attendu
# $1 dotfile    : Le nom du Dotfile
# $2 category   : La catégrogie de ce Dotfile (optionnal) (default: "")
install_dotfile() {
    local filename="$1"
    local category="${2:-}"

    local src_path=$(get_file_path "$BB_RSC_DOTFILES_DIR" "$filename" "$category")

    # Vérifier que le Dotfile source existe bien
    verify_existing_path "$src_path"

    local dst_path=$(get_file_path "$BB_CFG_DIR" "$filename" "$category")

    verify_dotfile_install_directory "$category"

    cp "$src_path" "$dst_path"
    chmod 644 "$dst_path"

}

# Obtenir un chemin d'un Dotfile en tenant en compte de son éventuelle catégorie associée
# $1 base_path  : Le chemin de base
# $2 filename   : Le nom du fichier
# $3 category   : La catégorie (optionnal) (default: "")
get_file_path() {
    local base_path="$1"
    local filename="$2"
    local category="${3:-}"

    printf '%s' "${base_path}${category:+/$category}${filename:+/$filename}"

}

# Vérifier la bonne configuration du répertoire d'installation des Dotfiles
# $1 category   : La catégorie du répertoire d'installation à vérifier (optionnal) (default: "")
verify_dotfile_install_directory() {
    local category="${1:-}"

    local candidate_dir=$(printf '%s' "${BB_CFG_DIR}${category:+/$category}")

    # Créer les répertoires si manquants
    if ! verify_existing_path "$candidate_dir"; then
        mkdir -p "$candidate_dir" || { echo "Impossible de créer $candidate_dir" >&2; exit 1; }
    fi

}

# Vérifier qu'un chemin existe bien et pointe soit vers un fichier, soit vers un répertoire
# $1 path   : Le path à vérifier
verify_existing_path() {
    local path="$1"

    if [[ -z "$path" ]]; then
        echo "Aucun chemin fourni de fichier ou de répertoire fourni, impossible de vérifier son existence" >&2
        return 1
    elif [[ -d "$path" ]]; then
        return 0
    elif [[ -f "$path" ]]; then
        return 0
    else
        echo "Le chemin $path ne pointe ni vers un dossier, ni un fichier" >&2
        return 1
    fi

}

# Vérifier que ce fichier existe, sinon le créer.
# $1 file_path  : Le chemin de ce fichier
verify_file() {
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

}