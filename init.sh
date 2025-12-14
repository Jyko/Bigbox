#!/bin/sh

# Mettre à jour le système
sudo apt update -y && \ 
sudo apt upgrade -y

###############################################
## DEPUIS LA DOCUMENTATION OFFICIELLE DOCKER ##
###############################################

# Remove potential conflicting packages
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1) -y

# Installer la clé GPG officielle de Docker
sudo apt update
sudo apt install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Ajouter le repository Docker
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Installer Docker
sudo apt update && sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Ajouter l'utilisateur au groupe docker
sudo groupadd docker && usermod -aG docker $USER

# Démarrer le service Docker au démarrage du WSL2
sudo systemctl enable docker.service
sudo systemctl enable containerd.service

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