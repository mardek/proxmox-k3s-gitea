# Proxmox + K3s + Gitea Lab

Homelab infrastructure-as-code: four Debian VMs on Proxmox, K3s bootstrapped via Cloud-Init, Gitea via Helm, and Longhorn distributed storage by default.

## Architecture

### Deployment and cluster

```mermaid
flowchart TB
    subgraph Admin["Debian administration VM"]
        Deploy["deploy.sh"]
        Tools["diagnose.sh · run.sh"]
        Deploy --> Terraform["Terraform"]
        Deploy --> SSH["SSH installation"]
    end

    subgraph Proxmox["Proxmox host: bao · 192.168.2.22"]
        Template["VM 9000<br/>Debian 12 Cloud-Init template"]
        subgraph Cluster["K3s cluster"]
            Control["VM 100 · k3s-control<br/>192.168.2.100<br/>Kubernetes API · Scheduler<br/>Helm · K9s · Longhorn"]
            Worker1["VM 101 · k3s-worker-1<br/>192.168.2.101<br/>K3s agent · Pods · Longhorn"]
            Worker2["VM 102 · k3s-worker-2<br/>192.168.2.102<br/>K3s agent · Pods · Longhorn"]
            Worker3["VM 103 · k3s-worker-3<br/>192.168.2.103<br/>K3s agent · Pods · Longhorn"]
        end
    end

    Terraform -->|"Proxmox API"| Template
    Template --> Control
    Template --> Worker1
    Template --> Worker2
    Template --> Worker3
    SSH --> Control
    Control --> Worker1
    Control --> Worker2
    Control --> Worker3

    System["System services<br/>CoreDNS · Traefik · ServiceLB<br/>metrics-server · local-path"]
    Control --- System
```

### Applications and distributed storage

```mermaid
flowchart TB
    subgraph GiteaNS["Gitea namespace"]
        Gitea["Gitea deployment"] -->|"database connection"| PostgreSQL["PostgreSQL StatefulSet"]
        Gitea --> GiteaPVC["5 Gi PVC"]
        PostgreSQL --> DatabasePVC["5 Gi PVC"]
    end

    GiteaPVC --> Provisioner["Longhorn dynamic provisioning"]
    DatabasePVC --> Provisioner

    subgraph Storage["Longhorn storage on all four nodes"]
        Provisioner --> Volume["Persistent volume<br/>Three replicas on separate nodes"]
        Volume --> ReplicaA["Replica A<br/>k3s-worker-1"]
        Volume --> ReplicaB["Replica B<br/>k3s-worker-2"]
        Volume --> ReplicaC["Replica C<br/>k3s-worker-3"]
        ReplicaA --- PathA["/var/lib/longhorn/"]
        ReplicaB --- PathB["/var/lib/longhorn/"]
        ReplicaC --- PathC["/var/lib/longhorn/"]
    end

    User["User"] -->|"http://192.168.2.100:8080"| Forward["run.sh SSH port-forward"]
    Forward --> Service["Gitea ClusterIP Service"]
    Service --> Gitea
    Optional["Optional hostname"] --> Ingress["Traefik Ingress"]
    Ingress --> Service
```

### Worker failure and recovery

```mermaid
flowchart LR
    subgraph Before["Before failure"]
        HealthyControl["k3s-control<br/>Available"]
        HealthyW1["Worker 1<br/>Replica A"]
        HealthyW2["Worker 2<br/>Replica B + Gitea"]
        HealthyW3["Worker 3<br/>Replica C"]
        HealthyControl --> HealthyW1
        HealthyControl --> HealthyW2
        HealthyControl --> HealthyW3
    end

    subgraph Failure["Worker 2 powered off"]
        FailedControl["k3s-control<br/>Available"]
        FailedW1["Worker 1<br/>Replica A available"]
        FailedW2["Worker 2<br/>Unavailable"]
        FailedW3["Worker 3<br/>Replica C available"]
        FailedVolume["Volume degraded<br/>Two replicas remain"]
        FailedControl --> FailedW1
        FailedControl --> FailedW2
        FailedControl --> FailedW3
        FailedW1 --> FailedVolume
        FailedW3 --> FailedVolume
    end

    subgraph Recovery["After recovery"]
        Scheduler["Kubernetes reschedules Gitea"]
        NewPod["Replacement Gitea pod<br/>on worker 3"]
        ExistingData["Longhorn attaches<br/>the existing volume"]
        Scheduler --> NewPod --> ExistingData
    end

    Before --> Failure --> Recovery
```

When worker 2 returns, Longhorn restores its replica and the volume returns to a healthy state. Repository data is preserved throughout this example.

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
