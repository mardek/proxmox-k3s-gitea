# DevSecOps Homelab Guide

This guide covers the Kubernetes homelab built on Proxmox VE using k3s, including cluster architecture, storage, networking, security policies, and EKS mapping for interview preparation.

## Architecture Overview

The cluster consists of 4 Debian 12 VMs:
- **k3s-control** (192.168.2.100): Control plane + etcd
- **k3s-worker-1** (192.168.2.101): Worker node
- **k3s-worker-2** (192.168.2.102): Worker node
- **k3s-worker-3** (192.168.2.103): Worker node

All nodes run k3s v1.36.5+k3s1 with containerd runtime.

## Storage

### Local-Path (Default)
- Single-node storage using host filesystem
- Fast but not HA
- Data tied to specific node

### Longhorn
- Distributed block storage with replication
- Supports RWO and RWX via share manager
- Replicates across 3 nodes by default

## Networking

- Pod CIDR: 10.42.0.0/16
- Service CIDR: 10.43.0.0/16
- CNI: Flannel (VXLAN overlay)
- Ingress: Traefik (included with k3s)

## Security

- Pod Security Standards
- Network Policies
- RBAC configuration
- Service account management

## EKS Mapping

| k3s Component | EKS Equivalent |
|---------------|----------------|
| Longhorn | EBS CSI / EFS CSI |
| Traefik | AWS Load Balancer Controller |
| Flannel | VPC CNI |
| local-path | EBS CSI dynamic provisioning |

## Interview Topics

1. IRSA (IAM Roles for Service Accounts)
2. Managed Node Groups vs Fargate
3. Add-ons management
4. Private vs public API endpoints
5. Security groups for pods
