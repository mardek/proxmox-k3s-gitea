#!/usr/bin/env bash
set -euo pipefail

expected_nodes=${1:-4}
timeout_seconds=${2:-600}

if [[ ! ${expected_nodes} =~ ^[1-9][0-9]*$ || ! ${timeout_seconds} =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 [expected-node-count] [timeout-seconds]" >&2
  exit 2
fi
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

deadline=$((SECONDS + timeout_seconds))
while true; do
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ ${node_count} -eq ${expected_nodes} ]]; then
    break
  fi
  if (( SECONDS >= deadline )); then
    echo "Timed out: expected ${expected_nodes} nodes, found ${node_count}" >&2
    kubectl get nodes >&2 || true
    exit 1
  fi
  sleep 5
done

kubectl wait --for=condition=Ready nodes --all --timeout="${timeout_seconds}s"
kubectl get nodes -o wide
