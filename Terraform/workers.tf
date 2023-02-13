resource "azurerm_linux_virtual_machine" "kasm-worker" {
  count                           = 2
  name                            = "kasm-worker-${count.index}"
  location                        = "westus2"
  resource_group_name             = azurerm_resource_group.kasm.name
  network_interface_ids           = [azurerm_network_interface.kasm-worker[count.index].id]
  size                            = "Standard_D2s_v3"
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
    publisher = "ntegralinc1586961136942"
    offer     = "ntg_ubuntu_22_04_docker"
    sku       = "ntg_ubuntu_22_04_docker"
    version   = "latest"
  }

  plan {
    name      = "ntg_ubuntu_22_04_docker"
    publisher = "ntegralinc1586961136942"
    product   = "ntg_ubuntu_22_04_docker"
  }

}

resource "azurerm_network_interface" "kasm-worker" {
  count               = 2
  name                = "kasm-worker-${count.index}"
  location            = "westus2"
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