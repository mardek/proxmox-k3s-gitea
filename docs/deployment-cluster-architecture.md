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
