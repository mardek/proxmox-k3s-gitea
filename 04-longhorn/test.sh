#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
control_plane_address=${CONTROL_PLANE_ADDRESS:-192.168.2.100}
ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

log() {
  printf '\n==> %s\n' "$*"
}

log "Applying RWX test workload"
ssh "${ssh_options[@]}" "debian@${control_plane_address}" 'sudo kubectl apply -f -' \
  < "${script_dir}/test-rwx.yaml"

"${script_dir}/validate.sh"
