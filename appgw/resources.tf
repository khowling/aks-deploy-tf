# # Locals block for hardcoded names. 
locals {
    backend_address_pool_name      = "${var.app_gateway_name}-beap"
    frontend_port_name             = "${var.app_gateway_name}-feport"
    frontend_ip_configuration_name = "${var.app_gateway_name}-feip"
    http_setting_name              = "${var.app_gateway_name}-be-htst"
    listener_name                  = "${var.app_gateway_name}-httplstn"
    request_routing_rule_name      = "${var.app_gateway_name}-rqrt"
}

resource "azurerm_key_vault_certificate" "frontend" {
  name         = var.appgw_domain_name_label
  key_vault_id = var.key_vault_id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Server Authentication = 1.3.6.1.5.5.7.3.1
      # Client Authentication = 1.3.6.1.5.5.7.3.2
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject_alternative_names {
        dns_names = [ "${var.appgw_domain_name_label}" ]
      }

      subject            = "CN=${var.appgw_domain_name_label}"
      validity_in_months = 12
    }
  }
}

# Download newly created certificate from keyvault in a format that can be used with appgw
resource "null_resource" "b64_cert_pfx" {
  triggers = {
    "version": azurerm_key_vault_certificate.frontend.version
  }
  provisioner "local-exec" {
    command = "rm b64_cert_${azurerm_key_vault_certificate.frontend.version}.pfx; az keyvault secret download --vault-name ${var.keyvault_name} --name ${azurerm_key_vault_certificate.frontend.name} --file b64_cert_${azurerm_key_vault_certificate.frontend.version}.pfx"
  }
  depends_on = ["azurerm_key_vault_certificate.frontend"]
}

# Workarout to sync file creation, otherwise apply will fail on appgw creation with file does not exist
data "local_file" "b64_cert_pfx" {
  filename = "b64_cert_${azurerm_key_vault_certificate.frontend.version}.pfx"

  depends_on = ["null_resource.b64_cert_pfx"]
}

# Obtain the VNET name that was created by the AKS cluster,, to allow us to create a new subnet for appgw
resource "null_resource" "aks_vnet_name" {
  
  provisioner "local-exec" {
    command = "az network vnet list -g ${var.aks_resource_group} --query '[0].name' --output tsv | tr -d '\n' > ${var.aks_resource_group}_vnet_name.txt"
  }
}

data "azurerm_virtual_network" "aksvnet" {
   name                = file("${var.aks_resource_group}_vnet_name.txt")
   resource_group_name = var.aks_resource_group

   depends_on = ["null_resource.aks_vnet_name"]
 }


 resource "azurerm_subnet" "appgwsubnet" {
   name                 = var.app_gateway_subnet_name
   virtual_network_name = data.azurerm_virtual_network.aksvnet.name
   resource_group_name  = var.aks_resource_group
   address_prefix       = var.app_gateway_subnet_address_prefix
 }

 # Public Ip 
 resource "azurerm_public_ip" "appgw_public_ip" {
   name                         = "${var.app_gateway_name}_ip"
   location                     = var.resource_group.location
   resource_group_name          = var.resource_group.name
   allocation_method            = "Static"
   sku                          = "Standard"
   domain_name_label            = var.appgw_domain_name_label

   tags = var.tags
 }


