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
sudo pip3 install ansible
ansible-galaxy collection install community.docker
cd Ansible
ansible-playbook -i inventory.yml swarm-manager.yml
sudo docker swarm join-token worker
ansible-playbook -i inventory.yml swarm-worker.yml
cd ..
sudo certbot certonly
sudo docker secret create kasm_cert /etc/letsencrypt/live/$DOMAIN/fullchain.pem
sudo docker secret create kasm_key /etc/letsencrypt/live/$DOMAIN/privkey.pem