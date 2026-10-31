# Proxmox + K3s + Gitea Lab

Homelab infrastructure-as-code: four Debian VMs on Proxmox, K3s bootstrapped via Cloud-Init, Gitea via Helm, and Longhorn distributed storage by default.

## Architecture

### Deployment and cluster

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Debian administration VM                                                  │
│                                                                            │
│ deploy.sh ──► Terraform ──► Proxmox VMs                                   │
│     │                                                                      │
│     └── SSH ──► Helm, K9s, Longhorn, and Gitea installation               │
│                                                                            │
│ diagnose.sh: health checks       run.sh: Gitea port-forward                │
└──────────────────────────────────┬─────────────────────────────────────────┘
                                   │ Proxmox API + SSH
                                   ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Proxmox host: bao — 192.168.2.22                                           │
│                                                                            │
│ VM 9000: debian-12-cloud template                                          │
│                                                                            │
│ ┌────────────────────────────────────────────────────────────────────────┐ │
│ │ K3s cluster                                                           │ │
│ │                                                                        │ │
│ │ ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────┐  │ │
│ │ │ VM 100              │  │ VM 101              │  │ VM 102          │  │ │
│ │ │ k3s-control         │  │ k3s-worker-1        │  │ k3s-worker-2    │  │ │
│ │ │ 192.168.2.100       │  │ 192.168.2.101       │  │ 192.168.2.102   │  │ │
│ │ │                     │  │                     │  │                 │  │ │
│ │ │ Kubernetes API      │  │ K3s agent           │  │ K3s agent       │  │ │
│ │ │ Scheduler           │  │ Application pods    │  │ Application pods│  │ │
│ │ │ Helm and K9s        │  │ Longhorn storage    │  │ Longhorn storage│  │ │
│ │ │ Longhorn storage    │  └─────────────────────┘  └─────────────────┘  │ │
│ │ └─────────────────────┘                                                  │ │
│ │                         ┌─────────────────────┐                          │ │
│ │                         │ VM 103              │                          │ │
│ │                         │ k3s-worker-3        │                          │ │
│ │                         │ 192.168.2.103       │                          │ │
│ │                         │ K3s agent           │                          │ │
│ │                         │ Application pods    │                          │ │
│ │                         │ Longhorn storage    │                          │ │
│ │                         └─────────────────────┘                          │ │
│ └────────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────┘

Kubernetes system services:
CoreDNS • Traefik ingress • ServiceLB • metrics-server • local-path provisioner
```

### Applications and distributed storage

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Gitea namespace                                                            │
│                                                                            │
│ Gitea deployment ───────────────► PostgreSQL StatefulSet                   │
│       │                                    │                               │
│       ▼                                    ▼                               │
│  5 Gi PVC                             5 Gi PVC                             │
│       │                                    │                               │
│       └────────────────┬───────────────────┘                               │
│                        ▼                                                   │
│             Longhorn dynamic provisioning                                  │
└────────────────────────┬───────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ Longhorn: managers, CSI drivers, and storage on all four nodes             │
│                                                                            │
│ Each volume has three replicas on separate nodes.                          │
│ The control plane can also hold replicas.                                  │
│                                                                            │
│ Example volume:                                                            │
│   Replica A ──► k3s-worker-1:/var/lib/longhorn/                            │
│   Replica B ──► k3s-worker-2:/var/lib/longhorn/                            │
│   Replica C ──► k3s-worker-3:/var/lib/longhorn/                            │
│                                                                            │
│ StorageClasses:                                                            │
│   longhorn      ReadWriteOnce, three replicas, default                     │
│   longhorn-rwx  ReadWriteMany, three replicas                              │
│   local-path    Single-node storage, not replicated                        │
└────────────────────────────────────────────────────────────────────────────┘

User ──► run.sh SSH port-forward ──► Gitea ClusterIP Service ──► Gitea pod
         http://192.168.2.100:8080

Optional: User ──► Traefik Ingress ──► Gitea Service ──► Gitea pod
```

### Worker failure and recovery

```
Before: three healthy replicas and a Gitea pod on worker 2

  k3s-control ──► worker 1: replica A
       │        worker 2: replica B + Gitea pod
       │        worker 3: replica C
       ▼
  Kubernetes API and scheduler


Worker 2 powered off:

  k3s-control     worker 1        worker 2         worker 3
  Available       Replica A       POWERED OFF      Replica C
                                  Replica B and
                                  Gitea unavailable

  Volume: degraded but usable with two remaining replicas.


After recovery:

  k3s-control detects the failure and reschedules Gitea
                         │
                         ▼
                  Gitea pod on worker 3
                         │
                         ▼
       Longhorn attaches the existing replicated volume

  Repository data is preserved. When worker 2 returns, Longhorn restores
  its replica and the volume returns to a healthy state.
```

## Quick Start

```bash
# 1. Proxmox credentials and SSH key in agent
export PROXMOX_VE_API_TOKEN="root@pam!tokenname=uuid"
ssh-add ~/.ssh/id_ed25519

# 2. Create VMs (Terraform)
cp 01-vms/terraform.tfvars.example 01-vms/terraform.tfvars
# edit 01-vms/terraform.tfvars
01-vms/install-providers.sh
TF_CLI_CONFIG_FILE="$PWD/01-vms/.terraform-provider-mirror/terraform.rc" terraform -chdir=01-vms init
terraform -chdir=01-vms apply

# 3. Full deploy (includes Longhorn + Gitea)
export GITEA_ADMIN_PASSWORD='choose-strong-password'
./deploy.sh

# 4. Access Gitea
./run.sh
```

## Repository Layout

| Path | Purpose |
|------|---------|
| `01-vms/` | Terraform: Proxmox VMs + Cloud-Init |
| `02-kubernetes/` | Cluster readiness, Helm + K9s install |
| `03-gitea/` | Gitea Helm deployment |
| `04-longhorn/` | Longhorn distributed storage |
| `deploy.sh` | One-shot deploy from scratch |
| `destroy.sh` | Complete teardown |
| `diagnose.sh` | Health check all layers |
| `run.sh` | Port-forward to access Gitea |
| `install-terraform-debian.sh` | Install Terraform on Debian 12 |
| `docs/superpowers/` | Implementation plans + design specs |

## Storage

| Class | Backend | Access | Replicas | Default |
|-------|---------|--------|----------|---------|
| `longhorn` | Longhorn | RWO | 3 | Yes |
| `longhorn-rwx` | Longhorn | RWX | 3 | No |
| `local-path` | Host disk | RWO | 1 | No |

## Secrets

- `PROXMOX_VE_API_TOKEN` — environment variable, never committed
- `GITEA_ADMIN_PASSWORD` — environment variable, passed to installer
- K3s token — generated by Terraform `random_password`, stored in state

## Design Docs

- [Proxmox-K3s-Gitea Design](docs/superpowers/specs/2026-10-26-proxmox-k3s-gitea-design.md)
- [Longhorn RWX Design](docs/superpowers/specs/2026-10-26-longhorn-rwx-design.md)
- [Implementation Plan](docs/superpowers/plans/2026-10-26-proxmox-k3s-gitea.md)
