variable "eventhub_name" {}
variable "keyvault_name" {}
variable "tenant_id" {}
variable "location" {}
variable "common_resource_group" {}
variable "keyvault_access_object_id" {}

resource "azurerm_eventhub_namespace" "common" {
  name                = var.eventhub_name
  location            = var.common_resource_group.location
  resource_group_name = var.common_resource_group.name
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventhub" "eventhub" {
  name                = "OrderEvent"
  namespace_name      = azurerm_eventhub_namespace.common.name
  resource_group_name = var.common_resource_group.name
  partition_count     = 2
  message_retention   = 1
}

resource "azurerm_key_vault" "common" {
  name                        = var.keyvault_name
  location                    = var.common_resource_group.location
  resource_group_name         = var.common_resource_group.name
  enabled_for_disk_encryption = true
  tenant_id                   = var.tenant_id
  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.keyvault_access_object_id

    certificate_permissions = [
        "create",  
        "get", 
        "getissuers", 
        "list", 
        "listissuers", 
        "managecontacts", 
        "manageissuers", 
        "setissuers",
        "update",
        "delete"
    ]

    key_permissions = [
      "get",
      "list",
      "update",
      "create",
    ]

    secret_permissions = [
      "get",
      "list",
      "set",
      "delete",
    ]
  }
}

resource "azurerm_key_vault_secret" "eventhub_primary_connection_string" {
  name         = "eventhub-primary-connection-string"
  value        = azurerm_eventhub_namespace.common.default_primary_connection_string
  key_vault_id = azurerm_key_vault.common.id
}

resource "azurerm_key_vault_secret" "eventhub_primary_access_key" {
  name         = "eventhub-primary-access-key"
  value        = azurerm_eventhub_namespace.common.default_primary_key
  key_vault_id = azurerm_key_vault.common.id
}

output "eventhub_namespace_name" {
  depends_on = [azurerm_eventhub_namespace.common]
  value = azurerm_eventhub_namespace.common.name
}

output "key_vault_id" {
  depends_on = [azurerm_key_vault.common]
  value = azurerm_key_vault.common.id
}
