# OpenClaw on NCP — disposable lifecycle

A disposable NCP VM lifecycle around the existing Terraform/Ansible baseline.
The VM is an execution cache: local metadata, the OS credential store and a
protected workspace backup are the durable boundary. Human approval is required
before NCP resource creation, upgrade, or destruction. Repository validation does
not perform VM deployment, apply, or destroy.

## Normal lifecycle

Use the root command rather than entering Terraform/Ansible details on every run:

```bash
./openclaw up --approve       # after reviewing the displayed plan; also types APPLY
./openclaw status
./openclaw down --approve     # after reviewing the displayed compute-only plan; also types DESTROY
./openclaw up                 # restore/recreate path
./openclaw upgrade --to 2026.9.6 --approve
```

The command stores only non-secret installation metadata in
`~/.config/openclaw-ncp/installation.json`, and stores NCP credentials plus the
cryptographically random Gateway token in the OS credential store
(`security` Keychain on macOS or `secret-tool`/libsecret on Linux). It refuses a plaintext fallback. The token is
reused after VM recreation and is not rotated by `up`; rotation is a separate
explicit workflow.

When no profile exists, `up` performs read-only NCP discovery of zones, images,
specs and reusable GEN subnets, displays only zone-compatible PUBLIC GEN
subnets for the selected Ubuntu/KVM/x86_64 VM conditions, and requires `REUSE` before adopting
one. A zone must be selected explicitly unless the profile or `--zone` supplies
one. Pressing Enter
proposes a dedicated **public** VPC/subnet with only the verified operator
`/32` SSH ingress needed for bootstrap; the current lifecycle path requires a
public IP to reach the host. Private-subnet deployment requires a separately
approved private access profile and is rejected rather than guessed. Ownership
is recorded as `reused` or `created`; `down` never destroys VPC/subnet resources. `up` writes a
protected Terraform plan, displays it, and requires `APPLY` before billable
creation. No credentials enter tfvars, argv, logs, Git, or Terraform state.

`down` first checks the persistent token and creates a protected, validated
workspace backup;
it intentionally excludes OpenClaw auth SQLite databases, device tokens, pairing
databases, Tailscale state, and credential files. It then displays the destroy
compute-only destroy plan and requires `DESTROY`. Dedicated VPC/subnet/ACG
resources are deliberately retained under the installation profile for safe
reuse; only the VM/NIC/public IP are returned automatically. The next `up` recreates the VM, reapplies the safe
workspace, re-converges OpenClaw, installs/enables Tailscale without placing an
auth key in automation, and runs health checks. Tailscale enrollment, ACL/tag
approval and Serve enablement remain explicit human gates because auth-key
lifecycle cannot safely be inferred. OpenClaw 2026.9.x auth and pairing state are SQLite-backed and must
not be copied blindly across a new VM identity; if needed, pair once with:

```bash
./scripts/pair-app.sh
```

The short-lived code, Tailscale ACL/device approval, and iOS approval remain human
gates. Gateway access remains loopback-only on port 18789 behind Tailscale Serve.
After each VM creation, the wrapper obtains candidate SSH keys with
`ssh-keyscan`, displays SHA256 fingerprints, and pauses for an out-of-band NCP
console/fingerprint check. It updates the protected `known_hosts` file only
after the operator types the verified fingerprint; a changed key additionally
requires `REPLACE-HOST-KEY`. Strict checking is then passed to both Ansible and
backup/restore SSH. A public bootstrap subnet is used only with the
operator's verified `/32` SSH source; port 18789 is never opened.
First install resolves a current supported OpenClaw stable/Node LTS pair and
records it; recreation reuses the recorded pair when available. `upgrade` is the
separate reviewed path for changing that release.

## Reproduction scope

The lifecycle selects the newest currently available Ubuntu LTS x86_64/KVM
image from live NCP metadata (or accepts `./openclaw up --release 24.04`,
`--image-number`, and `--zone` overrides). The selected release, image number,
spec and zone are recorded in installation metadata. Node **24.21.0**, npm **11.19.0**, OpenClaw **2026.9.6**,
user-owned systemd Gateway, linger, local/loopback/token authentication on 18789.
Defaults: user dev; shell/project directory /home/dev/workspace; independent agent
workspace /home/dev/.openclaw/workspace. Home and workspace values are configurable.
The deterministic baseline remains available for offline tests; lifecycle first
install resolves a supported pair and records it, while explicit overrides remain
reviewable inputs.

This reproduces the baseline, not a disk image: Ubuntu patch levels/apt packages,
npm transitive dependency ranges/native optional builds and NCP image availability
can vary. Top-level npm tarballs are hash-pinned; **no full npm dependency lock is
claimed**. Bit-for-bit/offline reproduction requires a reviewed artifact mirror and
transitive lock/build archive, outside this baseline. Terraform provider lock is committed.

