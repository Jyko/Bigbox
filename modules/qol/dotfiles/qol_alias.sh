#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# --------------------
# Function d'alias
# --------------------
find_content_in_directory() {
    rg \
        --color=always \
        --line-number \
        --column "" \
    | fzf \
        --preview "batcat --style=plain --color=always {1} --highlight-line {2}" \
        --delimiter=: \
        --nth=3..
}

# --------------------
# Alias interactifs
# --------------------
if [[ $- == *i* ]]; then

    # eza pour remplacer ls
    alias ls='eza           --color --icons --group-directories-first'
    alias lt='eza   -a      --color --icons --group-directories-first --tree --level=2'
    alias ll='eza   -al     --color --icons --group-directories-first --git --no-permissions --no-user --no-time --no-filesize'
    alias lll='eza  -alo    --color --icons --group-directories-first --git --no-permissions'
    
    # bat pour remplacer cat
    alias bat='batcat'
    alias cat='batcat --style=plain --paging=never'

    # fd pour remplacer find
    alias fd='fd-find'

    # Fuzzy find sur le contenu des fichiers du répertoire actuel
    alias fzf_rg='find_content_in_directory'
    alias vim_rg='find_and_edit_content_in_directory'

fi

