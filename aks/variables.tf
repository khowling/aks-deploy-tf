variable "dns_prefix" {}
variable cluster_name {}
variable resource_group {}


# AKS needs a SP to allow it to configure LoadBalancers etc
variable "client_id" {}
variable "client_secret" {}
variable "agent_count" {
    default = 1
}
variable "ssh_public_key" {
    default = "~/.ssh/id_rsa.pub"
}
variable log_analytics_workspace_name {
    default = "khLogAnalyticsWorkspace"
}
# refer https://azure.microsoft.com/pricing/details/monitor/ for log analytics pricing 
variable log_analytics_workspace_sku {
    default = "PerGB2018"
}
variable "tags" {
  type = "map"

  default = {
    source = "terraform"
  }
}