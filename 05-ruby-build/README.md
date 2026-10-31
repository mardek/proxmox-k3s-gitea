# Gentoo Ruby builders

Deploys one Gentoo StatefulSet on each K3s worker. Each pod installs a Gitea Actions runner, builds Ruby from source, gathers timing and resource metrics, publishes release assets, and sends a report to the central dashboard.

## Prerequisites

- Longhorn and Gitea are deployed.
- Gitea Actions is enabled.
- Gitea has a stable URL reachable from every worker pod.
- A Gitea Actions registration token is available.
- A repository exists for build releases. Its owner and name are supplied as `owner/repository`.
- A separate access token can create releases and upload assets in that repository.
- `ssh` and `scp` are installed on the Debian administration VM. The script copies the project to `k3s-control` and performs all `kubectl` operations there.

## Deploy

```bash
./deploy-ruby.sh
```

The script prompts for missing settings and saves them in `.ruby-build.env` with owner-only permissions. Missing exports are also appended to existing `.bashrc` and `.zshrc` files. Later runs reuse those values. Tokens are hidden while typing. Run `./deploy-ruby.sh --reconfigure` to change saved settings, or `./deploy-ruby.sh --help` for the complete manual.

Environment variables still take precedence over saved values:

```bash
export GITEA_URL='http://gitea.gitea.svc.cluster.local'
export GITEA_RUNNER_TOKEN='actions-registration-token'
export GITEA_PUBLISH_TOKEN='release-upload-token'
export GITEA_REPOSITORY='admin/ruby'
./deploy-ruby.sh
```

Optional versions:

```bash
export RUBY_VERSION='3.4.11'
export ACT_RUNNER_VERSION='0.2.12'
export ACT_RUNNER_SHA256='be020ea42303598dd7f0908675ddd7ce4a753eafecc5efe44ca96a22e34ba11e'
export GENTOO_IMAGE='gentoo/stage3:latest'
```

Open the dashboard at `http://192.168.2.100:30080`. It refreshes every 30 seconds.

## Inspect builds

```bash
kubectl -n gentoo-ruby get pods -o wide
kubectl -n gentoo-ruby logs ruby-builder-k3s-worker-1-0 -f
kubectl -n gentoo-ruby logs ruby-builder-k3s-worker-2-0 -f
kubectl -n gentoo-ruby logs ruby-builder-k3s-worker-3-0 -f
```

The initial Portage synchronization and dependency installation can take considerable time. Ruby compilation begins afterward. Every StatefulSet has a 5 Gi Longhorn volume for runner registration and build data.

## Start another build

```bash
kubectl -n gentoo-ruby exec ruby-builder-k3s-worker-1-0 -- /opt/ruby-build/build-ruby.sh
```

Gitea Actions jobs with a matching `gentoo` or worker-specific label can execute the same script.

## Published data

Each successful build uploads these assets to a new Gitea Release:

- Original Ruby source archive
- Linux AMD64 Ruby binary
- SHA-256 checksums
- `metrics.json`
- `build-report.html`

The dashboard stores its reports on a separate Longhorn volume. Its upload endpoint is unauthenticated and should remain on the trusted homelab network or be protected before external exposure.

## Remove the builders

```bash
kubectl delete namespace gentoo-ruby
```

This removes the Kubernetes resources. PersistentVolumeClaims created by StatefulSets may need to be removed separately if their data is no longer required.
