#!/bin/bash
# Change this
DOMAIN=lab.taggart-tech.com
sudo apt update
sudo apt install -y letsencrypt python3-pip sshpass
sudo pip3 install docker rich requests ansible
sudo certbot certonly
docker image pull taggarttech/tti-kasm-terminal
docker image pull taggarttech/tti-kasm-kali
sudo docker secret create kasm_cert /etc/letsencrypt/live/$DOMAIN/fullchain.pem
sudo docker secret create kasm_key /etc/letsencrypt/live/$DOMAIN/privkey.pem
ansible-galaxy collection install community.docker