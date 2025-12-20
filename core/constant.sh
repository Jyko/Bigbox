BB_ALLOWED_ACTIONS=(
  help
  install
  uninstall
  upgrade
  version
)

# Répertoire des modules de la BigBox
BB_MOD_DIR="$SCRIPT_DIR/modules"

# Répertoire d'installation de la configuration de la BigBox
BB_CFG_DIR="$HOME/.config/bigbox"
BB_CFG_MAIN_DOTFILE="$BB_CFG_DIR/bigbox.sh"

# KUBERNETES
BB_K8S_CONFIG_DIR=$HOME/.kube
BB_K8S_CONTEXT=bigbox
BB_K8S_NAMESPACE=bigbox