# k3s on Proxmox Setup Guide

Step-by-step guide for provisioning a k3s cluster on Proxmox VE.

## Prerequisites

- Proxmox VE host with adequate resources
- Debian 12 cloud-init template (VM 9000)
- 4 IPs in your LAN: 192.168.2.100-103

## Step 1: Create VMs

```bash
for id in 100 101 102 103; do
  qm clone 9000 $id --name k3s-node-$id --full
  qm set $id --memory 4096 --cores 4
  qm resize $id scsi0 32G
  qm set $id --ipconfig0 ip=192.168.2.$id/24,gw=192.168.2.1
  qm start $id
done
```

## Step 2: Install k3s Server

On k3s-control (192.168.2.100):

```bash
cloud-init status --wait
sudo apt update
sudo apt install -y curl open-iscsi nfs-common
curl -sfL https://get.k3s.io | sh -
```

## Step 3: Configure kubeconfig

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config
```

## Step 4: Get Join Token

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

## Step 5: Join Workers

On each worker:

```bash
cloud-init status --wait
sudo apt update
sudo apt install -y curl open-iscsi nfs-common
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.2.100:6443 K3S_TOKEN=<TOKEN> sh -
```

## Step 6: Verify

```bash
kubectl get nodes
```

All nodes should show `Ready`.

## Troubleshooting

- If worker doesn't join, check `sudo journalctl -u k3s-agent -f`
- If nodes show NotReady, check `sudo systemctl status k3s-agent`
- For network issues, verify VMs can reach each other on port 6443
