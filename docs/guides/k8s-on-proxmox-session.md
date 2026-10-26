# k3s on Proxmox Session Notes

Session notes from hands-on cluster management covering deployment failures, debugging, and recovery procedures.

## Cluster Lifecycle

### Creation
1. Clone Debian 12 cloud-init template (VM 9000)
2. Resize disks to 32GB+
3. Install k3s server on control
4. Join worker nodes with token
5. Install Helm and Longhorn
6. Deploy Gitea via Helm

### Destruction
```bash
qm stop 100 101 102 103 --skiplock
qm destroy 100 101 102 103
```

## Key Incidents

### PVC Immutable Error
```
spec is immutable after creation except resources.requests and volumeAttributesClassName
```
**Fix**: Delete and recreate PVC (destroys data if reclaim policy is Delete)

### NFS File Locking Failure
```
unable to lock level db at /data/queues/common: resource temporarily unavailable
```
**Root cause**: NFS doesn't support POSIX file locks required by LevelDB
**Fix**: Use single replica or storage backend with proper locking

### Containerd Stuck Pulling
**Symptom**: Pods stuck in ContainerCreating for >10 minutes
**Fix**: Restart containerd and k3s-agent
```bash
sudo systemctl restart containerd
sudo systemctl restart k3s-agent
```

### kubeconfig Permission Issues
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config
```

## Tools Used

- kubectl: CLI for cluster operations
- k9s: Terminal UI for visual management
- Helm: Package manager for Kubernetes
- k3s: Lightweight Kubernetes distribution
