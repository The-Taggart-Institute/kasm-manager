variable worker_count {
  type = number
  description = "How many workers we want"
  default = 4
}


resource "azurerm_linux_virtual_machine" "kasm-worker" {
  count                           = var.worker_count
  name                            = "kasm-worker-${count.index}"
  location                        = var.region
  resource_group_name             = azurerm_resource_group.kasm.name
  network_interface_ids           = [azurerm_network_interface.kasm-worker[count.index].id]
  size                            = "Standard_B2s"
  computer_name                   = "kasm-worker"
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  os_disk {
    name                 = "kasm-worker-${count.index}-osdisk"
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

}

resource "azurerm_network_interface" "kasm-worker" {
  count               = var.worker_count
  name                = "kasm-worker-${count.index}"
  location            = var.region
  resource_group_name = azurerm_resource_group.kasm.name

  ip_configuration {
    name                          = "kasm-worker-${count.index}-ip"
    subnet_id                     = azurerm_subnet.kasm-internal.id
    private_ip_address_allocation = "Dynamic"
  }
}

output "worker_private_ips" {
  value = [for i in azurerm_network_interface.kasm-worker : i.private_ip_address]
}