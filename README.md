# Proxmox + k3s + Gitea Lab

Personal Kubernetes homelab running on Proxmox VE with k3s, Gitea, and Longhorn storage.

## Architecture

```
Proxmox Host (bao)
├── VM 100: k3s-control   (192.168.2.100) — control plane + etcd
├── VM 101: k3s-worker-1 (192.168.2.101)
├── VM 102: k3s-worker-2 (192.168.2.102)
├── VM 103: k3s-worker-3 (192.168.2.103)
└── VM 9000: debian-12-cloud (template)
```

## Quick Start

### 1. Create VMs from Template

```bash
# On Proxmox host
for id in 100 101 102 103; do
  qm clone 9000 $id --name k3s-node-$id --full
  qm set $id --memory 4096 --cores 4
  qm resize $id scsi0 40G
  qm set $id --ipconfig0 ip=192.168.2.$id/24,gw=192.168.2.1
  qm start $id
done
```

### 2. Install k3s

See [scripts/setup.sh](scripts/setup.sh) for full automated setup.

### 3. Access Gitea

```bash
kubectl port-forward --address 0.0.0.0 svc/gitea-http 3000:3000 -n gitea
```

Then open `http://192.168.2.100:3000`

## Storage

| Backend | Type | Access Mode | Use Case |
|---------|------|-------------|----------|
| local-path | Local disk | RWO | Default, fast, single-node |
| longhorn | Distributed block | RWO/RWX | Replicated across nodes |

## Troubleshooting

### k3s-agent not starting
```bash
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -f
```

### Containerd stuck pulling images
```bash
sudo systemctl restart containerd
sudo systemctl restart k3s-agent
```

### kubeconfig permissions
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config
```

## Destroy Everything

```bash
bash scripts/destroy.sh
```

## Notes

- Debian 12 cloud-init template (VM 9000) used for all nodes
- k3s v1.36.5+k3s1 with containerd runtime
- Traefik ingress controller included by default
- Default StorageClass: local-path
