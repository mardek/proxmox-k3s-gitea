#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "${script_dir}/.proxmox-env" ]]; then
  source "${script_dir}/.proxmox-env"
fi

proxmox_ssh_address=${PROXMOX_SSH_ADDRESS:-192.168.2.22}

log() {
  printf '\n==> %s\n' "$*"
}

log "Checking destruction prerequisites"
for command_name in terraform ssh ssh-agent ssh-add ssh-keygen; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required" >&2
    exit 1
  fi
done
if [[ -z ${PROXMOX_VE_API_TOKEN:-} ]]; then
  echo "Set PROXMOX_VE_API_TOKEN before running this script" >&2
  exit 1
fi

log "Loading the SSH key and testing Proxmox access"
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$HOME/.ssh/id_ed25519"
ssh-add -L >/dev/null
ssh-keygen -R "$proxmox_ssh_address" >/dev/null 2>&1 || true
ssh-keygen -R "[${proxmox_ssh_address}]:22" >/dev/null 2>&1 || true
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
  "root@${proxmox_ssh_address}" 'echo SSH_OK'

log "Preparing Terraform"
terraform -chdir="${script_dir}/01-vms" init -input=false

log "The next step will permanently delete all managed VMs, snippets, and local data"
log "Review the destruction plan and type yes only if you intend to erase the environment"
terraform -chdir="${script_dir}/01-vms" destroy -input=false

log "Terraform-managed environment destroyed"
