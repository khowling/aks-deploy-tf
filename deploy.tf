
provider "azurerm" {
    version = "~>1.18"
}

terraform {
    backend "azurerm" {}
}


variable "location" {
    default = "West Europe"
}
variable "aks_sp_client_id" {}
variable "aks_sp_client_secret" {}
variable "deployment_name" {}
variable "current_azid" {}
variable "dd_api_key" {}


locals {
    common_resource_group_name = "${terraform.workspace}-common"
    keyvault_name = "ehn-vlt-${terraform.workspace}"
    eventhub_name = "fntm-ehn-${terraform.workspace}"
}


data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "k8s" {
    name     = "${var.deployment_name}"
    location = "${var.location}"
}


resource "azurerm_resource_group" "common" {
  name     = "${local.common_resource_group_name}"
  location = "${var.location}"
}

module "kubernetes" {
  source         = "./aks"
  client_id      = var.aks_sp_client_id
  client_secret  = var.aks_sp_client_secret
  cluster_name   = var.deployment_name
  resource_group = azurerm_resource_group.k8s
  dns_prefix     = var.deployment_name
  agent_count    = 3
}

module "eventhub" {
  source                    = "./eventhub"
  keyvault_name             = local.keyvault_name
  eventhub_name             = local.eventhub_name
  keyvault_access_object_id = var.current_azid
  location                  = var.location
  common_resource_group     = azurerm_resource_group.common
  tenant_id                 = data.azurerm_client_config.current.tenant_id
}


module "appgw" {
  source                     = "./appgw"
  keyvault_name              = local.keyvault_name
  key_vault_id               = module.eventhub.key_vault_id
  hub_namespace              = module.eventhub.eventhub_namespace_name
  resource_group             = azurerm_resource_group.k8s
  aks_resource_group         = module.kubernetes.k8s_resource_group
  common_resource_group_name = azurerm_resource_group.common.name
  appgw_domain_name_label    = var.deployment_name
  dd_api_key                 = var.dd_api_key
}
