#!/usr/bin/env bash
set -euo pipefail

control_plane_address=${CONTROL_PLANE_ADDRESS:-192.168.2.100}
ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

control() {
  ssh "${ssh_options[@]}" "debian@${control_plane_address}" "sudo $*"
}

printf '\n==> Longhorn Pods\n'
control 'kubectl -n longhorn-system get pods -o wide'

printf '\n==> RWX StorageClass and PVC\n'
control 'kubectl get storageclass longhorn-rwx'
control 'kubectl get pvc longhorn-rwx-test'

printf '\n==> Share manager\n'
control 'kubectl -n longhorn-system get sharemanager'

printf '\n==> Writer and reader placement\n'
control 'kubectl get pods longhorn-rwx-writer longhorn-rwx-reader -o wide'

printf '\n==> Shared-file result\n'
control 'kubectl wait --for=jsonpath={.status.phase}=Succeeded pod/longhorn-rwx-reader --timeout=5m'
control 'kubectl logs longhorn-rwx-reader'
