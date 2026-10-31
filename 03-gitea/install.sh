#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ -z ${KUBECONFIG:-} && -f /etc/rancher/k3s/k3s.yaml ]]; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
fi

for command_name in helm kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${command_name} is required" >&2
    exit 1
  fi
done

if [[ -z ${GITEA_ADMIN_PASSWORD:-} ]]; then
  echo "Set GITEA_ADMIN_PASSWORD before running this script" >&2
  exit 1
fi

kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gitea create secret generic gitea-admin \
  --from-literal=admin-password="${GITEA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset GITEA_ADMIN_PASSWORD

helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo update bitnami

helm_args=(
  upgrade --install gitea bitnami/gitea
  --version 3.2.22
  --namespace gitea
  --values "${script_dir}/values.yaml"
  --wait
  --timeout 10m
)

if [[ -n ${GITEA_HOST:-} ]]; then
  helm_args+=(
    --set "ingress.enabled=true"
    --set "ingress.hostname=${GITEA_HOST}"
    --set "rootURL=http://${GITEA_HOST}/"
  )
fi

helm "${helm_args[@]}"
kubectl -n gitea get pods,pvc,ingress
