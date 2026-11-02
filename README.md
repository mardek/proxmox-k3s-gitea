# Proxmox + K3s + Gitea Lab

Homelab infrastructure-as-code: four Debian VMs on Proxmox, K3s bootstrapped via Cloud-Init, Gitea via Helm, Longhorn distributed storage, and Prometheus + Grafana monitoring.

## Lab addresses

In this exercise, `192.168.2.22` is the Proxmox server's primary management address. Use it for the Proxmox web interface, API, and SSH access.

`192.168.2.100` is the K3s control-plane address and the primary access point for lab services exposed through NodePorts or SSH port-forwards. The Kubernetes API also listens here. It is not strictly the “cluster ingress”: in Kubernetes, Ingress refers to HTTP/S routing through a controller such as Traefik.

## Quick Start

Run these commands on the Debian administration VM:

```bash
# Create the VMs, install the platform, and start service access
./deploy
```

Open `http://192.168.2.100:8080` and log in as `admin`. The deployment prompts for the Proxmox API token and Gitea administrator password. Settings are saved in `.proxmox-env` with owner-only permissions and reused on later runs. Missing exports are also appended to existing `.bashrc` and `.zshrc` files.

If VMID `9000` (`debian-12-cloud`) is absent, deployment creates it from the official Debian 12 generic cloud image; an existing template is left untouched.

Use `./deploy --reconfigure` to replace saved credentials and `./deploy --help` for all options. Helm and K9s are reinstalled only when their required versions are missing or different. To report newer upstream releases without upgrading them, run `./deploy --check-updates`; normal deployments do not perform update checks.

### Manage service access

A successful `./deploy` automatically runs `./run start`; access startup is never attempted after a failed deployment step. The base deployment omits the Ruby dashboard until `./deploy-ruby` creates it.

```bash
./run start       # Start all service forwards and the documentation index
./run status      # Check all processes and display their URLs
./run stop        # Stop all port-forwards
./run restart     # Restart all port-forwards
./run foreground  # Optional terminal-bound Gitea-only mode
./run --help      # Manual and environment overrides
```

Open `http://192.168.2.41:8090` for Main Access, which links to every service and embeds the Kubernetes command reference.

`./deploy` asks for `PROXMOX_SSH_ADDRESS` and `CONTROL_PLANE_ADDRESS` when they are not configured and includes them during `--reconfigure`. Main Access and its command examples are generated from these addresses, the discovered administration-VM address (`DOCS_HOST`), and the configured service ports. Set `DOCS_HOST` when automatic discovery should be overridden. No web-page edits are needed when the lab moves to another network.

Port-forwards run as `k3s-access-*` systemd services on `k3s-control`, so they survive SSH logout and restart automatically without leaving orphaned SSH processes. The documentation server keeps its PID and log files in `~/.local/state/proxmox-k3s-gitea/`.

### Prometheus and Grafana

The main deployment installs `kube-prometheus-stack` in the `monitoring` namespace. Open Grafana at `http://192.168.2.100:30090` and log in as `admin`; its initial password matches `GITEA_ADMIN_PASSWORD` unless `GRAFANA_ADMIN_PASSWORD` is set.

Prometheus retains 15 days of node, Pod, container, disk, network, and Longhorn metrics on a 5 Gi Longhorn volume. Node Exporter reports CPU, memory, filesystem, disk I/O, and network usage for every VM. kube-state-metrics reports Kubernetes resource health and container consumption. Grafana includes prebuilt dashboards for cluster and node history, including CPU, memory, disk, network, and Pod usage over selectable time ranges.

To reinstall only monitoring, copy `06-monitoring/` to the control plane and run `sudo ./06-monitoring/install` with `GRAFANA_ADMIN_PASSWORD` set.

### Service access

| Service | Address or port | Access method |
|---------|-----------------|---------------|
| Service index and command reference | `http://192.168.2.41:8090` | Local web server started by `./run start` |
| Proxmox | `https://192.168.2.22:8006` | Direct web interface |
| Gitea | `http://192.168.2.100:8080` | Start with `./run start` |
| Ruby build dashboard | `http://192.168.2.100:30080` | Start with `./run start` after `./deploy-ruby` |
| Grafana | `http://192.168.2.100:30090` | NodePort or managed port-forward |
| Kubernetes API | `192.168.2.100:6443` | Administrative access with kubeconfig |
| Prometheus | `http://192.168.2.100:9090` | Start with `./run start` |
| Longhorn UI | `http://192.168.2.100:8081` | Start with `./run start` |

The service index links to every web interface and to `kubernetes-commands.html`. It is served from `docs/index.html` on the administration VM.

### Deploy the Ruby build lab

After starting Gitea access with `./run start`:

```bash
./deploy-ruby
```

The script requests the internal Gitea URL, repository name, Actions runner registration token, and release publishing token. Use `http://gitea.gitea.svc.cluster.local` and `admin/ruby` for this lab. Settings are saved in `.ruby-build.env`; run `./deploy-ruby --reconfigure` after rotating credentials.

All three Gentoo builder Pods and runners remain online. Each deployment randomly selects one worker for the initial build, avoiding three simultaneous compilations; Gitea can schedule subsequent jobs across all runners. Builds compile and test Ruby as an unprivileged user, publish releases to Gitea, and send metrics to `http://192.168.2.100:30080`. See [the Ruby builder guide](05-ruby-build/README.md) for token setup and monitoring.

### Monitor and diagnose

```bash
./monitor                  # Live nodes, Pods, Services, PVs, PVCs, and logs
./monitor --interval 10    # Refresh every ten seconds
./monitor --once           # Fetch one snapshot
./monitor --compiler       # Follow the active Ruby compilation log
./diagnose                 # Full checks plus a ZIP archive in /tmp
```

The monitor displays recent K3s logs from the control plane and all workers, plus the latest Ruby builder logs. Diagnostics are saved as `/tmp/k3s-diagnostics-<timestamp>.zip`; the `zip` package is required on the administration VM.

## Repository Layout

| Path | Purpose |
|------|---------|
| `01-vms/` | Terraform: Proxmox VMs + Cloud-Init |
| `02-kubernetes/` | Cluster readiness, Helm + K9s install |
| `03-gitea/` | Gitea Helm deployment |
| `04-longhorn/` | Longhorn distributed storage |
| `05-ruby-build/` | Gentoo Ruby builders, Gitea runners, and metrics dashboard |
| `06-monitoring/` | Prometheus history and Grafana dashboards |
| `deploy` | One-shot deploy from scratch |
| `deploy-ruby` | Deploy three Ruby builders and the metrics dashboard |
| `destroy` | Complete teardown |
| `destroy-ruby` | Remove Ruby builders, dashboard data, and saved variables |
| `diagnose` | Health check all layers |
| `run` | Port-forward to access Gitea |
| `install-terraform-debian` | Install Terraform on Debian 12 |
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

- [Deployment and cluster architecture](docs/deployment-cluster-architecture.md) — VM topology, Gitea vs. Ruby workloads, Pod/PV/PVC storage, and network access diagrams
- [Proxmox-K3s-Gitea Design](docs/superpowers/specs/2026-10-26-proxmox-k3s-gitea-design.md)
- [Longhorn RWX Design](docs/superpowers/specs/2026-10-26-longhorn-rwx-design.md)
- [Implementation Plan](docs/superpowers/plans/2026-10-26-proxmox-k3s-gitea.md)
