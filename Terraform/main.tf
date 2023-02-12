terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.43.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "ssh_source_address" {
  type = string
}

variable "admin_username" {
  type    = string
  default = "kasm"
}

variable "admin_password" {
  type    = string
  default = "Password1234!"
}

resource "azurerm_resource_group" "kasm" {
  name     = "Kasm"
  location = "westus2"
}

resource "azurerm_virtual_network" "kasm-vnet" {
  name                = "kasm-vnet"
  location            = "westus2"
  resource_group_name = azurerm_resource_group.kasm.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "kasm-internal" {
  name                 = "kasm-internal"
  resource_group_name  = azurerm_resource_group.kasm.name
  virtual_network_name = "kasm-vnet"
  address_prefixes     = ["10.0.2.0/24"]
  depends_on = [
    azurerm_virtual_network.kasm-vnet
  ]
}