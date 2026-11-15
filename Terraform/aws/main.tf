terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
  required_version = ">= 1.3"
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "ssh_source_address" {
  type    = string
  default = "0.0.0.0/0"
}

variable "admin_username" {
  type    = string
  default = "kasm"
}

variable "worker_count" {
  type    = number
  default = 3
}

# SSH key pair generated with the lab; private key saved locally to ssh_key_path
variable "ssh_key_path" {
  type        = string
  default     = "~/.ssh/kasm-lab"
  description = "Local path where the generated private key is written"
}

resource "tls_private_key" "kasm" {
  algorithm = "ED25519"
}

# Newest Ubuntu 26.04 amd64 server AMI (canonical owner 099720109477)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "kasm" {
  key_name   = "kasm-lab"
  public_key = tls_private_key.kasm.public_key_openssh
}

resource "local_file" "kasm-private-key" {
  content         = tls_private_key.kasm.private_key_pem
  filename        = pathexpand(var.ssh_key_path)
  file_permission = "0600"
}

resource "aws_vpc" "kasm" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "kasm"
  }
}

resource "aws_subnet" "kasm" {
  vpc_id                  = aws_vpc.kasm.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "kasm"
  }
}

resource "aws_internet_gateway" "kasm" {
  vpc_id = aws_vpc.kasm.id

  tags = {
    Name = "kasm"
  }
}

resource "aws_route_table" "kasm" {
  vpc_id = aws_vpc.kasm.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kasm.id
  }

  tags = {
    Name = "kasm"
  }
}

resource "aws_route_table_association" "kasm" {
  subnet_id      = aws_subnet.kasm.id
  route_table_id = aws_route_table.kasm.id
}

# Manager security group: SSH from your address, HTTP/HTTPS for the Traefik ingress
resource "aws_security_group" "kasm-manager" {
  name        = "kasm-manager"
  description = "Kasm manager: SSH, HTTP, HTTPS"
  vpc_id      = aws_vpc.kasm.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_source_address]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kasm-manager"
  }
}

# Worker security group: SSH from your address; k3s traffic within the VPC only
resource "aws_security_group" "kasm-worker" {
  name        = "kasm-worker"
  description = "Kasm worker: SSH plus intra-cluster k3s traffic"
  vpc_id      = aws_vpc.kasm.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_source_address]
  }

  ingress {
    description = "k3s (server/agent, flannel, metrics) from the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.kasm.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kasm-worker"
  }
}
