#!/bin/bash
set -euo pipefail

export MAKEOPTS=${MAKEOPTS:--j2}

log() {
  printf '\n==> %s\n' "$*"
}

log "Synchronizing Portage"
sync_complete=false
for attempt in 1 2 3; do
  if emerge-webrsync; then
    sync_complete=true
    break
  fi
  log "Portage synchronization attempt ${attempt} failed; retrying"
  sleep 30
done
if [[ $sync_complete != true ]]; then
  echo "Portage synchronization failed after three attempts" >&2
  exit 1
fi

log "Selecting the Gentoo AMD64 profile"
eselect profile set default/linux/amd64/23.0

log "Installing runner and Ruby build dependencies"
emerge --noreplace \
  app-arch/xz-utils \
  app-misc/jq \
  dev-lang/python \
  dev-libs/gmp \
  dev-libs/libffi \
  dev-libs/libyaml \
  dev-libs/openssl \
  dev-vcs/git \
  net-misc/curl \
  sys-libs/readline \
  sys-libs/zlib \
  sys-process/time

runner_dir=/data/runner
mkdir -p "$runner_dir"
cd "$runner_dir"
runner_binary=/usr/local/bin/act_runner
if [[ ! -x $runner_binary ]]; then
  log "Installing Gitea Actions runner ${ACT_RUNNER_VERSION}"
  asset="act_runner-${ACT_RUNNER_VERSION}-linux-amd64"
  base_url="https://gitea.com/gitea/act_runner/releases/download/v${ACT_RUNNER_VERSION}"
  curl -fL --retry 4 "$base_url/$asset" -o /tmp/act_runner
  expected_checksum=${ACT_RUNNER_SHA256:-be020ea42303598dd7f0908675ddd7ce4a753eafecc5efe44ca96a22e34ba11e}
  echo "$expected_checksum  /tmp/act_runner" | sha256sum -c -
  install -m 0755 /tmp/act_runner "$runner_binary"
fi

if [[ ! -s .runner ]]; then
  log "Registering $WORKER_NAME with Gitea"
  act_runner register --no-interactive \
    --instance "$GITEA_URL" \
    --token "$GITEA_RUNNER_TOKEN" \
    --name "$WORKER_NAME" \
    --labels "self-hosted,linux,amd64,gentoo,$WORKER_NAME"
fi

if [[ ${RUBY_BUILD_ON_START:-true} == true ]]; then
  log "Starting the initial Ruby build"
  if ! id builder >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash builder
  fi
  mkdir -p /data/builds
  chown builder:builder /data/builds
  runuser -u builder -- /opt/ruby-build/build-ruby.sh || true
fi

log "Starting the Gitea Actions runner"
exec act_runner daemon