## Model policy reproduced from the running server

The following is the read-only source-of-truth snapshot checked on **2026-09-27**
from the running OpenClaw 2026.9.6 host. The convergence helper manages these
values for a new host; it does not copy the origin host's config or credential
databases.

| Scope | Model/policy |
| --- | --- |
| coordinator and ordinary agents | `openai/gpt-5.6-luna` |
| researcher | `openai/gpt-5.6-luna` |
| writer and reviewer | `openai/gpt-5.6-terra` |
| utility | `openai/gpt-5.6-luna` |
| OpenAI rate limit, outage, or quota fallback | `nvidia/nemotron-3-ultra-550b-a55b` |

Token-saving controls are `contextPruning.mode=cache-ttl` with `ttl=1h`,
`compaction.mode=safeguard`, and `subagents.maxConcurrent=3` (with
`archiveAfterMinutes=60`). Coordinator delegation is `suggest`. The retired
`openai/gpt-6-astra` registry entry is removed by convergence; it is not a
selected or fallback model.

### Credential bootstrap (one time per host)

Credentials stay in OpenClaw's auth profiles and are never placed in Git,
Terraform state, Ansible vars/templates/inventory, or this README. After the
new host is provisioned, authenticate interactively on that host (or through a
trusted local terminal) and inspect only redacted status:

```bash
# Existing OpenAI OAuth profile; use the provider's interactive recovery only if needed.
openclaw models auth login --provider openai --method oauth

# NVIDIA free fallback: interactive prompt; do not pass the key as an argument.
openclaw models auth login --provider nvidia --method api-key

openclaw models status
```

Do not use `--nvidia-api-key` on a shell command line. Do not export a key in a
playbook or persist it in `terraform.tfvars`; if automation is required, pause
after provisioning and perform this bootstrap with a local secret manager or
masked terminal. The expected auth result is an OpenAI OAuth profile and an
OpenClaw-managed NVIDIA API-key profile; credential values themselves must never
be included in evidence or logs.

### Model verification and fallback test

Run `openclaw models status` and confirm the routing above, then make one short
GPT test and one explicit Nemotron test through the local Gateway. Use a fresh
private test session and do not use `--deliver`:

```bash
openclaw agent --agent coordinator --model openai/gpt-5.6-luna \
  --message 'Reply only: GPT route OK' --json
openclaw agent --agent coordinator --model nvidia/nemotron-3-ultra-550b-a55b \
  --message 'Reply only: Nemotron route OK' --json
```

This validates both credentials and model routing without stopping the Gateway.
It does not force a production rate-limit/quota event; fallback behavior is
verified by the authored config plus a direct fallback-model call. Review the
JSON only for success/model identity and redact any content before sharing it.

## Prerequisites

* Authorized **new** Ubuntu LTS x86_64 VM, sufficient memory/storage for npm native
  dependencies; outbound HTTPS/DNS to Node, npm, Ubuntu and package build sources.
* Controller: Python 3.12, Ansible-core 2.19.3, Terraform 1.9.8 (validated versions).
  Repository-local validation installations live in ignored .venv/.tools.
* NCP networking: `./openclaw up` discovers exact provider resources read-only and
  asks before reuse; otherwise it proposes a dedicated network. See [network
  modes, security and state migration](docs/networking.md). Compatible
  zone/image/spec, existing login key and approved SSH/egress paths are required.
  Direct Terraform examples default to private with no SSH ingress; the lifecycle
  bootstrap path explicitly creates or reuses a PUBLIC subnet with only the
  verified operator /32. No NAT is created implicitly.
  Review ACG and NACL rules and routes. Never open 18789 publicly.
* Verify the SSH host fingerprint through trusted NCP console/out-of-band information
  before adding it to known_hosts. ssh-keyscan alone does not establish trust.
* Bootstrap inventory account already has working SSH and root/passwordless sudo.
  NCP login key is for initial account recovery; it does not automatically install
  an authorized key for dev. Verification intentionally reuses bootstrap SSH + become.

### Tailscale access path

The role installs and enables `tailscaled`, but tailnet authentication and device
approval remain operator actions. The Gateway stays `local`/`loopback` on
`127.0.0.1:18789`; NCP ACG/NACL rules must not open TCP/18789. When the
tailnet is ready, the converger enables OpenClaw's managed Tailscale Serve mode,
which provides HTTPS on the tailnet and forwards to the loopback Gateway. It
does not use Funnel or bind the Gateway to a LAN address.

