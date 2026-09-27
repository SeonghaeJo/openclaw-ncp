#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [SSH_USER@TAILNET_HOST]\n' "$0" >&2
  exit 64
fi

if [[ $# -eq 1 ]]; then
  target=$1
else
  inventory=${OPENCLAW_INVENTORY:-ansible/inventory.yml}
  if [[ ! -f "$inventory" ]]; then
    printf 'No target supplied and inventory not found: %s\n' "$inventory" >&2
    printf 'Set openclaw_device_pair_public_url in the private inventory or pass SSH_USER@TAILNET_HOST.\n' >&2
    exit 64
  fi
  if ! command -v ansible-inventory >/dev/null 2>&1; then
    printf 'ansible-inventory is required for automatic target discovery; pass SSH_USER@TAILNET_HOST instead.\n' >&2
    exit 69
  fi
  target=$(ansible-inventory -i "$inventory" --host openclaw --json | python3 -c '
import json, re, sys
from urllib.parse import urlsplit
data = json.load(sys.stdin)
url = data.get("openclaw_device_pair_public_url", "")
host = urlsplit(url).hostname if url else None
user = data.get("openclaw_user", "dev")
if not host or not re.fullmatch(r"[A-Za-z0-9._:-]+", host) or not re.fullmatch(r"[A-Za-z0-9._:-]+", user):
    raise SystemExit("inventory needs openclaw_device_pair_public_url=https://HOST and a safe openclaw_user")
print(user + "@" + host)
')
fi

if [[ ! "$target" =~ ^[A-Za-z0-9._:-]+@[A-Za-z0-9._:-]+$ ]]; then
  printf 'Invalid SSH target: %s\n' "$target" >&2
  exit 64
fi
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
