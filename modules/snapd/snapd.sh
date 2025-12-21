# METADATA du module
MODULE_NAME="snapd"
MODULE_PRIORITY=10

snapd_install() {
    apt_wrapper install -y snapd
}


snapd_upgrade() {
    apt_wrapper update -y && upgrade --only-upgrade -y snapd
}