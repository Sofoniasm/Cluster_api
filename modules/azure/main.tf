variable "location" { type = string }
variable "vnet_cidr" { type = string }
variable "subnet_cidr" { type = string }

resource "random_pet" "rg" {}

resource "azurerm_resource_group" "this" {
  name     = "capi-${random_pet.rg.id}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "capi-${random_pet.rg.id}-vnet"
  address_space       = [var.vnet_cidr]
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "this" {
  name                 = "capi-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_cidr]
}

output "resource_group" { value = azurerm_resource_group.this.name }
output "subnet_id" { value = azurerm_subnet.this.id }
