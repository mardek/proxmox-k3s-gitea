# Gentoo Ruby builders

Installs one persistent Gitea Actions runner as a systemd service on each Debian worker VM and deploys one Gentoo StatefulSet on each K3s worker. Registration is stored in `/var/lib/gitea-actions-runner/.runner` on the VM and is reused when the service or Pod restarts. Each deployment selects only one random worker for the initial Ruby build to avoid three simultaneous compilations. Successful builds gather timing and resource metrics, publish release assets, and send a report to the central dashboard.

## Prerequisites

- Longhorn and Gitea are deployed.
- Gitea Actions is enabled.
- Gitea has a stable URL reachable from every worker pod.
- A Gitea Actions registration token is available.
- If `admin/ruby` does not exist, the deployment creates it automatically and initializes its first commit. Existing repositories are reused.
- `ssh` and `scp` are installed on the Debian administration VM. The script copies the project to `k3s-control` and performs all `kubectl` operations there.

## Deploy

```bash
./deploy-ruby
```

The script prompts for missing settings and saves them in `.ruby-build.env` with owner-only permissions. Missing exports are also appended to existing `.bashrc` and `.zshrc` files. Later runs reuse those values. Tokens are hidden while typing. Run `./deploy-ruby --reconfigure` to change saved settings, or `./deploy-ruby --help` for the complete manual. Deployment restarts all three builders and starts a new initial build.

With `GITEA_ADMIN_PASSWORD` available from `.proxmox-env`, the script automatically creates a missing `admin/ruby` repository, generates a repository-write publishing token, and fetches the Actions registration token. Start Gitea access first with `./run start`. Set `GITEA_API_URL` if the administrative API uses a different address. Manual token entry remains available when admin credentials are unavailable.

Use these values for the local lab:

| Setting | Value or location |
|---------|-------------------|
| `GITEA_URL` | `http://gitea.gitea.svc.cluster.local` |
| `GITEA_REPOSITORY` | `admin/ruby` |
| `GITEA_RUNNER_TOKEN` | Repository → Settings → Actions → Runners |
| `GITEA_PUBLISH_TOKEN` | User Settings → Applications → Access Tokens |

Create the publishing token at `http://192.168.2.100:8080/user/settings/applications` with **Repository: Read and Write** permission. This personal access token creates releases and uploads assets; it is not the Actions runner registration token.

Environment variables still take precedence over saved values:

```bash
export GITEA_URL='http://gitea.gitea.svc.cluster.local'
export GITEA_RUNNER_TOKEN='actions-registration-token'
export GITEA_PUBLISH_TOKEN='release-upload-token'
export GITEA_REPOSITORY='admin/ruby'
./deploy-ruby
```

Optional versions:

```bash
export RUBY_VERSION='3.4.11'
export ACT_RUNNER_VERSION='0.2.12'
export ACT_RUNNER_SHA256='be020ea42303598dd7f0908675ddd7ce4a753eafecc5efe44ca96a22e34ba11e'
export GENTOO_IMAGE='gentoo/stage3:latest'
```

Open the dashboard at `http://192.168.2.100:30080`. It refreshes every 30 seconds. A worker appears only after its complete build and test run succeeds; there are no partial metrics while compilation is running. Deployment installs and starts the Debian worker services before creating the Gentoo Pods, then waits for all three worker names to report a non-offline status. Each Pod waits for its Debian worker runner before starting an initial build. Inspect a host runner with `systemctl status gitea-actions-runner` or `journalctl -u gitea-actions-runner` on the worker VM.

## Inspect builds

From the Debian administration VM:

```bash
ssh debian@192.168.2.100 'sudo kubectl -n gentoo-ruby get pods -o wide'
ssh -t debian@192.168.2.100 'sudo kubectl -n gentoo-ruby logs ruby-builder-k3s-worker-1-0 -f'
ssh -t debian@192.168.2.100 'sudo kubectl -n gentoo-ruby logs ruby-builder-k3s-worker-2-0 -f'
ssh -t debian@192.168.2.100 'sudo kubectl -n gentoo-ruby logs ruby-builder-k3s-worker-3-0 -f'
```

The initial Portage synchronization and dependency installation can take considerable time. Ruby 3.4.11 is compiled and tested as the unprivileged `builder` user, which is required for Ruby's permission tests. Every StatefulSet has a 5 Gi Longhorn volume for build data; runner registration remains on the Debian VM. A failed test run leaves its logs in the pod but does not publish metrics or a release.

## Start another build

Run the build as the same unprivileged user:

```bash
ssh -t debian@192.168.2.100 \
  'sudo kubectl -n gentoo-ruby exec ruby-builder-k3s-worker-1-0 -- runuser -u builder -- /opt/ruby-build/build-ruby'
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
./destroy-ruby
```

Use `./destroy-ruby --force` to skip confirmation. This removes the builder and dashboard Pods, all PVCs in `gentoo-ruby`, saved variables, and shell exports. The Gitea repository, releases, and published assets are preserved.
