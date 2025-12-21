################################
# Utilitaires communs pour SSH #
################################

ssh_verify_directory() {
    mkdir -p "$BB_SSH_DIR"
    chmod 700 "$BB_SSH_DIR"
}

# Obtenir le chemin standard d'une SSH Key BigBox
# $1 key_name   : Le nom de la SSH Key
ssh_get_key_path() {
    local key_name="$1"

    if [[ -z "$key_name" ]]; then
        echo -e "Le nom de la clé SSH ne peut être null"
        exit 1
    fi

    echo "$BB_SSH_DIR/$key_name"
}

ssh_generate_key() {
    local key_name="$1"

    if [[ -z "$key_name" ]]; then
        echo -e "Le nom de la clé SSH ne peut être null"
        exit 1
    fi

    ssh_verify_directory

    local private_key_path=$(ssh_get_key_path "$key_name")
    local public_key_path=$(ssh_get_key_path "$key_name.pub")

    # Si au moins l'une des clés de la paire est manquante, nous effaçons et regénérons une paire complète.
    if [[ ! -f "$private_key_path" || ! -f "$public_key_path" ]]; then
        rm -f "$private_key_path" "$public_key_path"
        
        ssh-keygen -t ed25519 -f "$private_key_path" -N "" -q
        chmod 600 "$private_key_path"
        chmod 644 "$public_key_path"
    fi
}

ssh_delete_key() {
    local key_name="$1"

    if [[ -z "$key_name" ]]; then
        echo -e "Le nom de la clé SSH ne peut être null"
        exit 1
    fi

    local private_key_path=$(ssh_get_key_path "$key_name")
    local public_key_path=$(ssh_get_key_path "$key_name.pub")

    rm -f "$$private_key_path" "$$public_key_path"
}