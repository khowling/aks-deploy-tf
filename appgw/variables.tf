
variable "resource_group" {}
variable "aks_resource_group" {}
variable "appgw_domain_name_label" {}
variable "common_resource_group_name" {}
variable "key_vault_id" {}
variable "keyvault_name" {}
variable "hub_namespace" {}
variable "dd_api_key" {}

variable "app_gateway_subnet_name" {
  description = "AppGw Subnet Name."
  default     = "tf-appgw-subnet"
}
variable "app_gateway_subnet_address_prefix" {
  description = "Containers DNS server IP address."
  default     = "10.0.2.0/24"
}
variable "app_gateway_name" {
  description = "Name of the Application Gateway."
  default = "tf-cluster-appgw"
}
variable "app_gateway_sku" {
  description = "Name of the Application Gateway SKU."
  default = "WAF_v2"
}
variable "ilb_frontend_ip"{
  description = "ILB Frontend IP Address"
  default = "10.240.0.99"
}


variable "tags" {
  type = "map"

  default = {
    source = "terraform"
  }
}
