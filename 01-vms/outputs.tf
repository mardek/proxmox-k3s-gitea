output "vm_ids" {
  value = { for key, vm in proxmox_virtual_environment_vm.nodes : key => vm.vm_id }
}

output "configured_ipv4_addresses" {
  value = { for key, vm in var.vms : key => vm.address }
}
