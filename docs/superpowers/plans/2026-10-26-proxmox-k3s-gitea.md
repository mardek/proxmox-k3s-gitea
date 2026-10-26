# Proxmox, K3s, and Gitea Rebuild Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Terraform → Cloud-Init/K3s → Helm/Gitea deployment pipeline on disk.

**Architecture:** Terraform clones three Debian 12 VMs and uploads rendered Cloud-Init snippets. Cloud-Init configures one K3s server and two agents with a shared generated token. Shell scripts check cluster readiness and install the existing Bitnami Gitea chart with persistent local-path storage.

**Tech Stack:** Terraform 1.6+, bpg/proxmox 0.118.0, hashicorp/random 3.7.x, Debian 12 Cloud-Init, K3s, Bash, kubectl, Helm 3, Bitnami Gitea chart 3.2.22.

**Spec:** `docs/superpowers/specs/2026-10-26-proxmox-k3s-gitea-design.md`

## Global Constraints

- Project root: `/Users/mardek/Documents/dev/proxmox-k3s-gitea`.
- Use the existing VM names/addresses: `k3s-control`/`192.168.2.100`, `k3s-worker-1`/`192.168.2.101`, `k3s-worker-2`/`192.168.2.102`.
- Do not use Ansible and do not introduce a different Gitea chart.
- Never hard-code Proxmox credentials, private keys, or application passwords.
- Do not run `terraform apply`, `terraform destroy`, Helm installation, or the Debian installer on the Mac.
- The project is not a Git repository; do not initialize Git or create commits.

---

### Task 1: Debian Terraform installer

**Files:**
- Create: `install-terraform-debian.sh`

**Interfaces:**
- Produces: root-run Debian 12 installer; verifies installation with `terraform version`.

- [ ] **Step 1: Write the installer**

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

source /etc/os-release
if [[ ${ID} != debian || ${VERSION_ID} != 12 ]]; then
  echo "This installer supports Debian 12 only; found ${PRETTY_NAME}." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform
terraform version
```

- [ ] **Step 2: Validate without executing installation**

Run: `bash -n install-terraform-debian.sh`
Expected: exit 0.

---

### Task 2: Terraform VM and Cloud-Init layer

**Files:**
- Create: `01-vms/versions.tf`
- Create: `01-vms/providers.tf`
- Create: `01-vms/variables.tf`
- Create: `01-vms/main.tf`
- Create: `01-vms/outputs.tf`
- Create: `01-vms/terraform.tfvars.example`
- Create: `01-vms/cloud-init/server.yaml.tftpl`
- Create: `01-vms/cloud-init/agent.yaml.tftpl`
- Create: `.gitignore`

**Interfaces:**
- Consumes: Proxmox API credentials through `PROXMOX_VE_API_TOKEN` or `PROXMOX_VE_USERNAME`/`PROXMOX_VE_PASSWORD`; SSH authentication through the user's SSH agent.
- Produces: `vm_ids` and `configured_ipv4_addresses` outputs; Cloud-Init installs K3s using the generated shared token.

- [ ] **Step 1: Create provider and version configuration**

`versions.tf`:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.118.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
```

`providers.tf`:

```hcl
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
```

- [ ] **Step 2: Declare all inputs**

`variables.tf`:

```hcl
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

variable "proxmox_insecure" {
  description = "Skip TLS verification for a self-signed Proxmox certificate"
  type        = bool
  default     = true
}

variable "template_vm_id" {
  description = "Existing Debian 12 Cloud-Init template VM ID"
  type        = number
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
  }

  validation {
    condition     = length([for vm in values(var.vms) : vm if vm.role == "server"]) == 1 && alltrue([for vm in values(var.vms) : contains(["server", "agent"], vm.role)])
    error_message = "Define exactly one server and only agent roles for all other VMs."
  }
}
```

- [ ] **Step 3: Create Cloud-Init templates**

`server.yaml.tftpl`:

