#!/bin/bash
sudo apt update
sudo apt install -y letsencrypt
sudo certbot certonly
docker image pull taggarttech/tti-kasm-terminal
docker image pull taggarttech/tti-kasm-kali

