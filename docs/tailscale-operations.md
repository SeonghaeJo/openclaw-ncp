# Tailscale operator runbook

Terraform provisions NCP networking and the VM. Ansible installs `tailscale`
and enables `tailscaled`; an authorized operator must run `tailscale up` and
approve the device in the tailnet. Auth keys are not accepted as ordinary
Ansible variables and must come from an approved secret manager.

## Required network shape

The Gateway remains `local`/`loopback` on port `18789`. The converger manages
`gateway.trustedProxies` as `127.0.0.1` and `::1`. After tailnet approval and a
rerun with `openclaw_tailscale_ready: true`, OpenClaw's
`gateway.tailscale.mode: serve` provides the HTTPS tailnet route to the loopback
Gateway. Do not use Funnel or open TCP/18789 in NCP ACG, NACL, host firewall,
or LAN interfaces.

## Two-phase enrollment

1. Run Ansible with `openclaw_tailscale_ready: false`.
2. Over trusted bootstrap SSH, run `sudo tailscale up`, complete browser/admin
   approval, and verify with `sudo tailscale status`.
3. Set the uncommitted host-specific `openclaw_device_pair_public_url` to the
   HTTPS MagicDNS URL and set `openclaw_tailscale_ready: true`.
4. Rerun the playbook and `./scripts/verify.sh inventory.yml`.
5. From the operator PC, run `./scripts/pair-app.sh dev@HOST.TAILNET.example`.
   Scan the displayed setup code in the official OpenClaw app, approve the pending
   device, and confirm WSS from the real app. The script never receives or prints
   the Gateway token.

The role does not automate tailnet login, ACL/tag approval, QR delivery, or
device approval. Those actions require an authorized human and may produce
short-lived or private credentials. Never record them in repository evidence.

If Tailscale reports `NoState`, complete login before setting
`openclaw_tailscale_ready: true`. If Serve cannot start, inspect protected
host logs and tailnet policy; do not solve it by changing Gateway bind mode.
The verifier continues to reject any non-loopback listener on port 18789.
