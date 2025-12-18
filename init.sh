#!/bin/sh

# Mettre à jour le système
sudo apt update -y && \ 
sudo apt upgrade -y

###############################################
## DEPUIS LA DOCUMENTATION OFFICIELLE DOCKER ##
###############################################

# Nettoyer les anciennes installations de Docker et consorts
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1) -y


# Tester Docker
docker info

##################
# POSTGRESQL CLI #
##################

sudo apt install postgresql-client-17 -y

# Tester Postgresql CLI
psql --version

############
# NATS CLI #
############

# Installer GoLang et compiler NATS-CLI
sudo apt install golang -y && \
go install github.com/nats-io/natscli/nats@latest

# Ajouter les binaires GoLang au PATH
echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc

# Tester NATS-CLI
nats --version

############
# SSH KEYS #
############

sudo ssh-keygen -t ed25519 -f ~/.ssh/sftp_key -C "SFTP KEY" -N "" -y

#######
# K3S #
#######

curl -sfL https://get.k3s.io | sh -

# Ajouter la configuration du serveur k3s local à la configuration kube potentiellement déjà existante
mkdir -p ~/.kube && \
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/k3s.yaml && \
sudo chown $USER:$USER ~/.kube/k3s.yaml && \
chmod 600 ~/.kube/k3s.yaml

# Fusionner les configurations kubectl
export KUBECONFIG=~/.kube/config:~/.kube/k3s.yaml && \
kubectl config view --merge --flatten > ~/.kube/config && \
unset KUBECONFIG

# Renommer le contexte
sudo kubectl config rename-context default k3s-local

########
# Helm #
########

sudo snap install helm --classic