#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "${script_dir}/.proxmox-env" ]]; then
  source "${script_dir}/.proxmox-env"
fi

proxmox_ssh_address=${PROXMOX_SSH_ADDRESS:-192.168.2.22}
control_plane_address=${CONTROL_PLANE_ADDRESS:-192.168.2.100}
remote_dir=/tmp/k3s-gitea-deploy
ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

log() {
  printf '\n==> %s\n' "$*"
}

refresh_host_key() {
  local address=$1
  ssh-keygen -R "$address" >/dev/null 2>&1 || true
  ssh-keygen -R "[${address}]:22" >/dev/null 2>&1 || true
}

log "Checking local prerequisites"
for command_name in terraform curl dpkg ssh scp ssh-agent ssh-add ssh-keygen; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required; install it before running this script" >&2
    exit 1
  fi
done

if [[ -z ${PROXMOX_VE_API_TOKEN:-} ]]; then
  echo "Set PROXMOX_VE_API_TOKEN before running this script" >&2
  exit 1
fi
if [[ -z ${GITEA_ADMIN_PASSWORD:-} ]]; then
  echo "Set GITEA_ADMIN_PASSWORD before running this script" >&2
  exit 1
fi

log "Preparing the local Terraform provider mirror"
"${script_dir}/01-vms/install-providers.sh"
export TF_CLI_CONFIG_FILE="${script_dir}/01-vms/.terraform-provider-mirror/terraform.rc"

log "Loading the SSH key and testing Proxmox access"
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$HOME/.ssh/id_ed25519"
ssh-add -L >/dev/null
refresh_host_key "$proxmox_ssh_address"
ssh "${ssh_options[@]}" "root@${proxmox_ssh_address}" 'echo SSH_OK'

log "Creating or updating the four Proxmox VMs"
terraform -chdir="${script_dir}/01-vms" init -input=false
terraform -chdir="${script_dir}/01-vms" apply -auto-approve -input=false

log "Waiting for K3s on ${control_plane_address}"
refresh_host_key "$control_plane_address"
deadline=$((SECONDS + 600))
until ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  'sudo test -s /etc/rancher/k3s/k3s.yaml' 2>/dev/null; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for K3s on ${control_plane_address}" >&2
    exit 1
  fi
  sleep 10
done

log "Copying deployment scripts to the control plane"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  "mkdir -p '${remote_dir}/02-kubernetes' '${remote_dir}/03-gitea' '${remote_dir}/04-longhorn'"
scp -q "${ssh_options[@]}" "${script_dir}/02-kubernetes/"*.sh \
  "debian@${control_plane_address}:${remote_dir}/02-kubernetes/"
scp -q "${ssh_options[@]}" "${script_dir}/03-gitea/install.sh" "${script_dir}/03-gitea/values.yaml" \
  "debian@${control_plane_address}:${remote_dir}/03-gitea/"
scp -q "${ssh_options[@]}" "${script_dir}/04-longhorn/"*.sh "${script_dir}/04-longhorn/"*.yaml \
  "debian@${control_plane_address}:${remote_dir}/04-longhorn/"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  "chmod +x '${remote_dir}/02-kubernetes/'*.sh '${remote_dir}/03-gitea/install.sh' '${remote_dir}/04-longhorn/'*.sh"

log "Waiting for all four Kubernetes nodes to become Ready"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  "sudo '${remote_dir}/02-kubernetes/wait-for-cluster.sh' 4 600"

log "Installing Helm on the control plane"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  "sudo '${remote_dir}/02-kubernetes/install-helm.sh'"

log "Installing K9s on the control plane"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  "sudo '${remote_dir}/02-kubernetes/install-k9s.sh'"

log "Installing Longhorn distributed storage"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" \
  "sudo '${remote_dir}/04-longhorn/install.sh'"

log "Installing or upgrading Gitea with Helm"
{
  printf 'export GITEA_ADMIN_PASSWORD=%q\n' "$GITEA_ADMIN_PASSWORD"
  printf 'export GITEA_HOST=%q\n' "${GITEA_HOST:-}"
  printf "'%s/03-gitea/install.sh'\n" "$remote_dir"
} | ssh "${ssh_options[@]}" "debian@${control_plane_address}" 'sudo bash -s'

log "Deployment completed successfully"
