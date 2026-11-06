#!/usr/bin/env bash
# shellcheck shell=bash

BB_STARSHIP_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BB_STARSHIP_DOTFILES_DIR="$BB_STARSHIP_BASE_DIR/dotfiles"
# Version installée depuis GitHub quand le paquet apt n'existe pas (Ubuntu 24.04)
BB_STARSHIP_VERSION="v1.27.0"
BB_STARSHIP_BINARY="/usr/local/bin/starship"

starship_install() {

    _starship_binary_install

    # Nous ne générons la configuration par défaut que si l'utilisateur n'en a pas déjà une.
    # Pas de run_cmd ici : il capture stdout et le fichier serait vide.
    if [[ ! -f "$BB_STARSHIP_CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$BB_STARSHIP_CONFIG_FILE")"
        starship print-config > "$BB_STARSHIP_CONFIG_FILE"
        state_mark_owned "file:$BB_STARSHIP_CONFIG_FILE"
    fi

    cfg_copy_dotfile "$BB_STARSHIP_DOTFILES_DIR/starship_env.sh"

}

starship_uninstall() {

    cfg_delete_dotfile "starship_env.sh"

    # La configuration n'est supprimée que si c'est la Bigbox qui l'a générée
    if state_is_owned "file:$BB_STARSHIP_CONFIG_FILE"; then
        rm -f "$BB_STARSHIP_CONFIG_FILE"
        state_unmark "file:$BB_STARSHIP_CONFIG_FILE"
    fi

    apt_purge_owned starship || true
    state_remove_owned_files "$BB_STARSHIP_BINARY"

}

# Le paquet starship n'est disponible dans les dépôts Ubuntu qu'à partir de la 25.04
_starship_binary_install() {
    if command -v starship >/dev/null 2>&1; then
        return 0
    fi

    if apt-cache show starship >/dev/null 2>&1; then
        apt_install starship
        return 0
    fi

    local arch
    case "$(dpkg --print-architecture)" in
        amd64) arch="x86_64" ;;
        arm64) arch="aarch64" ;;
        *) log_error "Architecture non supportée pour starship : $(dpkg --print-architecture) \n" ; return 2 ;;
    esac

    local tmp
    tmp=$(mktemp -d)

    run_cmd curl "${BB_CURL_OPTS[@]}" -o "$tmp/starship.tar.gz" \
        "https://github.com/starship/starship/releases/download/${BB_STARSHIP_VERSION}/starship-${arch}-unknown-linux-musl.tar.gz"
    tar -xzf "$tmp/starship.tar.gz" -C "$tmp" starship
    sudo install -m 0755 "$tmp/starship" "$BB_STARSHIP_BINARY"
    state_mark_owned "file:$BB_STARSHIP_BINARY"

    rm -rf "${tmp:?}"
}