```yaml
#cloud-config
hostname: ${hostname}
package_update: true
packages:
  - curl
  - qemu-guest-agent
users:
  - default
  - name: debian
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}
write_files:
  - path: /etc/rancher/k3s/config.yaml
    permissions: "0600"
    content: |
      token: ${k3s_token}
      node-name: ${hostname}
runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
  - [sh, -c, "curl -sfL https://get.k3s.io | sh -"]
```

`agent.yaml.tftpl`:

```yaml
#cloud-config
hostname: ${hostname}
package_update: true
packages:
  - curl
  - qemu-guest-agent
users:
  - default
  - name: debian
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}
write_files:
  - path: /etc/rancher/k3s/config.yaml
    permissions: "0600"
    content: |
      server: https://${server_address}:6443
      token: ${k3s_token}
      node-name: ${hostname}
runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
  - [sh, -c, "for i in $(seq 1 60); do curl -kfs https://${server_address}:6443/ping && break; sleep 5; done; curl -kfs https://${server_address}:6443/ping"]
  - [sh, -c, "curl -sfL https://get.k3s.io | sh -"]
```

- [ ] **Step 4: Create resources and outputs**

`main.tf`:

```hcl
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
```

`outputs.tf`:

```hcl
output "vm_ids" {
  value = { for key, vm in proxmox_virtual_environment_vm.nodes : key => vm.vm_id }
}

output "configured_ipv4_addresses" {
  value = { for key, vm in var.vms : key => vm.address }
}
```

- [ ] **Step 5: Add editable values and exclusions**

`terraform.tfvars.example`:

```hcl
proxmox_endpoint = "https://192.168.2.10:8006/"
proxmox_node     = "pve"
template_vm_id   = 9000
ssh_public_key   = "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY"

proxmox_insecure     = true
proxmox_ssh_username = "root"
datastore_id         = "local-lvm"
snippet_datastore_id = "local"
disk_interface       = "scsi0"
network_bridge       = "vmbr0"
network_gateway      = "192.168.2.1"
network_prefix       = 24
dns_servers          = ["192.168.2.1"]
```

`.gitignore`:

```gitignore
.terraform/
terraform.tfstate
terraform.tfstate.backup
terraform.tfvars
*.tfplan
```

- [ ] **Step 6: Format and validate**

Run:

```bash
terraform -chdir=01-vms fmt
terraform -chdir=01-vms init -backend=false
terraform -chdir=01-vms validate
```

Expected: configuration validates without contacting Proxmox or creating resources.

---

### Task 3: Cluster readiness gate

**Files:**
- Create: `02-kubernetes/wait-for-cluster.sh`

**Interfaces:**
- Consumes: working `KUBECONFIG` or default kubectl context.
- Produces: success only when the expected node count exists and every node is Ready.

- [ ] **Step 1: Write the readiness script**

```bash
#!/usr/bin/env bash
set -euo pipefail

expected_nodes=${1:-3}
timeout_seconds=${2:-600}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi
if [[ ! ${expected_nodes} =~ ^[1-9][0-9]*$ || ! ${timeout_seconds} =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 [expected-node-count] [timeout-seconds]" >&2
  exit 2
fi

deadline=$((SECONDS + timeout_seconds))
while true; do
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ ${node_count} -eq ${expected_nodes} ]]; then
    break
  fi
  if (( SECONDS >= deadline )); then
    echo "Timed out: expected ${expected_nodes} nodes, found ${node_count}" >&2
    kubectl get nodes >&2 || true
    exit 1
  fi
  sleep 5
done

kubectl wait --for=condition=Ready nodes --all --timeout="${timeout_seconds}s"
kubectl get nodes -o wide
```

- [ ] **Step 2: Validate syntax and failure behavior**

Run: `bash -n 02-kubernetes/wait-for-cluster.sh`
Expected: exit 0.

Run: `02-kubernetes/wait-for-cluster.sh 0`
Expected: exit 2 with usage; no cluster mutation.

