# METADATA du module
MODULE_NAME="basic"
MODULE_PRIORITY=0

# Liste des packages considérés comme suffisament basiques pour ne jamais être désinstallés
BB_BASIC_PACKAGES=(
    apt-transport-https
    bash-completion
    curl
    ca-certificates
    git
    jq
    unzip
    wget
)

basic_install() {
    apt_wrapper install -y ${PACKAGES[@]}
}

basic_upgrade() {
    apt_wrapper update -y && apt_wrapper install -y --only-upgrade "${PACKAGES[@]}"
}