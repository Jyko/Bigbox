# METADATA du module
MODULE_NAME="snapd"
MODULE_PRIORITY=10

snapd_install() {

    apt_wrapper install -y snapd
    
}

# Snapd ne sera pas désinstallé par la BigBox
# snapd_uninstall() { }

snapd_upgrade() {

    apt_wrapper update -y && upgrade --only-upgrade -y snapd

}