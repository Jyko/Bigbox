#!/usr/bin/env bash
# shellcheck shell=bash

# Exporter les variables d'environnement de la Bigbox
export BIGBOX_HOME="{{.BigboxHome}}"

# Charger toutes les configurations des modules installés par la Bigbox
if [ -d "$BIGBOX_HOME" ]; then
    for module in "$BIGBOX_HOME/"*/; do
        for file in "$module"*.sh; do
            [ -r "$file" ] && source "$file"
        done
    done
fi
