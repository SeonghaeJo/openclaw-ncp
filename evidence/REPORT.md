# Review evidence — 2026-09-25 (deployment approval pending)

Repository: /home/dev/workspace/openclaw-ncp-v2. No prior Git metadata, no AGENTS.md
in repository or checked ancestor locations. Supplied baseline preserved as bc51695.
Git identity was unset; commits use per-command OpenClaw Automation
<automation@openclaw.invalid>, without changing global/local identity configuration.

## Executed checks

- Baseline and final candidate heuristic secret scans: PASS (not a formal secret audit).
- Ubuntu/Node/npm/OpenClaw/id/linger/loopback/config nonsecret field readback: recorded
  in README. No auth payloads printed, copied or committed.
- Ansible-core 2.19.3 syntax: deploy and verify playbooks PASS (ansible-syntax.txt).
- Python unittest: 7 cases including explicit authored model-policy/legacy-removal
  assertions; real isolated OpenClaw 2026.9.6 schema/config
  initialization + second run byte stability + unrelated-field preservation;
  token first/reuse/rotation/malformed cases; mocked service install/restart/spec drift;
  negative wildcard/external listeners; YAML/EnvironmentFile render/SSH policy.
  Full output: tests.txt. Mock tests do NOT prove systemd or VM deployment.
- Terraform 1.9.8 init -backend=false: PASS; provider 4.0.7 lock generated and committed.
  No account credentials, plan, apply or paid resources used. Provider signature details
  are preserved in terraform-init.txt. validate PASS in terraform-validate.txt; fmt PASS.
- bash -n verify.sh, Python compile and git diff --check: PASS.

## Tool/artifact provenance

System ensurepip unavailable; no system packages installed. A repository-local venv
was seeded with PyPI pip 25.2 wheel, SHA256
6d67a2b4e7f14d8b31b8b52648866fa717f45a1eb70e83002f4331d07e953717.
Every validation wheel was compared to the matching PyPI release JSON SHA256.
Exact downloaded wheel names/hashes: python-wheels.sha256. Tool/cache directories
are ignored. Terraform archive from releases.hashicorp.com/terraform/1.9.8 was
verified against its published SHA256SUMS (terraform-cli.sha256); this validates
transport/hash consistency, not an independent signing-key trust audit.
Node archive checksum from nodejs.org/dist/v24.21.0/SHASUMS256.txt is fixed in defaults.
Top-level npm/openclaw tarballs were downloaded locally and matched published SHA512
SRI plus committed SHA256 (role files/npm-artifacts.json). Deployment verifies the
committed SHA256 before npm installation. Transitive npm/apt dependency closure is
not locked; baseline-version reproduction is narrower than bit-for-bit reproduction.

## Important discovered behavior

Installed gateway install help explicitly says install AND start. Installed
SecretRef installer source suppresses persisted gateway token; required drop-in is
written before installation. Installed config get redacts provider source/allowlist
as well as credentials, so it cannot be used for equality/idempotency. Helper privately
parses authored JSON5 through the pinned application's json5 dependency, then uses
supported config patch --stdin --dry-run and config patch for validated merges.
Tests exposed and fixed both redaction and required-path errors rather than accepting
mock-only validation. Terraform validate caught an empty NIC name, fixed before handoff.

## Remaining acceptance gates

1. Independent reviewer code/security QA.
2. Human-approved disposable NCP Ubuntu VM: full first run, second run (zero desired
   changes), service reboot/linger, restart-after-change and token rotation/recovery.
3. Confirm image/spec/subnet/zone/ACG/NACL/account prerequisites and SSH fingerprint.
4. Confirm actual fresh npm/native dependency install with current upstream registry;
   it was NOT executed on the origin host or in a fresh VM.
5. Separately approve/configure model/Discord/Codex account auth and minimal scopes.

Do not call this production-ready or exact disk reproduction. Origin service/runtime
configuration was never changed/restarted; no deployment playbook ran against it.
