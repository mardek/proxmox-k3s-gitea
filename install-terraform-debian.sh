#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

source /etc/os-release
if [[ ${ID} != debian || ${VERSION_ID} != 12 ]]; then
  echo "This installer supports Debian 12 only; found ${PRETTY_NAME}." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl dpkg gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform
terraform version
