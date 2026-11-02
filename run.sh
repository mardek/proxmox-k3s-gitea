#!/usr/bin/env bash
set -euo pipefail

control_plane_address=${CONTROL_PLANE_ADDRESS:-192.168.2.100}
gitea_port=${GITEA_PORT:-8080}
state_dir=${RUN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/proxmox-k3s-gitea}
pid_file=$state_dir/gitea-port-forward.pid
log_file=$state_dir/gitea-port-forward.log

usage() {
  cat <<'EOF'
Usage: ./run.sh [start|stop|restart|status|foreground]
       ./run.sh -h | --help

Manage persistent access to Gitea through a background SSH port-forward.
The default command is start. The process survives terminal and SSH logout.

Commands:
  start       Start the port-forward unless it is already running.
  stop        Stop the background port-forward.
  restart     Restart the background port-forward.
  status      Show whether the port-forward is running.
  foreground  Run in the terminal without detaching (stops with Ctrl+C).
  -h, --help  Show this manual.

Environment overrides:
  CONTROL_PLANE_ADDRESS  Control-plane SSH address (default: 192.168.2.100).
  GITEA_PORT             Browser and port-forward port (default: 8080).
  RUN_STATE_DIR          Alternate PID and log directory.

Open http://192.168.2.100:8080 after starting. Logs and the PID file are
stored under ~/.local/state/proxmox-k3s-gitea by default.
EOF
}

running() {
  [[ -s $pid_file ]] && kill -0 "$(<"$pid_file")" 2>/dev/null
}

start() {
  if running; then
    printf 'Gitea port-forward is already running (PID %s).\n' "$(<"$pid_file")"
    status
    return
  fi
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  rm -f "$pid_file"
  nohup ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    "debian@${control_plane_address}" \
    "sudo env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n gitea port-forward svc/gitea ${gitea_port}:80 --address 0.0.0.0" \
    >>"$log_file" 2>&1 </dev/null &
  printf '%s\n' "$!" > "$pid_file"
  sleep 1
  if ! running; then
    rm -f "$pid_file"
    printf 'Gitea port-forward failed to start. See %s\n' "$log_file" >&2
    exit 1
  fi
  printf 'Started Gitea port-forward (PID %s).\n' "$(<"$pid_file")"
  printf 'Open: http://%s:%s\nLog: %s\n' "$control_plane_address" "$gitea_port" "$log_file"
}

stop() {
  if ! running; then
    rm -f "$pid_file"
    echo 'Gitea port-forward is not running.'
    return
  fi
  pid=$(<"$pid_file")
  kill "$pid"
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done
  rm -f "$pid_file"
  echo 'Gitea port-forward stopped.'
}

status() {
  if running; then
    printf 'Running (PID %s): http://%s:%s\n' "$(<"$pid_file")" "$control_plane_address" "$gitea_port"
  else
    echo 'Stopped.'
    return 1
  fi
}

foreground() {
  ssh-keygen -R "$control_plane_address" >/dev/null 2>&1 || true
  ssh-keygen -R "[${control_plane_address}]:22" >/dev/null 2>&1 || true
  printf '\nOpen this URL in your browser: http://%s:%s\n' "$control_plane_address" "$gitea_port"
  printf 'Login user: admin\nKeep this terminal open. Press Ctrl+C to stop access.\n\n'
  exec ssh -t -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "debian@${control_plane_address}" \
    "sudo env KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl -n gitea port-forward svc/gitea ${gitea_port}:80 --address 0.0.0.0"
}

command_name=${1:-start}
if (($# > 1)); then
  usage >&2
  exit 2
fi
case $command_name in
  -h|--help) usage; exit 0 ;;
  start|stop|restart|status|foreground) ;;
  *) printf 'Unknown command: %s\n\n' "$command_name" >&2; usage >&2; exit 2 ;;
esac

for required_command in ssh ssh-keygen; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command is required" >&2
    exit 1
  fi
done
if [[ ! $gitea_port =~ ^[0-9]+$ || $gitea_port -lt 1 || $gitea_port -gt 65535 ]]; then
  echo 'GITEA_PORT must be between 1 and 65535' >&2
  exit 2
fi

case $command_name in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  foreground) foreground ;;
esac
