# OpenClaw on NCP — reviewed v2 draft

A **new-host reproduction baseline**, not an upgrader for the running origin host.
Human approval is required for deployment/resource creation. No VM deployment or
Terraform apply was performed during this review; production readiness is not proven.

## Reproduction scope

Ubuntu 24.04 x86_64, Node **24.21.0**, npm **11.19.0**, OpenClaw **2026.9.6**,
user-owned systemd Gateway, linger, local/loopback/token authentication on 18789.
Defaults: user dev; shell/project directory /home/dev/workspace; independent agent
workspace /home/dev/.openclaw/workspace. Home and workspace values are configurable.
Changing pinned runtime versions requires reviewing checksums, CLI behavior and tests;
role assertions deliberately reject unreviewed version overrides.

This reproduces the baseline, not a disk image: Ubuntu patch levels/apt packages,
npm transitive dependency ranges/native optional builds and NCP image availability
can vary. Top-level npm tarballs are hash-pinned; **no full npm dependency lock is
claimed**. Bit-for-bit/offline reproduction requires a reviewed artifact mirror and
transitive lock/build archive, outside this baseline. Terraform provider lock is committed.

## Prerequisites

* Authorized **new** Ubuntu 24.04 x86_64 VM, sufficient memory/storage for npm native
  dependencies; outbound HTTPS/DNS to Node, npm, Ubuntu and package build sources.
* Controller: Python 3.12, Ansible-core 2.19.3, Terraform 1.9.8 (validated versions).
  Repository-local validation installations live in ignored .venv/.tools.
* Existing NCP VPC PUBLIC/GEN subnet, compatible zone/image/spec, routing and Internet
  access; existing login key; 1–3 existing ACGs from the same VPC. ACG **and NACL**
  allow SSH only from operator IP/CIDR, required outbound traffic and return traffic.
  Never open 18789 publicly. No VPC/NACL/ACG creation or rule editing is automated.
* Verify the SSH host fingerprint through trusted NCP console/out-of-band information
  before adding it to known_hosts. ssh-keyscan alone does not establish trust.
* Bootstrap inventory account already has working SSH and root/passwordless sudo.
  NCP login key is for initial account recovery; it does not automatically install
  an authorized key for dev. Verification intentionally reuses bootstrap SSH + become.

## Terraform (from repository root)

Set NCP credentials using your approved local secret mechanism, not committed tfvars.
Copy terraform/terraform.tfvars.example to terraform/terraform.tfvars and select
Ubuntu 24.04 x86_64 image/spec explicitly. Provider 4.0.7 accepts image_number/spec
for KVM/XEN/RHV; legacy product-code pairs support only XEN/RHV. Never mix pairs.
The hypervisor label is an input guard, not live validation of the account image.
A primary NIC attaches the supplied ACGs. Public IP allocation/server creation costs
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
No operator groups/sudo grants, SSH keys, models, Discord/Codex credentials,
plugins or agent-specific workspaces are cloned. Prior Codex version drift is not a
freshly verified fact and is not reproduced as a target.

### Manual integration checklist (after baseline acceptance)

* Configure models through installed openclaw configure; complete account login locally.
* Configure Discord with openclaw channels add discord / configure, using masked local
  prompts. Check installed command help first. Choose minimal channel allowlists and
  explicit owner/operator rules; never infer owner authority from channel membership.
* Review/install compatible Codex/plugin version only under separate approval; authenticate
  the new host yourself. Never copy origin credential databases or request broader scopes.
* Review sessions/agents/bindings and intended workspace permissions; configure explicitly.
* Restart only the new Gateway when approved; test channels and model responses separately.

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

Sources: installed 2026.9.6 docs/cli/config.md, docs/cli/gateway.md,
docs/gateway/secrets/secretref-contract.md; dist/gateway-install-token-BO-3h7CJ.mjs
and dist/daemon-install-helpers-DxMwN6NT.mjs.
Public references: https://docs.openclaw.ai/cli/config,
https://nodejs.org/dist/v24.21.0/SHASUMS256.txt,
https://github.com/NaverCloudPlatform/terraform-provider-ncloud/blob/v4.0.7/docs/resources/server.md.
Node SHA256 is in role defaults; npm URL/SRI/SHA256 are in files/npm-artifacts.json;
Python wheel hashes and Terraform CLI checksum are in evidence/.