---

### Task 4: Gitea Helm layer

**Files:**
- Create: `03-gitea/values.yaml`
- Create: `03-gitea/install.sh`

**Interfaces:**
- Consumes: `GITEA_ADMIN_PASSWORD` (required), optional `GITEA_HOST`, working kubectl/Helm context.
- Produces: release `gitea` in namespace `gitea`, chart `bitnami/gitea` version `3.2.22`, with two 5 Gi PVCs.

- [ ] **Step 1: Write chart values**

`values.yaml`:

```yaml
adminUsername: admin
adminEmail: admin@example.com
appName: Gitea
existingSecret: gitea-admin

persistence:
  enabled: true
  storageClass: local-path
  size: 5Gi

service:
  type: ClusterIP

ingress:
  enabled: false
  ingressClassName: traefik
  pathType: Prefix
  path: /
  tls: false

postgresql:
  enabled: true
  auth:
    username: gitea
    database: gitea
  primary:
    persistence:
      enabled: true
      storageClass: local-path
      size: 5Gi
```

- [ ] **Step 2: Write repeatable installer**

`install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for command_name in helm kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required" >&2
    exit 1
  fi
done

if [[ -z ${GITEA_ADMIN_PASSWORD:-} ]]; then
  echo "Set GITEA_ADMIN_PASSWORD before running this script" >&2
  exit 1
fi

kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gitea create secret generic gitea-admin \
  --from-literal=admin-password="${GITEA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset GITEA_ADMIN_PASSWORD

helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo update bitnami

helm_args=(
  upgrade --install gitea bitnami/gitea
  --version 3.2.22
  --namespace gitea
  --values "${script_dir}/values.yaml"
  --wait
  --timeout 10m
)

if [[ -n ${GITEA_HOST:-} ]]; then
  helm_args+=(
    --set "ingress.enabled=true"
    --set "ingress.hostname=${GITEA_HOST}"
    --set "rootURL=http://${GITEA_HOST}/"
  )
fi

helm "${helm_args[@]}"
kubectl -n gitea get pods,pvc,ingress
```

- [ ] **Step 3: Validate locally without a cluster**

Run: `bash -n 03-gitea/install.sh`
Expected: exit 0.

Run, when Helm is available:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo update bitnami
helm template gitea bitnami/gitea --version 3.2.22 --namespace gitea --values 03-gitea/values.yaml >/dev/null
```

Expected: chart renders successfully; nothing is installed.

---

### Task 5: Final deliverable verification

**Files:**
- Verify all files above; no new files.

- [ ] **Step 1: Verify shell syntax**

Run: `bash -n install-terraform-debian.sh 02-kubernetes/wait-for-cluster.sh 03-gitea/install.sh`
Expected: exit 0.

- [ ] **Step 2: Verify Terraform**

Run:

```bash
terraform -chdir=01-vms fmt -check
terraform -chdir=01-vms validate
```

Expected: both exit 0.

- [ ] **Step 3: Verify expected file layout**

Run: `ls -R .`
Expected: installer, spec, plan, five `.tf` files, two Cloud-Init templates, readiness script, and Gitea files are present.

- [ ] **Step 4: Report operational commands without running them**

Document for the user:

```bash
cp 01-vms/terraform.tfvars.example 01-vms/terraform.tfvars
# Edit terraform.tfvars, export Proxmox credentials, and load the SSH key into ssh-agent.
terraform -chdir=01-vms init
terraform -chdir=01-vms plan
terraform -chdir=01-vms apply

02-kubernetes/wait-for-cluster.sh 3 600
GITEA_ADMIN_PASSWORD='choose-a-strong-password' 03-gitea/install.sh
# Optional: GITEA_HOST=gitea.example.com GITEA_ADMIN_PASSWORD='choose-a-strong-password' 03-gitea/install.sh
```

Expected: commands are presented only; no infrastructure or cluster changes are made by verification.
