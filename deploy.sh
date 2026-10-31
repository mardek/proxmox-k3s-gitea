#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PROXMOX_DEPLOY_CONFIG:-${script_dir}/.proxmox-env}
reconfigure=false

usage() {
  cat <<'EOF'
Usage: ./deploy.sh [--reconfigure]
       ./deploy.sh -h | --help

Create the Proxmox VMs, install K3s and Longhorn, and deploy Gitea.
Missing settings are requested interactively and saved in .proxmox-env
with owner-only permissions. Exports are also added to existing .bashrc and
.zshrc files when absent. Later runs reuse the saved values automatically.

Options:
  --reconfigure  Prompt for every setting, including previously saved values.
  -h, --help     Show this manual.

Saved settings:
  PROXMOX_VE_API_TOKEN  Proxmox API token in user@realm!name=uuid format.
  GITEA_ADMIN_PASSWORD  Password for the Gitea administrator account.

Environment overrides:
  PROXMOX_DEPLOY_CONFIG  Alternate settings file path.
  PROXMOX_SSH_ADDRESS    Proxmox SSH address (default: 192.168.2.22).
  CONTROL_PLANE_ADDRESS  Control-plane SSH address (default: 192.168.2.100).
  GITEA_HOST             Optional public Gitea hostname.

Secrets are hidden while typing. Environment variables take precedence over
saved values. Use --reconfigure after rotating credentials.
EOF
}

while (($#)); do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --reconfigure) reconfigure=true ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ -f $config_file ]]; then
  # shellcheck source=/dev/null
  source "$config_file"
fi

for variable in PROXMOX_VE_API_TOKEN GITEA_ADMIN_PASSWORD; do
  current=${!variable:-}
  if [[ $reconfigure != true && -n $current ]]; then
    continue
  fi
  read -rsp "$variable${current:+ [saved; press Enter to keep]}: " value
  printf '\n'
  if [[ -z $value ]]; then
    value=$current
  fi
  if [[ -z $value ]]; then
    echo "$variable is required" >&2
    exit 1
  fi
  printf -v "$variable" '%s' "$value"
  export "$variable"
done

umask 077
{
  printf 'export PROXMOX_VE_API_TOKEN=%q\n' "$PROXMOX_VE_API_TOKEN"
  printf 'export GITEA_ADMIN_PASSWORD=%q\n' "$GITEA_ADMIN_PASSWORD"
  printf 'export PROXMOX_SSH_ADDRESS=%q\n' "${PROXMOX_SSH_ADDRESS:-192.168.2.22}"
  printf 'export CONTROL_PLANE_ADDRESS=%q\n' "${CONTROL_PLANE_ADDRESS:-192.168.2.100}"
  printf 'export GITEA_HOST=%q\n' "${GITEA_HOST:-}"
} > "$config_file"
for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f $rc_file ]] || continue
  for variable in PROXMOX_VE_API_TOKEN GITEA_ADMIN_PASSWORD; do
    if ! grep -qE "^[[:space:]]*(export[[:space:]]+)?${variable}=" "$rc_file"; then
      printf 'export %s=%q\n' "$variable" "${!variable}" >> "$rc_file"
    fi
  done
done

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
