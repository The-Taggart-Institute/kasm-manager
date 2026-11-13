# Kasm Manager

Frontend for deploying Kasm workspaces using Kubernetes (K3s).

## Summary

This tool is designed to make the management of [Kasm Workspace Images](https://www.kasmweb.com/images) at scale feasible without the proprietary control plane, which limits free use to 5 concurrent sessions.

This tool uses [K3s](https://k3s.io/) (a lightweight Kubernetes distribution with a bundled Traefik ingress) to deploy workspace containers. Each instance gets its own subdomain — `https://kasm-<id>.<domain>` — routed through Traefik, which terminates TLS with a single wildcard certificate. Instances can be monitored and managed with the `kasm-manager.py` script.

All state lives in the cluster (passwords in Secrets, instance metadata in Deployment labels), so the CLI is stateless — no local state files.

To make cluster setup easier, this repository includes Ansible playbooks and an inventory file for manager and worker nodes.

## Requirements

To get started, you'll need:

* An Ubuntu/Debian server with at least 2 CPUs/2GB RAM, and about 40GB of disk space. The more the better, and these are also the minimum specs for any worker nodes in the cluster.
* K3s installed (the Ansible playbook handles this).
* A public IP.
* A domain name. The `setup.sh` script retrieves a `letsencrypt` wildcard certificate.

## Setup

### Installation

On the manager node, with your domain's wildcard DNS record pointing to the server's public IP:

```shell
git clone https://github.com/The-Taggart-Institute/kasm-manager
cd kasm-manager
./setup.sh
```

This installs K3s, sets up a kubeconfig for the `kasm` user, and stores your wildcard certificate as a Kubernetes Secret (`kasm-wildcard-tls`) for Traefik to use. If the secret is absent, Traefik falls back to its default self-signed certificate — everything still works, browsers just show a warning.

Before using the CLI, export your domain:

```shell
export KASM_DOMAIN=lab.example.com
```

### Ansible

To configure the manager and worker nodes, list the correct IPs in `Ansible/inventory.yml`, then from the repo's top level:

```shell
cd Ansible
# Install the manager; it will prompt for the manager's IP
ansible-playbook -i inventory.yml k3s-manager.yml
# Keep this handy for joining workers
sudo cat /var/lib/rancher/k3s/server/node-token
# Join the workers; prompts for manager IP and node token
ansible-playbook -i inventory.yml k3s-worker.yml
```

### Terraform

For Azure users, a set of Terraform plans is included to provision the VMs for the cluster.

In the `Terraform` folder:

```shell
terraform apply
```

You'll be asked to add a source IP for SSH to the Manager node. This should be your external IP. Once deployed, you'll be able to ssh with the user `kasm` to the public IP reported by the Terraform output.

**Note: This is not free! You will incur Azure charges!**

## Usage

Install the CLI's Python dependencies with [uv](https://docs.astral.sh/uv/):

```shell
uv sync
```

Then run any command with `uv run python kasm-manager.py <command>`.

* `create -i|--image IMAGE`: Creates a new Workspace instance from one of the named image types. Currently supported are `terminal` and `kali`. Prints the instance URL and the randomly-generated password for access. The user is `kasm_user`.
* `list`: Lists all running instances with their age and URL.
* `inspect ID`: Shows details of a running instance, including its password. `ID` is the instance number shown in the output of `list`.
* `destroy ID`: Removes a running instance identified by `ID`. Fully idempotent — running it twice or against a half-created instance is safe.
* `prune`: Removes all running instances older than the configured `MAX_SESSION_TIME` in the script. Default is 2 hours.

## Resource Usage/Allocation

By default, each instance takes 2 CPU cores and 2 GB of RAM. Later versions may customize this, but keep these requirements in mind when provisioning worker nodes and considering scale. Just because an instance has access to 2 cores and 2 GB of RAM doesn't mean it always uses that much, but that is the limit for the container.

## Customization

The script and Workspace images are deeply customizable. Review the `CONSTANTS` section of the script for customizable parameters. Also review the `Dockerfiles` folder to see how we customize the base Kasm images and how you might like to change them further. After changing an image, rebuild and push it to Docker Hub — instances pull `taggarttech/tti-kasm-terminal:latest` / `tti-kasm-kali:latest`.
