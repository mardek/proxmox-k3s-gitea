# Longhorn RWX evaluation design

## Goal

Add an isolated Longhorn RWX proof of concept without changing the running Gitea or PostgreSQL deployment.

## Scope

Create `04-longhorn/` with an installer and test manifests. The stage will install host prerequisites, deploy Longhorn 1.13.0 through Helm, configure a three-replica StorageClass, and verify that Pods on different workers can access the same RWX volume.

The existing Gitea application, its PVCs, and its database remain untouched. CloudNativePG migration is out of scope.

## Components

- `install.sh`: run on the Debian Terraform runner; uses SSH to install `open-iscsi`, `nfs-common`, `cryptsetup`, and `dmsetup` on all four VMs, then installs Longhorn on the control plane with Helm.
- `storageclass.yaml`: `longhorn-rwx` using `driver.longhorn.io`, three replicas, `Delete` reclaim policy, and expansion enabled.
- `test-rwx.yaml`: a 1 Gi RWX PVC plus writer and reader Pods pinned to different workers. The writer appends timestamps to a shared file; the reader prints it.
- `validate.sh`: checks Longhorn Pods, the PVC, share-manager resources, and shared-file visibility from the reader.

## Operational behavior

The installer is separate from `deploy.sh` and must be run explicitly. It is repeatable: package installation and `helm upgrade --install` are idempotent. It does not remove or modify `local-path`, Gitea, or PostgreSQL resources.

Longhorn RWX exposes a replicated block volume through an NFS share-manager Pod. Data replicas are distributed across workers, but NFS client I/O can pause during share-manager failover. This test does not claim zero-downtime HA.

## Verification

Local verification on the Mac:

- Run `bash -n` on all scripts.
- Parse YAML manifests without applying them.

Cluster verification when the user runs the stage:

- Longhorn system Pods become Ready.
- The test PVC becomes Bound with RWX access.
- The writer and reader run on different workers.
- The reader displays the writer's shared-file contents.
- `diagnose.sh` reports Longhorn Pods, StorageClasses, PVCs, and share-manager resources.
