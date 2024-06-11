resource "azurerm_resource_group" "simphera" {
    name = var.rgname
    location = var.location
}

resource "azurerm_virtual_network" "vnet-001" {
    name = "main_vnet"
    location = var.location
    resource_group_name = var.rgname
    address_space = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet-001" {
    name = "default-node-pool-subnet"
    resource_group_name = var.rgname
    virtual_network_name = azurerm_virtual_network.vnet-001.name
    address_prefixes = [ "10.1.0.0/24" ]
    delegation {
        name = "delegation"

        service_delegation {
        name = "NGINX.NGINXPLUS/nginxDeployments"
        actions = [
            "Microsoft.Network/virtualNetworks/subnets/join/action",
            ]
        }
    }
}

resource "azurerm_public_ip" "pip-001" {
  name                = "ingress-pubip"
  location            = var.location
  resource_group_name = var.rgname
  allocation_method   = "Static"
  #domain_name_label   = var.rgname

}

resource "azurerm_nginx_deployment" "nginx" {
  name                      = "example-nginx"
  resource_group_name       = var.rgname
  sku                       = "publicpreview_Monthly_gmz7xq9ge3py"
  location                  = var.location
  managed_resource_group    = "example"
  diagnose_support_enabled  = true
  automatic_upgrade_channel = "stable"

  frontend_public {
    ip_address = [azurerm_public_ip.pip-001.id]
  }
  network_interface {
    subnet_id = azurerm_subnet.subnet-001.id
  }

  capacity = 20

  email = "user@test.com"
}

resource "azurerm_lb" "lb-001" {
  name                = "ingress-lb"
  location            = var.location
  resource_group_name = var.rgname

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.pip-001.id
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool-001" {
  loadbalancer_id = azurerm_lb.lb-001.id
  name            = "BackEndAddressPool"
}

resource "azurerm_lb_nat_pool" "lbnatpool-001" {
  resource_group_name            = var.rgname
  name                           = "ssh"
  loadbalancer_id                = azurerm_lb.lb-001.id
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_probe" "lbprobe-001" {
  loadbalancer_id = azurerm_lb.lb-001.id
  name            = "http-probe"
  protocol        = "Http"
  request_path    = "/health"
  port            = 8080
}

resource "azurerm_virtual_machine_scale_set" "vmss-001" {
  name                = "mytestscaleset-1"
  location            = var.location
  resource_group_name = var.rgname
  automatic_os_upgrade = true
  upgrade_policy_mode  = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 5
    pause_time_between_batches              = "PT0S"
  }
  health_probe_id = azurerm_lb_probe.lbprobe-001.id
  sku {
    name     = "Standard_F2"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }

  os_profile {
    computer_name_prefix = "testvm"
    admin_username       = "myadmin"
    admin_password = "password123!"
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "TestIPConfiguration"
      primary                                = true
      subnet_id                              = azurerm_subnet.subnet-001.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool-001.id]
      load_balancer_inbound_nat_rules_ids    = [azurerm_lb_nat_pool.lbnatpool-001.id]
    }
  }
}


resource "azurerm_subnet" "subnet-002" {
    name = "execution-nodes-subnet"
    resource_group_name = var.rgname
    virtual_network_name = azurerm_virtual_network.vnet-001.name
    address_prefixes = [ "10.0.32.0/19" ]
}


resource "azurerm_public_ip" "pip-002" {
  name                = "pip-2"
  location            = var.location
  resource_group_name = var.rgname
  allocation_method   = "Static"
  #domain_name_label   = var.rgname
}

resource "azurerm_lb" "lb-002" {
  name                = "lbvmss2"
  location            = var.location
  resource_group_name = var.rgname

  frontend_ip_configuration {
    name                 = "PublicIPAddress2"
    public_ip_address_id = azurerm_public_ip.pip-002.id
  }
}

resource "azurerm_lb_backend_address_pool" "bpepool-002" {
  loadbalancer_id = azurerm_lb.lb-002.id
  name            = "BackEndAddressPool2"
}

resource "azurerm_lb_nat_pool" "lbnatpool-002" {
  resource_group_name            = var.rgname
  name                           = "ssh"
  loadbalancer_id                = azurerm_lb.lb-002.id
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_probe" "lbprobe-002" {
  loadbalancer_id = azurerm_lb.lb-002.id
  name            = "http-probe"
  protocol        = "Http"
  request_path    = "/health"
  port            = 8080
}

resource "azurerm_virtual_machine_scale_set" "vmss-002" {
  name                = "aks-execnodes"
  location            = var.location
  resource_group_name = var.rgname

  # automatic rolling upgrade
  automatic_os_upgrade = true
  upgrade_policy_mode  = "Rolling"

  rolling_upgrade_policy {
    max_batch_instance_percent              = 20
    max_unhealthy_instance_percent          = 20
    max_unhealthy_upgraded_instance_percent = 5
    pause_time_between_batches              = "PT0S"
  }

  # required when using rolling upgrade policy
  health_probe_id = azurerm_lb_probe.lbprobe-002.id

  sku {
    name     = "Standard_F2"
    tier     = "Standard"
    capacity = 2
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun           = 0
    caching       = "ReadWrite"
    create_option = "Empty"
    disk_size_gb  = 10
  }

  os_profile {
    computer_name_prefix = "testvm"
    admin_username       = "myadmin"
    admin_password = "password123!"
  }

  network_profile {
    name    = "terraformnetworkprofile2"
    primary = true

    ip_configuration {
      name                                   = "TestIPConfiguration2"
      primary                                = true
      subnet_id                              = azurerm_subnet.subnet-002.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool-002.id]
      load_balancer_inbound_nat_rules_ids    = [azurerm_lb_nat_pool.lbnatpool-002.id]
    }
  }
}

resource "azurerm_subnet" "subnet-aks" {
    name = "aks-subnet"
    resource_group_name = var.rgname
    virtual_network_name = azurerm_virtual_network.vnet-001.name
    address_prefixes = [ "10.0.64.0./19" ]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "simphera-aks"
  location            = var.location
  resource_group_name = var.rgname
  dns_prefix          = "simphera-aks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.subnet-aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.64.0/19"
    dns_service_ip = "10.0.64.10"
  }
}

resource "kubernetes_service" "nginx" {
  metadata {
    name = "nginx-service"
  }
  spec {
    selector = {
      app = "nginx"
    }
    port {
      port     = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
    namespace = "default"
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "nginx"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:latest"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "azurerm_public_ip" "pip-aks" {
  name                = "aks-pip"
  location            = var.location
  resource_group_name = var.rgname
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "lb-aks" {
  name                = "aks-lb"
  location            = var.location
  resource_group_name = var.rgname
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress3"
    public_ip_address_id = azurerm_public_ip.pip-aks.id
  }
}

