# Network extension verification — 2026-09-26

Base: 4a1664a; initial working tree clean. Provider lock unchanged: ncloud 4.0.7.
CLI: repository-local Terraform 1.9.8. Installed provider JSON schema and official
v4.0.7 VPC/subnet/ACG/rule documentation inspected (links in docs/networking.md).

Executed successfully:
* scripts/test-network.sh: recursive fmt check, validate, 17 mock plan runs;
  2 additional expected nonzero provider-schema CIDR rejection tests.
  Full output: network-tests.txt.
* NCP_REAL_CLI_TEST=1 .venv/bin/python -m unittest discover -s tests -v:
  6/6 including isolated real CLI configuration regression. network-regression.txt.
* Ansible playbook syntax check with example inventory: passed.
* git diff --check: passed.

Mock tests cover all three modes, legacy primary NIC/ACG wiring/public-IP behavior,
private/no-ingress defaults, explicit public/SSH opt-in, contradictory modes/IDs,
missing IDs, VPC/subnet/ACG membership, zone mismatch, CIDR scope/containment,
private/public incompatibility and world SSH rejection. Provider rejects malformed
and noncanonical CIDRs even with mock_provider; wrapper verifies diagnostic and
nonzero exit rather than suppressing failures.

No real credentials/operational tfvars/state were read. No live account plan,
Terraform apply/destroy, paid resource creation, push or PR. Mock test teardown has
no created resources because every run is command=plan. No VM/network deployment.

Limits: mocks do not prove lookup/auth error behavior at NCP, available zones,
other-subnet overlap, quotas, route/NACL defaults, Internet/SSH, runtime bootstrap,
state migration or live second-run zero-diff. Separate approved live review required.
