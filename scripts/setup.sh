#!/bin/bash
set -euo pipefail

# Proxmox + k3s + Gitea Setup Script
# Run on k3s-control after all nodes are created and joined

CONTROL_IP="192.168.2.100"
NODES=(101 102 103)

echo "=== Step 1: Install dependencies on all nodes ==="
for ip in "${NODES[@]}"; do
  ssh -o StrictHostKeyChecking=no debian@192.168.2.$ip \
    "sudo apt update && sudo apt install -y open-iscsi nfs-common curl" || true
done

echo "=== Step 2: Configure kubeconfig ==="
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

echo "=== Step 3: Verify cluster ==="
kubectl get nodes

echo "=== Step 4: Install Helm ==="
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3.sh | bash

echo "=== Step 5: Install Longhorn ==="
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultDataPath=/var/lib/longhorn \
  --set persistence.defaultClass=true

echo "=== Step 6: Wait for Longhorn ==="
kubectl wait --for=condition=ready pod -l app=longhorn-manager \
  -n longhorn-system --timeout=300s

echo "=== Step 7: Verify storage classes ==="
kubectl get sc

echo "=== Step 8: Add Gitea Helm repo ==="
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update

echo "=== Step 9: Create namespace ==="
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -

echo "=== Step 10: Install Gitea ==="
helm install gitea gitea-charts/gitea \
  --namespace gitea \
  --set persistence.storageClass=longhorn \
  --set postgresql.persistence.storageClass=longhorn \
  --set replicaCount=1 \
  --set gitea.config.cache.ADAPTER=memory \
  --set gitea.config.session.PROVIDER=memory

echo "=== Step 11: Wait for Gitea ==="
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=gitea \
  -n gitea --timeout=300s

echo "=== Setup Complete ==="
echo "Gitea URL: http://${CONTROL_IP}:3000 (via port-forward)"
echo "kubectl port-forward --address 0.0.0.0 svc/gitea-http 3000:3000 -n gitea"