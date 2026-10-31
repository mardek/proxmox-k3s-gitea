#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
control_plane_address=${CONTROL_PLANE_ADDRESS:-192.168.2.100}
proxmox_ssh_address=${PROXMOX_SSH_ADDRESS:-192.168.2.22}
worker_addresses=${WORKER_ADDRESSES:-"192.168.2.101 192.168.2.102 192.168.2.103"}
ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
failures=0

section() {
  printf '\n==> %s\n' "$*"
}

refresh_host_key() {
  local address=$1
  ssh-keygen -R "$address" >/dev/null 2>&1 || true
  ssh-keygen -R "[${address}]:22" >/dev/null 2>&1 || true
}

run() {
  if ! "$@"; then
    echo "[FAILED] $*" >&2
    failures=$((failures + 1))
  fi
}

control() {
  run ssh "${ssh_options[@]}" "debian@${control_plane_address}" "sudo $*"
}

if ! command -v ssh >/dev/null 2>&1; then
  echo "ssh is required" >&2
  exit 1
fi

section "Checking control-plane SSH access"
refresh_host_key "$control_plane_address"
if ! ssh "${ssh_options[@]}" "debian@${control_plane_address}" 'sudo true'; then
  echo "Cannot run diagnostics on ${control_plane_address}" >&2
  exit 1
fi

if command -v terraform >/dev/null 2>&1; then
  section "Validating Terraform configuration"
  run terraform -chdir="${script_dir}/01-vms" validate
else
  section "Terraform not installed; skipping local validation"
fi

section "Checking Proxmox VM status"
refresh_host_key "$proxmox_ssh_address"
run ssh "${ssh_options[@]}" "root@${proxmox_ssh_address}" 'qm list'

for address in "$control_plane_address" $worker_addresses; do
  section "Checking Cloud-Init and K3s service on ${address}"
  refresh_host_key "$address"
  run ssh "${ssh_options[@]}" "debian@${address}" \
    'cloud-init status --long; sudo systemctl is-active k3s || sudo systemctl is-active k3s-agent'
done

section "Checking Kubernetes nodes"
control 'kubectl get nodes -o wide'

section "Checking all Pods"
control 'kubectl get pods -A -o wide'

section "Checking Longhorn"
control 'kubectl -n longhorn-system get pods -o wide'
control 'kubectl -n longhorn-system get sharemanager'

section "Checking storage"
control 'kubectl get sc'
control 'kubectl get pv'
control 'kubectl get pvc -A -o wide'

section "Checking persistent volume node placement"
control "kubectl get pv -o custom-columns='PV:.metadata.name,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values'"

section "Checking Helm and K9s versions"
control 'helm version --short'
control 'k9s version'

section "Checking Gitea Helm release"
control 'env KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm list -n gitea'

section "Checking Gitea resources"
control 'kubectl -n gitea get pods,pvc,svc,ingress -o wide'

section "Checking container images"
control "kubectl -n gitea get pods -o jsonpath='{range .items[*]}{.metadata.name}{\"\n\"}{range .spec.initContainers[*]}  init: {.image}{\"\n\"}{end}{range .spec.containers[*]}  image: {.image}{\"\n\"}{end}{end}'"

section "Checking Gitea warning events"
control 'kubectl -n gitea get events --field-selector type=Warning --sort-by=.lastTimestamp'

section "Checking Gitea logs"
control 'kubectl -n gitea logs deployment/gitea --tail=50'
control 'kubectl -n gitea logs statefulset/gitea-postgresql --tail=50'

section "Diagnostic summary"
if (( failures > 0 )); then
  echo "${failures} check(s) failed; review the [FAILED] lines above." >&2
  exit 1
fi

echo "All diagnostic checks completed without command failures."
