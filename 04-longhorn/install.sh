#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
control_plane_address=${CONTROL_PLANE_ADDRESS:-192.168.2.100}
all_addresses=${K3S_ADDRESSES:-"192.168.2.100 192.168.2.101 192.168.2.102 192.168.2.103"}
ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

log() {
  printf '\n==> %s\n' "$*"
}

for address in $all_addresses; do
  log "Installing Longhorn prerequisites on ${address}"
  ssh-keygen -R "$address" >/dev/null 2>&1 || true
  ssh "${ssh_options[@]}" "debian@${address}" \
    'sudo apt-get update && sudo apt-get install -y open-iscsi nfs-common cryptsetup dmsetup && sudo systemctl enable --now iscsid'
done

log "Installing Longhorn 1.13.0"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  'sudo helm repo add longhorn https://charts.longhorn.io --force-update && sudo helm repo update longhorn && sudo helm upgrade --install longhorn longhorn/longhorn --version 1.13.0 --namespace longhorn-system --create-namespace --wait --timeout 15m'

log "Waiting for Longhorn controllers and node drivers"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  'sudo kubectl -n longhorn-system wait --for=condition=Available deployment --all --timeout=15m && sudo kubectl -n longhorn-system rollout status daemonset --all --timeout=15m'

log "Creating the RWX StorageClass and test workload"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" 'sudo kubectl apply -f -' \
  < "${script_dir}/storageclass.yaml"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" 'sudo kubectl apply -f -' \
  < "${script_dir}/test-rwx.yaml"

"${script_dir}/validate.sh"
