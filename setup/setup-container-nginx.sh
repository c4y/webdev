#!/usr/bin/bash


#====================================================================
# Pakete installieren
#====================================================================
apt update
apt -y install net-tools bridge-utils ca-certificates curl unzip
install -m 0755 -d /etc/apt/keyrings


#====================================================================
# Docker installieren
#====================================================================
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


#====================================================================
# nginx Proxy Manager docker-compose generieren
#====================================================================
sudo bash -c "cat <<EOF > docker-compose.yml 
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF"


#====================================================================
# nginx Proxy Manager starten
#====================================================================
docker compose up -d