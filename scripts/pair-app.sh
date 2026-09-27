#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[A-Za-z0-9._:-]+@[A-Za-z0-9._:-]+$ ]]; then
  printf 'Usage: %s SSH_USER@TAILNET_HOST\n' "$0" >&2
  exit 64
fi

target=$1
cat >&2 <<'NOTICE'
The next output is a short-lived OpenClaw device setup code. Scan it only in
the official OpenClaw app. Do not copy it into Git, chat, inventory, logs, or
the shell history; it expires after one use.
NOTICE

# The remote command is constant; no token or secret is passed in argv. The
# protected env file is sourced only inside the remote login shell because QR
# generation may need the Gateway SecretRef in the installed CLI version.
exec ssh -tt -o StrictHostKeyChecking=yes -o BatchMode=yes -- "$target" 'exec bash -lc '\''
  set -a
  . "$HOME/.config/openclaw/gateway.env"
  set +a
  export PATH="$HOME/.npm-global/bin:/opt/node-v24.21.0-linux-x64/bin:/usr/bin:/bin"
  exec openclaw qr --setup-code-only
'\'''
