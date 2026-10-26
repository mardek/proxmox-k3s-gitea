# Proxmox, K3s, and Gitea rebuild pipeline

## Goal

Create a repeatable, from-scratch deployment for three Debian 12 VMs on Proxmox, a K3s cluster bootstrapped by Cloud-Init, and Gitea installed with Helm. The project will live at `/Users/mardek/Documents/dev/proxmox-k3s-gitea`.

## Selected approach

Use three independently operated stages:

1. Terraform with the `bpg/proxmox` provider creates the VMs and uploads rendered Cloud-Init snippets.
2. Cloud-Init installs K3s: one server at `192.168.2.100` and agents at `192.168.2.101` and `192.168.2.102`.
3. Helm installs or upgrades Gitea in the `gitea` namespace with persistent storage and optional Ingress configuration.

A shared, randomly generated K3s token is passed to the server and agents. It is marked sensitive in Terraform outputs and variables where applicable; Terraform state must still be protected because it can contain sensitive values.

Alternatives considered:

- One Terraform configuration for everything: fewer directories, but couples application and VM lifecycles and requires a working cluster during Terraform initialization.
- Ansible for K3s: rejected because the existing workflow uses Cloud-Init and the user does not want Ansible.
- Separate files without separate directories: useful for organization but insufficient for independent Terraform state and lifecycle.

## Files

- `install-terraform-debian.sh`: root-run Debian 12 installer using HashiCorp's official APT repository; verifies `terraform version`.
- `01-vms/versions.tf`: Terraform and provider version constraints.
- `01-vms/providers.tf`: Proxmox provider configuration using environment variables for credentials.
- `01-vms/variables.tf`: Proxmox, VM, network, SSH, and Gitea-independent inputs.
- `01-vms/main.tf`: three VM resources, Cloud-Init snippet resources, and a random K3s token.
- `01-vms/outputs.tf`: VM names, IDs, and addresses without exposing secrets.
- `01-vms/terraform.tfvars.example`: editable non-secret environment values for the existing node names and addresses.
- `01-vms/cloud-init/`: server and agent Cloud-Init templates.
- `02-kubernetes/wait-for-cluster.sh`: checks node readiness and expected node count using `kubectl`.
- `03-gitea/values.yaml`: persistent Gitea configuration with explicitly configured Ingress disabled by default until a hostname is supplied.
- `03-gitea/install.sh`: installs/upgrades the pinned Gitea chart with Helm, optionally accepting a hostname and settings overrides.

## Configuration and secrets

The user supplies the Proxmox endpoint, node name, VM template, datastore, snippet datastore, network bridge, gateway, DNS servers, and SSH public key through variables. Proxmox API credentials come from environment variables and are never written to example files. Gitea's administrator password is not committed; the initial installation instructs the user how to supply or create it.

## Failure handling

Cloud-Init commands fail visibly rather than continuing after a failed K3s download. Agents wait for the control-plane API before installing. The readiness script exits nonzero on timeout. The Gitea installer uses `set -euo pipefail`, validates required commands, and uses `helm upgrade --install` for repeatable execution.

## Verification

Without contacting Proxmox or changing existing infrastructure:

- Run `bash -n` on all shell scripts.
- Run `terraform fmt -check` and `terraform validate` in `01-vms` after dependency initialization.
- Render Cloud-Init locally and validate its YAML syntax if a YAML parser is already available.
- Check Helm template rendering if Helm is available locally; otherwise provide the exact command for Debian.

Real `terraform apply`, K3s creation, and Gitea installation require the user's Proxmox credentials and explicit approval and are not part of local verification.

## Destruction

`terraform destroy` in `01-vms` removes all three managed VMs and their local data. It does not delete the Proxmox base template or the project configuration. This is intentionally destructive and must never run automatically during setup or verification.
