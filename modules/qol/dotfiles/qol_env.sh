#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# Remplacer find par fd par défaut
export FZF_DEFAULT_COMMAND='fd-find --color=always --type f --no-ignore --hidden'
export FZF_DEFAULT_OPTS=" \
    --ansi \
    --bind 'enter:accept,ctrl-e:execute(test -f {1} && ${EDITOR:-vim} +{2} {1})+abort' \
    --border \
    --height=25% \
    --info=inline \
    --layout=reverse \
    --preview='batcat --style=plain --color=always {}' \
    --preview-window=right:50% \
    --prompt='❯ ' \
"