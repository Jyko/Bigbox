#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# --------------------
# Configuration FZF
# --------------------

# Remplacer find par fd par défaut
export FZF_DEFAULT_COMMAND='fd-find --color=always --type f --no-ignore --hidden'
export FZF_DEFAULT_OPTS=" \
    --ansi \
    --bind 'enter:accept,ctrl-e:execute(test -f {1} && ${EDITOR:-vim} +{2} {1})+abort,tab:toggle-preview' \
    --border \
    --height=25% \
    --info=inline \
    --layout=reverse \
    --preview='batcat --style=plain --color=always {}' \
    --preview-window=right:70%:wrap:hidden \
    --prompt='❯ '
"

# --------------------
# Configuration Zoxide
# --------------------

# Ajouter .local/bin au PATH pour Zoxide et tout autre outils faisant une installation minimale de scope utilisateur
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$PATH:$HOME/.local/bin" ;;
esac

# Configurer la fuzzy-search de 'zi' et du keybind 'ctrl+g'
# Toujours exporter les variables AVANT le script d'init de Zoxide
export _ZO_FZF_OPTS=" \
    --ansi \
    --bind 'enter:accept,ctrl-e:execute(test -f {1} && ${EDITOR:-vim} +{2} {1})+abort,tab:toggle-preview' \
    --border \
    --delimiter='\t' \
    --nth=2 \
    --height=50% \
    --info=inline \
    --layout=reverse \
    --preview='eza --color=always --icons --group-directories-first {2}' \
    --preview-window=right:70%:wrap:hidden \
    --prompt='❯ ' \
"

# Désactiver le warning qui alerte sur le fait que l'eval n'est pas la dernière instruction du .bashrc
# On sait, on assume, çà ne pose pas de soucis.
export _ZO_DOCTOR=0

eval "$(zoxide init bash)"


