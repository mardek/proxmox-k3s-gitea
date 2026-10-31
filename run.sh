#!/usr/bin/env bash
set -euo pipefail

control_plane_address=${CONTROL_PLANE_ADDRESS:-192.168.2.100}
gitea_port=${GITEA_PORT:-8080}

for command_name in ssh ssh-keygen; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required" >&2
    exit 1
  fi
done
if [[ ! ${gitea_port} =~ ^[0-9]+$ || ${gitea_port} -lt 1 || ${gitea_port} -gt 65535 ]]; then
  echo "GITEA_PORT must be between 1 and 65535" >&2
  exit 2
fi

ssh-keygen -R "$control_plane_address" >/dev/null 2>&1 || true
ssh-keygen -R "[${control_plane_address}]:22" >/dev/null 2>&1 || true

printf '\nOpen this URL in your browser: http://%s:%s\n' "$control_plane_address" "$gitea_port"
printf 'Login user: admin\n'
printf 'Keep this terminal open. Press Ctrl+C to stop access.\n\n'

exec ssh -t -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
  "debian@${control_plane_address}" \
  "sudo env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n gitea port-forward svc/gitea ${gitea_port}:80 --address 0.0.0.0"
