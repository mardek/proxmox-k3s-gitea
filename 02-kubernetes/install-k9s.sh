#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi
if [[ $(uname -m) != x86_64 ]]; then
  echo "This installer currently supports Linux amd64 only" >&2
  exit 1
fi

version=0.51.0
asset=k9s_Linux_amd64.tar.gz
base_url="https://github.com/derailed/k9s/releases/download/v${version}"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

curl -fsSL "${base_url}/${asset}" -o "${work_dir}/${asset}"
curl -fsSL "${base_url}/checksums.sha256" -o "${work_dir}/checksums.sha256"
(
  cd "$work_dir"
  sha256sum --ignore-missing -c checksums.sha256
)
tar -xzf "${work_dir}/${asset}" -C "$work_dir" k9s
install -m 0755 "${work_dir}/k9s" /usr/local/bin/k9s
install -d -m 0700 /root/.kube
if [[ ! -e /root/.kube/config ]]; then
  ln -s /etc/rancher/k3s/k3s.yaml /root/.kube/config
fi
k9s version