resource "azurerm_application_gateway" "network" {
  name                = var.app_gateway_name
  resource_group_name = var.resource_group.name
  location            = var.resource_group.location

  sku {
    name     = var.app_gateway_sku
    tier     = var.app_gateway_sku
    capacity = 2
  }

  ssl_certificate {
      name = var.appgw_domain_name_label
      data = data.local_file.b64_cert_pfx.content
      password = ""
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.appgwsubnet.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw_public_ip.id
  }

  backend_address_pool {
    name = "${local.backend_address_pool_name}"
    ip_addresses = [ "${var.ilb_frontend_ip}" ]
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 1
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Https"
    ssl_certificate_name           = var.appgw_domain_name_label
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  tags = var.tags

  depends_on = ["data.local_file.b64_cert_pfx", "azurerm_subnet.appgwsubnet", "azurerm_public_ip.appgw_public_ip"]
}

data "azurerm_eventhub_namespace" "hub_namespace" {
  name                = var.hub_namespace
  resource_group_name = var.common_resource_group_name
}

resource "azurerm_eventhub" "appgw_diags" {
  name                = "appgw_diags"
  namespace_name      = data.azurerm_eventhub_namespace.hub_namespace.name
  resource_group_name = var.common_resource_group_name
  partition_count     = 2
  message_retention   = 1
}

resource "azurerm_eventhub_namespace_authorization_rule" "appgw_diags" {
  name                = "appgw_diags"
  namespace_name      = data.azurerm_eventhub_namespace.hub_namespace.name
  resource_group_name = var.common_resource_group_name

  listen = true
  send   = true
  manage = true
}

resource "azurerm_monitor_diagnostic_setting" "appgw_diags" {
  name               = "appgw_diags"
  target_resource_id = azurerm_application_gateway.network.id
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.appgw_diags.id
  eventhub_name = azurerm_eventhub.appgw_diags.name

  log {
    category = "ApplicationGatewayAccessLog"
    retention_policy {
      enabled = false
    }
  }

  log {
    category = "ApplicationGatewayPerformanceLog"
    retention_policy {
      enabled = false
    }
  }

  log {
    category = "ApplicationGatewayFirewallLog"
    retention_policy {
      enabled = false
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }

  depends_on = [
    "azurerm_eventhub_namespace_authorization_rule.appgw_diags",
    "azurerm_application_gateway.network",
    "azurerm_eventhub.appgw_diags"
  ]
}

resource "random_id" "server" {
  byte_length = 4
}


resource "azurerm_storage_account" "fnstorage" {
  name                     = "fn${random_id.server.dec}"
  resource_group_name      = var.resource_group.name
  location                 = var.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "fndd_release" {
  name                  = "fndd-release"
  resource_group_name      = var.resource_group.name
  storage_account_name  = azurerm_storage_account.fnstorage.name
  container_access_type = "private"
}

data "azurerm_storage_account_sas" "fndd_release" {
  connection_string = "${azurerm_storage_account.fnstorage.primary_connection_string}"
  https_only        = false
  resource_types {
    service   = false
    container = false
    object    = true
  }
  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = formatdate("YYYY-MM-DD", timestamp())
  expiry = formatdate("YYYY-MM-DD", timeadd(timestamp(), "6000h"))

  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
  }
}

resource "azurerm_storage_blob" "fndd_release" {
  name = "datadog-fn.zip"
  resource_group_name    = var.resource_group.name
  storage_account_name   = azurerm_storage_account.fnstorage.name
  storage_container_name = azurerm_storage_container.fndd_release.name
  type   = "block"
  source = "./appgw/datadog_fn.zip"
}


resource "azurerm_app_service_plan" "fnplan" {
  name                = "fn${random_id.server.dec}"
  resource_group_name = var.resource_group.name
  location            = var.resource_group.location
  kind                = "FunctionApp"

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "test" {
  name                      = "fn${random_id.server.dec}"
  resource_group_name       = var.resource_group.name
  location                  = var.resource_group.location
  app_service_plan_id       = "${azurerm_app_service_plan.fnplan.id}"
  storage_connection_string = "${azurerm_storage_account.fnstorage.primary_connection_string}"
  version                   = "~2"
  app_settings = {
    "khcommon_RootManageSharedAccessKey_EVENTHUB": "${data.azurerm_eventhub_namespace.hub_namespace.default_primary_connection_string};EntityPath=${azurerm_eventhub.appgw_diags.name}",
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "FUNCTIONS_EXTENSION_VERSION": "~2",
    "WEBSITE_NODE_DEFAULT_VERSION": "10.14.1",
    "WEBSITE_RUN_FROM_PACKAGE": "https://${azurerm_storage_account.fnstorage.name}.blob.core.windows.net/${azurerm_storage_container.fndd_release.name}/${azurerm_storage_blob.fndd_release.name}${data.azurerm_storage_account_sas.fndd_release.sas}",
    "DD_API_KEY": var.dd_api_key,
    "DD_TAGS": "terraform"
  }
}

