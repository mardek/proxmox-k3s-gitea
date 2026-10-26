#!/bin/bash
set -euo pipefail

# Complete teardown of k3s cluster

echo "=== Uninstalling Gitea ==="
helm uninstall gitea -n gitea --ignore-not-found=true
kubectl delete namespace gitea --ignore-not-found=true

echo "=== Uninstalling Longhorn ==="
helm uninstall longhorn -n longhorn-system --ignore-not-found=true
kubectl delete namespace longhorn-system --ignore-not-found=true

echo "=== Removing CRDs ==="
kubectl get crd | grep longhorn | awk '{print $1}' | xargs -r kubectl delete crd

echo "=== Uninstalling k3s ==="
if command -v k3s-uninstall.sh &>/dev/null; then
  sudo /usr/local/bin/k3s-uninstall.sh
fi

echo "=== Cleaning up ==="
sudo rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet ~/.kube

echo "=== Destroy Proxmox VMs ==="
for id in 100 101 102 103; do
  qm stop $id --skiplock 2>/dev/null || true
  qm destroy $id 2>/dev/null || true
done

echo "=== Teardown Complete ==="