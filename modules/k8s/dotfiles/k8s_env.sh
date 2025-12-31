#!/usr/bin/env bash
# shellcheck shell=bash

# Fichier à ne pas modifier manuellement !
# Sauf si vous savez exactement ce que vous faites

# Exporter explicitement le fichier config pour certains outils un peu facétieux (n'est-ce pas kubectl et kubecolor ?)
export KUBECONFIG="$HOME/.kube/config"