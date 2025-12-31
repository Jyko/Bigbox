#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# Raccourcis standard de fzf
if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
  source /usr/share/doc/fzf/examples/key-bindings.bash
fi

# Seulement dans les shells intéractifs
if [[ $- == *i* ]]; then
  bind -x '"\C-f": find_content_in_directory'
fi