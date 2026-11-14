resource "aws_instance" "kasm-manager" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.xlarge"
  subnet_id              = aws_subnet.kasm.id
  vpc_security_group_ids = [aws_security_group.kasm-manager.id]
  key_name               = aws_key_pair.kasm.key_name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = {
    Name = "kasm-manager"
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = var.admin_username
      private_key = tls_private_key.kasm.private_key_pem
      host        = self.public_ip
    }

    inline = [
      "git clone https://github.com/The-Taggart-Institute/kasm-manager",
    ]
  }
}

output "manager_ip" {
  value       = aws_instance.kasm-manager.public_ip
  description = "Manager IP"
}
