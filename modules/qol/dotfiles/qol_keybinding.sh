#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# --------------------
# Keybinds de FZF
# --------------------
# Raccourcis standard de fzf
if [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
  source /usr/share/doc/fzf/examples/key-bindings.bash
fi

# --------------------
# Function des raccourcis
# --------------------

find_content_in_directory() {
  rg \
      --color=always \
      --column \
      --line-number \
      "" \
  | fzf \
      --delimiter=: \
      --height=50% \
      --nth=3.. \
      --preview 'file={1}; line={2}; 
          start=$(( line > 10 ? line - 10 : 1 ));
          end=$(( line + 10 ));
          batcat --style=plain --color=always --highlight-line "$line" --line-range "$start:$end" --number "$file"'
}

# --------------------
# Keybinds supplémentaires Bigbox
# --------------------
if [[ $- == *i* ]]; then
  # Pour la recherche full-text dans les fichiers du répertoire courant
  bind -x '"\C-f": find_content_in_directory'
  # Pour la navigation intelligente en fuzzy-search
  bind -x '"\C-g": zi'
fi