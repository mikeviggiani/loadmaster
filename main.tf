resource "azurerm_availability_set" "availability_set" {
  count               = var.is_ha ? 1 : 0      
  name                = "${var.prefix}-avset"
  location            = var.location
  resource_group_name = var.resource_group_name
  managed             = var.av_set_managed
}

#resource "azurerm_public_ip" "public_ip" {
#  name                = "${var.prefix}-lm-ip"
#  location            = var.location
#  resource_group_name = var.resource_group_name
#  allocation_method   = var.allocation_method
#  tags = {
#    for tag in keys(var.public_ip_tags) :
#    tag => var.public_ip_tags[tag]
#  }
#}

resource "azurerm_network_interface" "iface" {
  count               = var.is_ha ? 2 : 1
  name                = "${var.prefix}-${count.index}-interface"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipcon${count.index}"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "ap" {
  count = var.is_ha ? 2 : 0
  network_interface_id    = azurerm_network_interface.iface[count.index].id
  ip_configuration_name   = "ipcon${count.index}"
  backend_address_pool_id = var.is_ha ? azurerm_lb_backend_address_pool.lm_address_pool[0].id : null
}



resource "azurerm_lb" "azure_lb" {
  count = var.is_ha ? 1 : 0
  name                = "${var.prefix}-azure-lb"
  location            = var.location
  resource_group_name = var.resource_group_name

  frontend_ip_configuration {
    name                 = "${var.prefix}IP"
    subnet_id            = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_security_rule" "lm" {
  for_each                    = var.network_security_rules
  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = var.network_security_group.name
}


resource "azurerm_lb_probe" "lb_probes" {
  for_each            = var.is_ha ? var.probes : {}
  resource_group_name = var.resource_group_name
  loadbalancer_id     = azurerm_lb.azure_lb[0].id
  name                = each.value.name
  protocol            = each.value.protocol
  port                = each.value.port
  request_path        = each.value.path
}

resource "azurerm_lb_rule" "lb_rule" {
  for_each                       = var.is_ha ? var.lb_rules : {}
  resource_group_name            = var.resource_group_name
  name                           = each.value.name
  loadbalancer_id                = azurerm_lb.azure_lb[0].id
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  frontend_ip_configuration_name = var.is_ha ? azurerm_lb.azure_lb[0].frontend_ip_configuration[0].name : null

  backend_address_pool_id = azurerm_lb_backend_address_pool.lm_address_pool[0].id
  probe_id                = azurerm_lb_probe.lb_probes[keys(var.probes)[0]].id
}

resource "azurerm_lb_nat_rule" "nat_rule" {
  for_each                       = var.is_ha ? var.nat_rules : {}
  resource_group_name            = var.resource_group_name
  loadbalancer_id                = var.is_ha ? azurerm_lb.azure_lb[0].id : null
  name                           = each.value.name
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  frontend_ip_configuration_name = var.is_ha ? azurerm_lb.azure_lb[0].frontend_ip_configuration[0].name : null
}

resource "azurerm_network_interface_nat_rule_association" "lm" {
  for_each              = var.is_ha ? var.nat_rules : {}
  network_interface_id  = azurerm_network_interface.iface[each.value.iface_index].id
  ip_configuration_name = "ipcon${each.value.iface_index}"
  nat_rule_id           = azurerm_lb_nat_rule.nat_rule[each.key].id
}



resource "azurerm_lb_backend_address_pool" "lm_address_pool" {
  count               = var.is_ha ? 1 : 0
  resource_group_name = var.resource_group_name 
  loadbalancer_id     = var.is_ha ? azurerm_lb.azure_lb[0].id : null
  name                = "${var.prefix}-backendpool"
}

resource "azurerm_linux_virtual_machine" "vms" {
  count                 = var.is_ha ? 2 : 1
  name                  = "${var.prefix}-${count.index}"
  location              = var.location
  resource_group_name   = var.resource_group_name
  network_interface_ids = ["${azurerm_network_interface.iface[count.index].id}"]
  size                  = var.vm_size
  availability_set_id   = var.is_ha ? azurerm_availability_set.availability_set[0].id : null

  os_disk {
    name            = "${var.prefix}${count.index}"
    caching         = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = var.lm_market_details.publisher
    offer     = var.lm_market_details.offer
    sku       = var.lm_market_details.sku
    version   = var.lm_market_details.version
  }

  plan {
    publisher = var.lm_market_details.publisher
    product   = var.lm_market_details.offer
    name      = var.lm_market_details.sku
  }

  admin_username = var.admin_username
  admin_password = var.admin_password

  disable_password_authentication = false
}


