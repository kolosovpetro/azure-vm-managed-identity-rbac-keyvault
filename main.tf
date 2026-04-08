data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

#################################################################################################################
# LOCALS
#################################################################################################################

locals {
  vnet_cidr      = ["10.10.0.0/24"]
  vm_subnet_cidr = ["10.10.0.0/26"]
  # fw_subnet_cidr      = ["10.10.0.64/26"]
  # bastion_subnet_cidr = ["10.10.0.128/26"]
}

#################################################################################################################
# RESOURCE GROUP
#################################################################################################################

resource "azurerm_resource_group" "public" {
  location = var.location
  name     = "rg-identity-rbac-kv-${var.prefix}"
  tags     = var.tags
}

#################################################################################################################
# VNET AND SUBNET
#################################################################################################################

resource "azurerm_virtual_network" "public" {
  name                = "vnet-${var.prefix}"
  address_space       = local.vnet_cidr
  location            = azurerm_resource_group.public.location
  resource_group_name = azurerm_resource_group.public.name
}

resource "azurerm_subnet" "vm" {
  name                 = "snet-vm-${var.prefix}"
  resource_group_name  = azurerm_resource_group.public.name
  virtual_network_name = azurerm_virtual_network.public.name
  address_prefixes     = local.vm_subnet_cidr
}

# resource "azurerm_subnet" "fw" {
#   name                 = "AzureFirewallSubnet"
#   resource_group_name  = azurerm_resource_group.public.name
#   virtual_network_name = azurerm_virtual_network.public.name
#   address_prefixes     = local.fw_subnet_cidr
# }

# resource "azurerm_subnet" "bastion_snet" {
#   name                 = "AzureBastionSubnet"
#   resource_group_name  = azurerm_resource_group.public.name
#   virtual_network_name = azurerm_virtual_network.public.name
#   address_prefixes     = local.bastion_subnet_cidr
# }

#################################################################################################################
# VIRTUAL MACHINE
#################################################################################################################

module "ubuntu_vm_custom_image_key_auth" {
  source                           = "github.com/kolosovpetro/azure-linux-vm-terraform.git//modules/ubuntu-vm-key-auth-custom-image?ref=master"
  custom_image_resource_group_name = "rg-packer-images-linux"
  custom_image_sku                 = "azure-ubuntu-v6"
  ip_configuration_name            = "ipc-custom-image-key-${var.prefix}"
  network_interface_name           = "nic-custom-image-key-${var.prefix}"
  os_profile_admin_public_key      = file("${path.root}/id_ed25519.pub")
  os_profile_admin_username        = "razumovsky_r"
  os_profile_computer_name         = "vm-custom-image-key-${var.prefix}"
  public_ip_name                   = "pip-custom-image-key-${var.prefix}"
  resource_group_location          = azurerm_resource_group.public.location
  resource_group_name              = azurerm_resource_group.public.name
  storage_os_disk_name             = "osdisk-custom-image-key-${var.prefix}"
  subnet_id                        = azurerm_subnet.vm.id
  vm_name                          = "jumphost-${var.prefix}"
  network_security_group_id        = azurerm_network_security_group.public.id
}

#################################################################################################################
# ROLE ASSIGNMENT TO SYSTEM MANAGED IDENTITY
#################################################################################################################

resource "azurerm_role_assignment" "vm_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = module.ubuntu_vm_custom_image_key_auth.principal_id
}

#################################################################################################################
# KEYVAULT AND SECRETS
#################################################################################################################

resource "azurerm_key_vault" "kv" {
  name                = "kv-${var.prefix}"
  location            = azurerm_resource_group.public.location
  resource_group_name = azurerm_resource_group.public.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true
}

resource "azurerm_role_assignment" "terraform_kv_access" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_for_rbac" {
  depends_on = [
    azurerm_role_assignment.terraform_kv_access
  ]

  create_duration = "120s"
}

resource "azurerm_key_vault_secret" "login" {
  name         = "vm-admin-login"
  value        = "SuperLogin123!"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [time_sleep.wait_for_rbac]
}

resource "azurerm_key_vault_secret" "password" {
  name         = "vm-admin-password"
  value        = "SuperSecretPassword123!"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [time_sleep.wait_for_rbac]
}
