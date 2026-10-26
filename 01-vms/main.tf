locals {
  server = one([for vm in values(var.vms) : vm if vm.role == "server"])
}

resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  for_each = var.vms

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${each.value.name}-cloud-init.yaml"
    data = templatefile(
      "${path.module}/cloud-init/${each.value.role}.yaml.tftpl",
      {
        hostname       = each.value.name
        ssh_public_key = trimspace(var.ssh_public_key)
        k3s_token      = random_password.k3s_token.result
        server_address = local.server.address
      }
    )
  }
}

resource "proxmox_virtual_environment_vm" "nodes" {
  for_each = var.vms

  name            = each.value.name
  node_name       = var.proxmox_node
  vm_id           = each.value.vm_id
  description     = "Managed by Terraform; K3s ${each.value.role}"
  tags            = ["terraform", "k3s"]
  on_boot         = true
  stop_on_destroy = true

  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = 3
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = var.disk_interface
    size         = each.value.disk_size
  }

  initialization {
    datastore_id = var.datastore_id
    dns {
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${each.value.address}/${var.network_prefix}"
        gateway = var.network_gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_init[each.key].id
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }
}
