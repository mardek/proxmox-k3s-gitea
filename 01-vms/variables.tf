variable "proxmox_endpoint" {
  description = "Proxmox API endpoint, without /api2/json"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node hosting the VMs"
  type        = string
}

variable "proxmox_ssh_username" {
  description = "SSH user allowed to upload snippets"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_address" {
  description = "IP address or FQDN used for SSH to the Proxmox node"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for a self-signed Proxmox certificate"
  type        = bool
  default     = true
}

variable "template_vm_id" {
  description = "Existing Debian 12 Cloud-Init template VM ID"
  type        = number
  default     = 9000
}

variable "datastore_id" {
  description = "Datastore for VM disks and Cloud-Init drives"
  type        = string
  default     = "local-lvm"
}

variable "snippet_datastore_id" {
  description = "Datastore with Snippets content enabled"
  type        = string
  default     = "local"
}

variable "disk_interface" {
  description = "Boot disk interface used by the template"
  type        = string
  default     = "scsi0"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_gateway" {
  type    = string
  default = "192.168.2.1"
}

variable "network_prefix" {
  type    = number
  default = 24
}

variable "dns_servers" {
  type    = list(string)
  default = ["192.168.2.1"]
}

variable "ssh_public_key" {
  description = "Public key added to the debian account"
  type        = string
}

variable "vms" {
  type = map(object({
    vm_id     = number
    name      = string
    role      = string
    address   = string
    cores     = number
    memory    = number
    disk_size = number
  }))

  default = {
    control = {
      vm_id = 100, name = "k3s-control", role = "server", address = "192.168.2.100"
      cores = 2, memory = 4096, disk_size = 40
    }
    worker1 = {
      vm_id = 101, name = "k3s-worker-1", role = "agent", address = "192.168.2.101"
      cores = 2, memory = 4096, disk_size = 40
    }
    worker2 = {
      vm_id = 102, name = "k3s-worker-2", role = "agent", address = "192.168.2.102"
      cores = 2, memory = 4096, disk_size = 40
    }
    worker3 = {
      vm_id = 103, name = "k3s-worker-3", role = "agent", address = "192.168.2.103"
      cores = 2, memory = 4096, disk_size = 40
    }
  }

  validation {
    condition     = length([for vm in values(var.vms) : vm if vm.role == "server"]) == 1 && alltrue([for vm in values(var.vms) : contains(["server", "agent"], vm.role)])
    error_message = "Define exactly one server and only agent roles for all other VMs."
  }
}
