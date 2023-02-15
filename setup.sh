#!/bin/bash
# Change this
DOMAIN=lab.taggart-tech.com

# Docker setup
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
sudo apt update
sudo apt install -y letsencrypt python3-pip sshpass docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo gpasswd -a kasm docker
sudo pip3 install docker rich requests ansible
sudo certbot certonly
docker image pull taggarttech/tti-kasm-terminal
docker image pull taggarttech/tti-kasm-kali
sudo docker secret create kasm_cert /etc/letsencrypt/live/$DOMAIN/fullchain.pem
sudo docker secret create kasm_key /etc/letsencrypt/live/$DOMAIN/privkey.pem
ansible-galaxy collection install community.docker