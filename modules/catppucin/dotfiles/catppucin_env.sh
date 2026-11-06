#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# Changer le thème de ls, eza, tree, dir, fd, fzf, ripgrep ...
LS_COLORS="$(vivid generate catppuccin-mocha)"
export LS_COLORS