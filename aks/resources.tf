/*
resource "azurerm_log_analytics_workspace" "la_workspace" {
    name                = var.log_analytics_workspace_name
    location            = var.resource_group.location
    resource_group_name = var.resource_group.name
    sku                 = var.log_analytics_workspace_sku
}

resource "azurerm_log_analytics_solution" "la_ContainerInsights" {
    solution_name         = "ContainerInsights"
    location              = azurerm_log_analytics_workspace.la_workspace.location
    resource_group_name   = var.resource_group.name
    workspace_resource_id = azurerm_log_analytics_workspace.la_workspace.id
    workspace_name        = azurerm_log_analytics_workspace.la_workspace.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/ContainerInsights"
    }
}
*/
resource "azurerm_kubernetes_cluster" "k8s" {
    name                = var.cluster_name
    location            = var.resource_group.location
    resource_group_name = var.resource_group.name
    dns_prefix          = var.dns_prefix

    linux_profile {
        admin_username = "ubuntu"
        ssh_key {
            key_data = "${file("${var.ssh_public_key}")}"
        }
    }

    agent_pool_profile {
        name            = "agentpool"
        count           = var.agent_count
        vm_size         = "Standard_DS1_v2"
        os_type         = "Linux"
        os_disk_size_gb = 30
    }

    service_principal {
        client_id     = "${var.client_id}"
        client_secret = "${var.client_secret}"
    }
/*
    addon_profile {
        oms_agent {
            enabled                    = true
            log_analytics_workspace_id = azurerm_log_analytics_workspace.la_workspace.id
        }
    }
*/
    tags = var.tags
}

output "k8s_resource_group" {
  value = azurerm_kubernetes_cluster.k8s.node_resource_group
}
