# Deployment and cluster architecture

The Debian administration VM runs Terraform and the deployment scripts. Terraform creates four Debian VMs on Proxmox; Cloud-Init bootstraps K3s, with one control plane and three workers.

```mermaid
flowchart TB
    subgraph Admin["Debian administration VM"]
        Deploy["deploy"]
        Tools["diagnose · monitor · run"]
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

The main deployment also installs Longhorn, Gitea, Prometheus, and Grafana. The three workers host the Gentoo Ruby builders and their Gitea Actions runners.

## Workloads and persistent storage

A **Pod** is a running workload. A **PersistentVolumeClaim (PVC)** is a workload's request for storage. Kubernetes binds that claim to a **PersistentVolume (PV)**, which Longhorn implements as replicated storage. Deleting or recreating a Pod does not delete its PVC, so Gitea repositories, build data, and metrics can survive rescheduling.

```mermaid
flowchart TB
    subgraph GiteaNS["Namespace: gitea"]
        GiteaPod["Gitea Pod<br/>Web UI · Git · Actions API"]
        DatabasePod["PostgreSQL Pod<br/>Gitea database"]
        GiteaPod -->|"SQL"| DatabasePod
        GiteaPod --> GiteaClaim["PVC: gitea<br/>5 Gi"]
        DatabasePod --> DatabaseClaim["PVC: data-gitea-postgresql-0<br/>5 Gi"]
    end

    subgraph RubyNS["Namespace: gentoo-ruby"]
        Builder1["Ruby builder Pod<br/>k3s-worker-1<br/>Gentoo · runner · compiler"]
        Builder2["Ruby builder Pod<br/>k3s-worker-2<br/>Gentoo · runner · compiler"]
        Builder3["Ruby builder Pod<br/>k3s-worker-3<br/>Gentoo · runner · compiler"]
        Dashboard["Ruby dashboard Pod<br/>Build metrics and reports"]
        Builder1 --> Claim1["PVC: 5 Gi"]
        Builder2 --> Claim2["PVC: 5 Gi"]
        Builder3 --> Claim3["PVC: 5 Gi"]
        Dashboard --> DashboardClaim["PVC: ruby-dashboard-data<br/>1 Gi"]
        Builder1 -->|"metrics and reports"| Dashboard
        Builder2 -->|"metrics and reports"| Dashboard
        Builder3 -->|"metrics and reports"| Dashboard
    end

    GiteaClaim --> PV1["PV bound by Longhorn"]
    DatabaseClaim --> PV2["PV bound by Longhorn"]
    Claim1 --> PV3["PV bound by Longhorn"]
    Claim2 --> PV4["PV bound by Longhorn"]
    Claim3 --> PV5["PV bound by Longhorn"]
    DashboardClaim --> PV6["PV bound by Longhorn"]

    PV1 --> Replicas["Longhorn replicas distributed across nodes"]
    PV2 --> Replicas
    PV3 --> Replicas
    PV4 --> Replicas
    PV5 --> Replicas
    PV6 --> Replicas
```

Gitea Pods serve users and automation continuously. Ruby builder Pods are isolated Gentoo environments that compile and test Ruby, publish releases back to Gitea, and upload metrics to their own dashboard. Their compute workloads are separate from Gitea even though they use the same cluster and storage backend.

## Network and service access

```mermaid
flowchart LR
    User["User browser or Git client"]

    subgraph AdminVM["Debian administration VM"]
        MainAccess["Main Access<br/>HTTP 8090"]
    end

    subgraph Control["k3s-control"]
        GiteaForward["systemd port-forward<br/>8080 → Service 80"]
        PromForward["systemd port-forward<br/>9090 → Service 9090"]
        LonghornForward["systemd port-forward<br/>8081 → Service 80"]
        GrafanaForward["systemd port-forward<br/>30090 → Service 80"]
        RubyForward["systemd port-forward<br/>30080 → Service 8080"]
    end

    subgraph Cluster["Kubernetes Services and Pods"]
        GiteaService["Gitea ClusterIP<br/>80"]
        GiteaWorkload["Gitea Pod"]
        PromService["Prometheus ClusterIP<br/>9090"]
        PromWorkload["Prometheus Pod"]
        LonghornService["Longhorn ClusterIP<br/>80"]
        LonghornWorkload["Longhorn UI Pods"]
        GrafanaService["Grafana NodePort<br/>30090"]
        GrafanaWorkload["Grafana Pod"]
        RubyService["Ruby dashboard NodePort<br/>30080"]
        RubyWorkload["Ruby dashboard Pod"]
        Runners["Gitea Actions runners<br/>inside Gentoo builder Pods"]
    end

    User -->|"8090"| MainAccess
    User -->|"8080"| GiteaForward
    User -->|"9090"| PromForward
    User -->|"8081"| LonghornForward
    User -->|"30090"| GrafanaForward
    User -->|"30080"| RubyForward

    GiteaForward --> GiteaService --> GiteaWorkload
    PromForward --> PromService --> PromWorkload
    LonghornForward --> LonghornService --> LonghornWorkload
    GrafanaForward --> GrafanaService --> GrafanaWorkload
    RubyForward --> RubyService --> RubyWorkload
    Runners -->|"internal Service URL"| GiteaService
    GiteaWorkload -->|"jobs"| Runners
```

Gitea, Prometheus, and Longhorn are ClusterIP services exposed to the lab through systemd-managed port-forwards. Grafana and the Ruby dashboard also have NodePorts. Runners use Gitea's internal Service DNS name, so they do not depend on an external port-forward remaining active.
