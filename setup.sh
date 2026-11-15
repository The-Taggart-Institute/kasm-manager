#!/bin/bash
# Change this
DOMAIN=lab.taggart-tech.com

sudo apt update
sudo apt install -y certbot
sudo certbot certonly --manual --preferred-challenges dns -d "*.$DOMAIN" -d "$DOMAIN"

# kubeconfig for non-root CLI use, if not already installed by Ansible
if [ ! -f ~/.kube/config ]; then
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown "$(id -u):$(id -g)" ~/.kube/config
    chmod 600 ~/.kube/config
fi

sudo k3s kubectl create namespace kasm
sudo k3s kubectl -n kasm create secret tls kasm-wildcard-tls \
  --cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem \
  --key=/etc/letsencrypt/live/$DOMAIN/privkey.pem
