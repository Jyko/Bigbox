#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# Export des binaires GoLang dans le PATH
case ":$PATH:" in
  *":$HOME/go/bin:"*) ;;
  *) export PATH="$PATH:$HOME/go/bin" ;;
esac