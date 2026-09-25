#!/usr/bin/env bash
set -euo pipefail
HOST="${1:?usage: $0 SERVER_IP}"
USER="${OPENCLAW_SSH_USER:-dev}"

ssh "${USER}@${HOST}" '
  set -euo pipefail
  export PATH="$HOME/.npm-global/bin:$PATH"
  echo "== Node/npm =="; node --version; npm --version
  echo "== OpenClaw =="; openclaw --version
  echo "== Gateway config =="
  openclaw config get gateway.mode
  openclaw config get gateway.bind
  openclaw config get gateway.port
  openclaw config get gateway.auth.mode
  echo "== Gateway =="; openclaw gateway status
  echo "== Listener =="; ss -ltn | grep "127.0.0.1:18789"
  echo "== Workspace =="; test -d "$HOME/workspace"; ls -ld "$HOME/workspace"
'
