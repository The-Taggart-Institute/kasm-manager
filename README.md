# Kasm Manager

Frontend for deploying Kasm workspaces using Docker Swarm.

## Summary

This tool is designed to make the management of [Kasm Workspace Images](https://www.kasmweb.com/images) at scale feasible without the proprietary control plane, which limits free use to 5 concurrent sessions.

This tool uses [Docker Swarm](https://docs.docker.com/engine/swarm/) to deploy containers as services across the Swarm. Each Workspace instance is given a unique port, and can be monitored and managed with the `kasm-manager.py` script.

To make managing the Swarm a bit easier, this repository includes an Ansible playbook and inventory file for your node workers.

## Requirements

To get started, you'll need:

* An Ubuntu/Debian server with at least 2 CPUs/2GB RAM, and about 40GB of disk space. The more the better, and these are also the minimum specs for any worker nodes in the Docker Swarm.
* Docker in Swarm Mode.
* A public IP.
* A domain name. The `setup.sh` script will retrieve a `letsencrypt` certificate.


## Setup

* On your chosen Ubuntu server, initiate Swarm Mode with `docker swarm init`. You don't have to worry about setting up the nodes; we'll do that shortly.

### Installation

With your chosen domain pointing to the server's public IP, follow these shell commands:

```shell
git clone https://github.com/The-Taggart-Institute/kasm-manager
cd kasm-manager 
./setup.sh
```

This will install requisite packages and get your SSL certificate set up. It will also add these certificates to Docker secrets for use with our customized Kasm Workspace images. The running workspaces will be able to use your signed cert and key, stored in the secrets `kasm_cert` and `kasm_key`, respectively.

### Ansible

To make the configuration of any swarm worker nodes easier, we've included an Ansible playbook and example inventory file for you. To set up worker nodes, make sure that the correct IPs are listed in the `Ansible/inventory.yml` file. Then:

```shell
# From the repo's top-level
cd Ansible
# Keep this info handy
sudo docker swarm join-token worker
ansible-playbook -i inventory.yml swarm-worker.yml
```

The playbook will ask for the manager IP and the join token for the swarm, which you can copy and paste from the output of the `docker` command above.

It'll take a while, but afterwards your worker nodes will be set up to run Kasm Workspace containers!

### Terraform

For Azure users, a set of Terraform Plans is included to get you started with a Docker Swarm cluster.

In the the `Terraform` folder:

```shell
terraform apply
```

You'll be asked to add a source IP for SSH to the Manager node. This should be your external IP. Once deployed, you'll be able to ssh with the user `kasm` to the public IP reported by the Terraform output.

**Note: This is not free! You will incur Azure charges!**

## Usage

`kasm-manager.py` is the core management tool in this project. It has several subcommands.

* `create -i|--image IMAGE`: Creates a new Workspace instance from one of the named image types. Currently supported are `terminal` and `kali`. Creates the Docker service and shows the randomly-generated password for access. The user is `kasm_user`.
* `list`: Lists all running instances
* `inspect PORT_ID`: Shows details of a running instance. `PORT_ID` is the port number the instance is running on—put another way, the numbers from the output of `list`.
* `destroy PORT_ID`: Removes a running instance identified by `PORT_ID`.
* `prune`: Removes all running instances older than the configured `MAX_SESSION_TIME` in the script. Default is 2 hours.
  * **Note: Make sure your server's clock is set to UTC!**

## Resource Usage/Allocation

By default, each instance takes 2 CPU cores and 2 GB of RAM. Later versions may customize this, but keep these requirements in mind when provisioning worker nodes and considering scale. Just because an instance has access to 2 cores and 2 GB of RAM doesn't mean it always uses that much, but that is the limit for the container.

## Customization

The script and Workspace images are deeply customizable. Review the `CONSTANTS` section of the script for customizable parameters. Also review the `Dockerfiles` folder to see how we customize the base Kasm images and how you might like to change them further.