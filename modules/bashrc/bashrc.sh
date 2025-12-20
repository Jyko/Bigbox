# METADATA du module
MODULE_NAME="bashrc"
MODULE_PRIORITY=9000 # Over 9000 ! Le dernier à devoir passer avec le source .bashrc

bashrc_install() {

    cp "$HOME/.bashrc" "$HOME/bigbox_install_bashrc.bak"
    source_file "$BB_CFG_MAIN_DOTFILE" "$HOME/.bashrc"

    source "$HOME/.bashrc"

}

#  TODO: Supprimer le source dans le .bashrc du $USER
bashrc_uninstall() {

    cp "$HOME/.bashrc" "$HOME/bigbox_uninstall_bashrc.bak"
    unsource_file "$BB_CFG_MAIN_DOTFILE" "$HOME/.bashrc"

    source "$HOME/.bashrc"

}

# Pas besoin normalement
# bashrc_upgrade() { }