The environment-specific device-pair URL is supplied as the inventory variable
`openclaw_device_pair_public_url` (the host's MagicDNS HTTPS URL). Do not commit
the real hostname or any auth material.

## Terraform (from repository root)

Set NCP credentials using your approved local secret mechanism, not committed tfvars.
Copy terraform/terraform.tfvars.example to terraform/terraform.tfvars and select
an Ubuntu x86_64 image/spec explicitly when using Terraform directly. The root
wrapper performs live image/release selection. Provider 4.0.7 accepts image_number/spec
for KVM/XEN/RHV; legacy product-code pairs support only XEN/RHV. Never mix pairs.
The hypervisor label is an input guard, not live validation of the account image.
A primary NIC attaches supplied or dedicated restricted ACGs. See the three example
tfvars files in terraform/ and [network guidance](docs/networking.md). Existing ID
lookup errors fail closed, never trigger creation. Public IP allocation/server creation costs
money and requires a separate human decision.

```bash
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=reviewed.tfplan
# Only after reviewing costs, networking and receiving deployment approval:
# terraform -chdir=terraform apply reviewed.tfplan
```

Local state/plan files can contain sensitive infrastructure data. Keep them encrypted,
access controlled and backed up; do not commit them. This project does not configure
remote state. Never import or apply against the running origin host implicitly.

## First Ansible run (new host only)

1. Copy ansible/inventory.example.yml to ansible/inventory.yml; set the verified
   new IP, bootstrap username, private key location and host variables. Use inventory
   host vars for custom user/home/workspaces so deployment and verify agree.
2. Supply a new token from your local secret manager, or generate and store one
   locally with openssl rand -hex 32. Do not paste credentials into chat or argv.
3. From repository root:

```bash
cd ansible
# OPENCLAW_GATEWAY_TOKEN must already be in this process environment.
ansible-playbook -i inventory.yml playbook.yml -e openclaw_new_host_ack=true
unset OPENCLAW_GATEWAY_TOKEN
cd ..
./scripts/verify.sh inventory.yml
```

verify.sh resolves relative inventory paths from ansible/. An absolute inventory
path also works. Set ANSIBLE_PLAYBOOK to the absolute local .venv/bin/ansible-playbook
if not on PATH. Both playbooks require trusted SSH host keys. Do not disable checking.

For a host that has not joined the tailnet, leave `openclaw_tailscale_ready: false`
and omit the public URL on the first run. Then complete the authenticated boundary
manually over trusted bootstrap SSH:

```bash
sudo tailscale up
sudo tailscale status
```

Approve the device and its tags/ACLs in the tailnet administration workflow.
Set these host-specific values in the uncommitted inventory (or an approved
configuration mechanism), then rerun the playbook and verifier:

```yaml
openclaw_tailscale_ready: true
openclaw_device_pair_public_url: https://HOST.TAILNET.example
```

OpenClaw then manages `gateway.tailscale.mode: serve` to
`http://127.0.0.1:18789`. Do not run Funnel or expose 18789 in NCP networking.
The setup-code pairing is also a manual, short-lived approval step:

```bash
openclaw qr --setup-code-only
```

Use the code in the iOS app, approve the pending OpenClaw device through the
normal device workflow, and confirm the app's WSS connection. Setup codes,
device credentials, and Tailscale auth keys must not be copied into inventory,
logs, Terraform state, or Git.

## Rerun and secrets lifecycle

Rerun the same playbook/acknowledgement **without** exporting a token: the existing
0600 gateway.env is reused. Missing token file on a first run fails closed. Different
supplied token on an existing host fails unless openclaw_rotate_token=true is explicit.
Rotation requires the newly supplied token; protect/update client credentials and
verify RPC health after the restart. Malformed managed files fail rather than being
overwritten. Back up the token separately in an approved secret store.

Token values travel only through protected process environment/private files, never
shell interpolation, CLI argv, config text or ordinary Ansible logs. no_log also
hides operational failures: inspect protected host logs locally without sharing
credential-bearing output. Root and the service user can still read the env/token;
SecretRef is not encryption or protection against a compromised service account.

The helper validates and recursively patches only managed gateway keys, agent default
workspace and its reserved ncp_env provider. Unrelated channels/models/agents/bindings
are preserved. JSON5 comments may be removed by OpenClaw's supported writer; inspect
its local backups. Reserved provider conflicts fail. Existing production config or
auth stores must NOT be copied into this project/new host automatically.

EnvironmentFile drop-in is present **before** gateway install, which installs AND
starts in 2026.9.6. Gateway auth SecretRef is resolved in the installer environment
but not persisted as plaintext by the installer. The original generated unit is
not replaced by a custom template. A local fingerprint detects unit/spec drift;
package/config/token/drop-in changes restart the service. Unchanged config is not
rewritten; unchanged healthy services are not restarted. Node runtime drift fails
verification rather than silently using a different system Node.

## Verification and recovery

The verifier checks exact runtime versions, config/schema, active+enabled user unit,
authenticated Gateway health RPC on explicit loopback URL, agent workspace and **all**
listeners on the Gateway port (any external/wildcard listener fails). It retries
startup health for up to about a minute. It never prints config/token/health payloads.

On a failed first run, fix the reported package/network/permission/secret prerequisite
and rerun with the same token. A partial preparation may already have written the
protected token; do not generate a replacement casually. Config validation precedes
service installation. CLI backup files can include secrets if you manually added
plaintext later: protect the whole state directory. For rollback on a new host,
review local config backups and restore only intended keys with the service stopped
under a separately approved operator procedure; never restore the origin host's auth.
For lost token, explicitly rotate and reconnect clients; avoid deleting the whole state.

## Intentional differences from inspected origin (2026-09-25)

Confirmed read-only: Ubuntu 24.04.4; Node 24.21.0; npm 11.19.0;
OpenClaw 2026.9.6 (eb377ac); dev uid 1001; linger yes; gateway local/loopback/18789,
token auth with string token; default agent workspace /home/dev/.openclaw/workspace.
No secret values copied. Reproduction uses a dedicated /opt Node archive rather than
the origin package manager layout; service uid is resolved, not forced to 1001;
token is a newly supplied env SecretRef rather than the origin plaintext string.
No operator groups/sudo grants, SSH keys, models, Codex credentials,
plugins or agent-specific workspaces are cloned. Prior Codex version drift is not a
freshly verified fact and is not reproduced as a target.

### App integration checklist (after baseline acceptance)

* Configure models through installed `openclaw configure`; complete account login locally.
* From the PC, run `./scripts/pair-app.sh` once the second Ansible phase is complete.
  The script reads the private inventory's `openclaw_device_pair_public_url` and
  `openclaw_user`, so the host does not need to be typed at runtime. Scan the displayed
  short-lived setup code in the official
  OpenClaw app and approve the pending device.
* Review/install compatible Codex/plugin versions only under separate approval; authenticate
  the new host yourself. Never copy origin credential databases or request broader scopes.
* Review sessions/agents/bindings and intended workspace permissions; configure explicitly.
* Send a harmless read-only test message from the app, then request a small code change
  in the approved `/home/dev/workspace` project and inspect the diff before accepting it.

The one-line PC entry point is:

```bash
./scripts/pair-app.sh
```

For a one-off connection without a private inventory, pass the target explicitly:

```bash
./scripts/pair-app.sh dev@TAILNET_MAGICDNS_NAME
```

The Tailscale hostname cannot be safely guessed before the device joins the tailnet;
it is environment-specific. Store it once in uncommitted `ansible/inventory.yml`, then
the no-argument command resolves it automatically. After pairing, the app uses the Tailscale Serve HTTPS URL and the Gateway remains
loopback-only. No chat-channel plugin configuration is required.

## Local validation and evidence

```bash
mkdir -p .tools
ANSIBLE_LOCAL_TEMP="$PWD/.tools/ansible-tmp" .venv/bin/ansible-playbook -i ansible/inventory.example.yml ansible/playbook.yml --syntax-check
NCP_REAL_CLI_TEST=1 .venv/bin/python -m unittest discover -s tests -v
.tools/terraform -chdir=terraform init -backend=false -input=false
.tools/terraform -chdir=terraform validate
```

The real CLI test needs installed 2026.9.6 in ~/.npm-global/bin; it isolates HOME,
state and config entirely below .tools and never starts a Gateway. Service idempotency
is mocked, not a VM/systemd integration test. See evidence/REPORT.md for results and
remaining gates. No full playbook is run on localhost, even with --check.

The model-policy unit test also checks the authored routing, token-saving controls,
fallback, coordinator delegation mode, and removal of the legacy gpt-6-astra entry.
The read-only server checks used for the snapshot were `openclaw models status`,
redacted config inspection, `openclaw config get` for the policy paths, and
`openclaw config validate`; no production config was changed during that audit.

Sources: installed 2026.9.6 docs/cli/config.md, docs/cli/gateway.md,
docs/gateway/secrets/secretref-contract.md; dist/gateway-install-token-BO-3h7CJ.mjs
and dist/daemon-install-helpers-DxMwN6NT.mjs.
Public references: https://docs.openclaw.ai/cli/config,
https://nodejs.org/dist/v24.21.0/SHASUMS256.txt,
https://github.com/NaverCloudPlatform/terraform-provider-ncloud/blob/v4.0.7/docs/resources/server.md.
Node SHA256 is in role defaults; npm URL/SRI/SHA256 are in files/npm-artifacts.json;
Python wheel hashes and Terraform CLI checksum are in evidence/.
