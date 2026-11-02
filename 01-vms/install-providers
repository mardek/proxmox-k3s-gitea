#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mirror_dir="${script_dir}/.terraform-provider-mirror"

case $(dpkg --print-architecture) in
  amd64) terraform_arch=amd64 ;;
  arm64) terraform_arch=arm64 ;;
  *)
    echo "No provider mirror is configured for this Debian architecture" >&2
    exit 1
    ;;
esac

install_provider() {
  local namespace=$1
  local name=$2
  local version=$3
  local url=$4
  local target_dir="${mirror_dir}/registry.terraform.io/${namespace}/${name}"
  local archive="${target_dir}/terraform-provider-${name}_${version}_linux_${terraform_arch}.zip"
  local temporary_archive

  if [[ -s ${archive} ]]; then
    return
  fi

  mkdir -p "$target_dir"
  temporary_archive=$(mktemp "${archive}.XXXXXX")
  trap 'rm -f "$temporary_archive"' RETURN
  curl --fail --location --silent --show-error \
    --connect-timeout 10 --max-time 300 \
    --retry 4 --retry-delay 2 --retry-all-errors \
    --output "$temporary_archive" "$url"
  mv "$temporary_archive" "$archive"
}

install_provider hashicorp random 3.9.1 \
  "https://releases.hashicorp.com/terraform-provider-random/3.9.1/terraform-provider-random_3.9.1_linux_${terraform_arch}.zip"
install_provider bpg proxmox 0.118.0 \
  "https://github.com/bpg/terraform-provider-proxmox/releases/download/v0.118.0/terraform-provider-proxmox_0.118.0_linux_${terraform_arch}.zip"

printf 'provider_installation {\n  filesystem_mirror {\n    path = "%s"\n  }\n}\n' "$mirror_dir" > "${mirror_dir}/terraform.rc"
