# METADATA du module
MODULE_NAME="basic"
MODULE_PRIORITY=0

BB_BASIC_MODULE_NAME="basic"
BB_BASIC_MODULE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_BASIC_MODULE_DOTFILES_DIR="$BB_BASIC_MODULE_BASE_DIR/dotfiles"

# Liste des packages considérés comme suffisament basiques pour ne jamais être désinstallés
BB_BASIC_PACKAGES=(
    apt-transport-https
    bash-completion
    curl
    ca-certificates
    git
    golang-go
    jq
    unzip
    wget
)

basic_install() {

    apt_wrapper install ${PACKAGES[@]}

    cfg_add_var "PATH" "$HOME/go/bin"

    install_dotfile "basic_export.sh" "$BB_BASIC_MODULE_NAME" "$BB_BASIC_MODULE_DOTFILES_DIR"
    
}

basic_upgrade() {
    apt_wrapper update && apt_wrapper install --only-upgrade "${PACKAGES[@]}"
}