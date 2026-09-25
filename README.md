# OpenClaw on NCP — v2

Reproducible baseline for the inspected NCP/OpenClaw host.

## v2 fixes
- Node.js 24 via NodeSource instead of Ubuntu default Node.
- Gateway configured before service start: local / loopback / 18789 / token.
- Gateway token supplied externally and stored as an environment SecretRef.
- NCP provider pinned to 4.0.7 with `support_vpc = true`.
- Linger/user systemd manager prepared before Gateway service installation.
- Verification for Node, OpenClaw, Gateway config/service/listener.

## Target
- Ubuntu 24.04 family
- user `dev`
- Node 24.x
- OpenClaw 2026.9.6 (variable)
- `/home/dev/workspace`
- systemd user Gateway
- listener `127.0.0.1:18789`

Discord, OpenAI account state, and Codex are deliberately not automated in v2.

## Secrets
Before Ansible:

```bash
export OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
```

Do not commit this token, Discord/OpenAI credentials, NCP keys, or SSH keys.

## Terraform

```bash
export NCLOUD_ACCESS_KEY='...'
export NCLOUD_SECRET_KEY='...'
export NCLOUD_REGION='KR'

cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

v2 reuses an existing VPC subnet; it does not guess account-specific VPC/ACG/image/spec values.

## Ansible

```bash
cd ../ansible
cp inventory.example.yml inventory.yml

ansible-playbook -i inventory.yml playbook.yml
```

The playbook reads `OPENCLAW_GATEWAY_TOKEN` from its environment.

## Verify

```bash
./scripts/verify.sh SERVER_IP
```

Expected listener: `127.0.0.1:18789`.

## Discord after bootstrap

```bash
sudo -iu dev
openclaw channels add --channel discord
openclaw gateway restart
openclaw channels status --probe
```

Use a channel allowlist and your own Discord account as operator if admin-from-chat is required.

## Codex
Not automated. The inspected host had OpenClaw 2026.9.6 with Codex plugin 2026.9.5, causing official-plugin version drift.

## Next
- optional VPC/subnet/ACG creation
- declarative Discord/agents/bindings
- external secret store
- Java 21, Docker, GitHub auth
- remote Terraform state
