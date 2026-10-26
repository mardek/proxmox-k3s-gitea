# Longhorn RWX Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an isolated Longhorn RWX installation and cross-worker shared-volume test.

**Architecture:** A Debian runner uses SSH to prepare all VMs and run Helm/kubectl on the control plane. Longhorn 1.13.0 provisions a three-replica RWX volume shared by a writer on worker 1 and a reader on worker 2. Existing Gitea resources are untouched.

**Tech Stack:** Bash, SSH, Helm 3, K3s, Longhorn 1.13.0, Kubernetes CSI, NFSv4, Debian 12.

**Spec:** `docs/superpowers/specs/2026-10-26-longhorn-rwx-design.md`

## Global Constraints

- Project root: `/Users/mardek/Documents/dev/proxmox-k3s-gitea`.
- Do not change existing Gitea or PostgreSQL resources.
- Do not execute installation or test manifests from the Mac.
- Debian only needs SSH; kubectl and Helm run on the control plane.
- The project is not a Git repository; do not initialize Git or create commits.

---

### Task 1: RWX StorageClass and test workload

**Files:**
- Create: `04-longhorn/storageclass.yaml`
- Create: `04-longhorn/test-rwx.yaml`

**Interfaces:**
- Produces: StorageClass `longhorn-rwx`, PVC `longhorn-rwx-test`, writer Pod on `k3s-worker-1`, reader Pod on `k3s-worker-2`.

- [ ] **Step 1: Verify the test is missing**

Run: `test ! -e 04-longhorn/test-rwx.yaml`
Expected: exit 0 before implementation.

- [ ] **Step 2: Create StorageClass**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-rwx
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
```

- [ ] **Step 3: Create the shared-volume test**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-rwx-test
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: longhorn-rwx
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-rwx-writer
spec:
  nodeSelector:
    kubernetes.io/hostname: k3s-worker-1
  containers:
    - name: writer
      image: debian:12-slim
      command: ["/bin/sh", "-c"]
      args:
        - |
          while true; do
            date -u +"%Y-%m-%dT%H:%M:%SZ $(hostname)" >> /data/shared.log
            sleep 5
          done
      volumeMounts:
        - name: shared
          mountPath: /data
  volumes:
    - name: shared
      persistentVolumeClaim:
        claimName: longhorn-rwx-test
---
apiVersion: v1
kind: Pod
metadata:
  name: longhorn-rwx-reader
spec:
  nodeSelector:
    kubernetes.io/hostname: k3s-worker-2
  containers:
    - name: reader
      image: debian:12-slim
      command: ["/bin/sh", "-c"]
      args:
        - |
          for i in $(seq 1 60); do
            if [ -s /data/shared.log ]; then
              cat /data/shared.log
              exit 0
            fi
            sleep 2
          done
          echo "Timed out waiting for shared data" >&2
          exit 1
      volumeMounts:
        - name: shared
          mountPath: /data
  volumes:
    - name: shared
      persistentVolumeClaim:
        claimName: longhorn-rwx-test
```

- [ ] **Step 4: Parse YAML without applying**

Run: `ruby -ryaml -e 'ARGV.each { |path| YAML.load_stream(File.read(path)) }' 04-longhorn/storageclass.yaml 04-longhorn/test-rwx.yaml`
Expected: exit 0.

---

### Task 2: Installer and validator

**Files:**
- Create: `04-longhorn/install.sh`
- Create: `04-longhorn/validate.sh`

**Interfaces:**
- `install.sh` consumes SSH access and the manifests from Task 1.
- `validate.sh` reports Longhorn health and the reader's shared-file output.

- [ ] **Step 1: Verify scripts are missing**

Run: `test ! -e 04-longhorn/install.sh && test ! -e 04-longhorn/validate.sh`
Expected: exit 0 before implementation.

- [ ] **Step 2: Create installer**

```bash
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
```

- [ ] **Step 3: Create validator**

```bash
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
```

- [ ] **Step 4: Validate shell syntax**

Run: `bash -n 04-longhorn/install.sh 04-longhorn/validate.sh`
Expected: exit 0.

---

### Task 3: Diagnostics integration and final checks

**Files:**
- Modify: `diagnose.sh`

**Interfaces:**
- Adds optional Longhorn reporting without failing clusters where Longhorn is absent.

- [ ] **Step 1: Add optional Longhorn checks after the all-Pods section**

```bash
section "Checking Longhorn (optional)"
control 'if kubectl get namespace longhorn-system >/dev/null 2>&1; then kubectl -n longhorn-system get pods -o wide; kubectl -n longhorn-system get sharemanager; else echo "Longhorn is not installed"; fi'
```

- [ ] **Step 2: Run final local verification**

Run:

```bash
bash -n diagnose.sh 04-longhorn/install.sh 04-longhorn/validate.sh
ruby -ryaml -e 'ARGV.each { |path| YAML.load_stream(File.read(path)) }' 04-longhorn/storageclass.yaml 04-longhorn/test-rwx.yaml
```

Expected: all commands exit 0; nothing contacts Proxmox or Kubernetes.
