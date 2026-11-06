# shellcheck shell=bash
# shellcheck disable=SC2016 # Format dpkg-query, pas une expansion
#################################################################################
# Simule un poste Ubuntu Desktop déjà utilisé AVANT la Bigbox, exécuté DANS la sandbox.
# L'uninstall ne doit retirer aucun de ces éléments (voir assert_desktop_preserved).
#################################################################################
set -u

if ! timeout 90 sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -qq install htop fzf </dev/null >/dev/null 2>&1; then
    echo "❌ Préinstallation de htop et fzf impossible"
    exit 1
fi

# Fichiers personnels dans des répertoires que la Bigbox utilise aussi
mkdir -p ~/.config/nats/context ~/.local/share/zoxide ~/.config/bat ~/.bigbox-test
echo '{"url":"nats://perso.example:4222"}' > ~/.config/nats/context/perso.json
echo "perso" > ~/.local/share/zoxide/db.zo
echo "--paging=never" > ~/.config/bat/config

# Référence des paquets, pour le rapport des paquets restants
timeout 10 dpkg-query -W -f '${Package}\n' | sort > ~/.bigbox-test/ref-packages.txt
echo "✅ Poste préparé : htop, fzf, contexte NATS, base zoxide et config bat personnels ($(wc -l < ~/.bigbox-test/ref-packages.txt) paquets)"
