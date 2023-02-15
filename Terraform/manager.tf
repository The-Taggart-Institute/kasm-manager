
resource "azurerm_linux_virtual_machine" "kasm-manager" {
  name                            = "kasm-manager"
  location                        = "westus2"
  resource_group_name             = azurerm_resource_group.kasm.name
  network_interface_ids           = [azurerm_network_interface.kasm-manager.id]
  size                            = "Standard_D4s_v3"
  computer_name                   = "kasm-manager"
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  os_disk {
    name                 = "kasm-manager-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 50
  }


  source_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.admin_username
      password = var.admin_password
      host     = self.public_ip_address
    }
    inline = [
      "git clone https://github.com/The-Taggart-Institute/kasm-manager",
    ]
  }
}

resource "azurerm_network_interface" "kasm-manager" {
  name                = "kasm-manager"
  location            = "westus2"
  resource_group_name = azurerm_resource_group.kasm.name

  ip_configuration {
    name                          = "kasm-internal"
    subnet_id                     = azurerm_subnet.kasm-internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.kasm-manager.id
  }
}

resource "azurerm_network_security_group" "kasm-manager" {
  name                = "kasm-manager-nsg"
  location            = "westus2"
  resource_group_name = azurerm_resource_group.kasm.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_source_address
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6900-7000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-http"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "kasm-manager" {
  network_interface_id      = azurerm_network_interface.kasm-manager.id
  network_security_group_id = azurerm_network_security_group.kasm-manager.id
}

resource "azurerm_public_ip" "kasm-manager" {
  name                = "kasm-manager-public-ip"
  location            = "westus2"
  resource_group_name = azurerm_resource_group.kasm.name
  allocation_method   = "Dynamic"
}

output "manager_ip" {
  value       = azurerm_linux_virtual_machine.kasm-manager.public_ip_address
  sensitive   = false
  description = "Manager IP"
}
