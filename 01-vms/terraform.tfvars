proxmox_endpoint = "https://192.168.2.22:8006/"
proxmox_node     = "bao"
template_vm_id   = 9000
ssh_public_key   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGuXcjaFPR1r+UmY97zmJKtPKUrJuCiQFL/NYpRe5Azx root@Debian"

proxmox_insecure     = true
proxmox_ssh_username = "root"
proxmox_ssh_address  = "192.168.2.22"
datastore_id         = "local-lvm"
snippet_datastore_id = "local"
disk_interface       = "scsi0"
network_bridge       = "vmbr0"
network_gateway      = "192.168.2.1"
network_prefix       = 24
dns_servers          = ["192.168.2.1"]
