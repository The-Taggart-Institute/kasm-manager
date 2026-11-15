resource "aws_instance" "kasm-worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.kasm.id
  vpc_security_group_ids = [aws_security_group.kasm-worker.id]
  key_name               = aws_key_pair.kasm.key_name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.yml", {
    admin_username = var.admin_username
    public_key     = tls_private_key.kasm.public_key_openssh
  })

  tags = {
    Name = "kasm-worker-${count.index}"
  }
}

output "worker_private_ips" {
  value = aws_instance.kasm-worker[*].private_ip
}
output "worker_public_ips" {
  value = aws_instance.kasm-worker[*].public_ip
}
