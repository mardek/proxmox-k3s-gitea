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

version=3.19.0
asset="helm-v${version}-linux-amd64.tar.gz"
expected_checksum=a7f81ce08007091b86d8bd696eb4d86b8d0f2e1b9f6c714be62f82f96a594496
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

curl -fsSL "https://get.helm.sh/${asset}" -o "${work_dir}/${asset}"
echo "${expected_checksum}  ${work_dir}/${asset}" | sha256sum -c -
tar -xzf "${work_dir}/${asset}" -C "$work_dir" linux-amd64/helm
install -m 0755 "${work_dir}/linux-amd64/helm" /usr/local/bin/helm
helm version --short
