#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/ansible"
exec "${ANSIBLE_PLAYBOOK:-ansible-playbook}" -i "${1:?usage: verify.sh INVENTORY_PATH}" verify.yml
