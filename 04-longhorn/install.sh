#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

log() {
  printf '\n==> %s\n' "$*"
}

log "Checking Longhorn prerequisites on the control plane"
sudo apt-get update
sudo apt-get install -y open-iscsi nfs-common cryptsetup dmsetup
sudo systemctl enable --now iscsid

log "Installing Longhorn 1.13.0"
sudo helm repo add longhorn https://charts.longhorn.io --force-update
sudo helm repo update longhorn

watch_longhorn_pods() {
  while true; do
    printf '\n--- Longhorn pod status (%s) ---\n' "$(date -u +%H:%M:%S)"
    sudo kubectl -n longhorn-system get pods -o wide 2>/dev/null || true
    sleep 15
  done
}

watch_longhorn_pods &
watcher_pid=$!
trap 'kill "$watcher_pid" 2>/dev/null || true' EXIT
sudo helm upgrade --install longhorn longhorn/longhorn \
  --version 1.13.0 --namespace longhorn-system --create-namespace --wait --timeout 15m
kill "$watcher_pid" 2>/dev/null || true
wait "$watcher_pid" 2>/dev/null || true
trap - EXIT

log "Waiting for Longhorn controllers and node drivers"
sudo kubectl -n longhorn-system wait --for=condition=Available deployment --all --timeout=15m
while read -r daemonset; do
  sudo kubectl -n longhorn-system rollout status "$daemonset" --timeout=15m
done < <(sudo kubectl -n longhorn-system get daemonset -o name)

log "Creating the RWX StorageClass"
sudo kubectl apply -f - < "${script_dir}/storageclass.yaml"

log "Setting longhorn as the default StorageClass"
sudo kubectl patch storageclass longhorn \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
sudo kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

log "Longhorn installation complete"
