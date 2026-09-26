# Network selection and ownership (deployment draft)

기존 ID를 지정해 재사용하거나 새 환경 생성을 명시적으로 선택합니다. ID 오타·조회 실패·권한 오류를 부재로 오인하여 자동 생성하지 않습니다. Names label new resources only; no name-based adoption.

| vpc_mode | subnet_mode | Inputs |
| --- | --- | --- |
| reuse (default) | reuse (default) | subnet_no; optional vpc_no checks membership, otherwise inferred from exact subnet lookup |
| reuse | create | vpc_no, subnet_cidr, zone |
| create | create | vpc_cidr, subnet_cidr, zone; no existing IDs or ACGs |

Create/reuse is invalid. Creation rejects corresponding IDs; reuse rejects creation CIDRs. Existing VPC/subnet/ACG data sources are read-only; lookup errors stop planning. Empty ACG list creates a dedicated ACG. Legacy lists remain attached to primary NIC order 0.

Canonical RFC1918 IPv4 /16–/28 CIDRs are required; subnet must fit within VPC. New subnets use GEN. Optional zone on reuse checks equality. NCP must still validate region/zone availability, overlapping existing subnets, quotas and image/spec compatibility.

## Security and reachability

* New subnets default PRIVATE, no public IP; dedicated ACG has no ingress. ssh_source_cidrs adds TCP/22 only. Prefer operator /32 or narrow VPN/bastion ranges; /0 through /7 are rejected, not a guarantee that every other range is safe. No Gateway 18789 or other management port is opened.
* Dedicated ACG egress permits TCP 80/443, TCP+UDP 53, UDP 123 to all destinations for bootstrap/DNS/time; no arbitrary port range. ACG is stateful.
* New subnet uses selected VPC's default NACL. VPC creation exposes platform-created default NACL and public/private route tables. No standalone ACL, route rule/association, NAT or paid helper is created. Existing defaults are not reset. Review actual default NACL rules, stateless return traffic and subnet route-table associations/routes in NCP before deployment.
* PRIVATE alone supplies neither Internet nor controller SSH access. Arrange separately approved existing VPN/bastion/controller and NAT/proxy/mirror paths as needed. Fresh private defaults intentionally are not immediately Ansible-bootstrap-ready. No NAT is silently provisioned.
* For direct public SSH explicitly choose PUBLIC + allocate_public_ip=true and narrow SSH sources. Verify IGW/default public routes, NACL and host firewall. Public IP/VM cost money; public subnet alone does not guarantee SSH.
* Legacy reuse retains public IP allocation when omitted. PRIVATE reuse requires allocate_public_ip=false. Existing ACG/NACL rules may be broad; this module does not harden them. Audit before deploying, never expose 18789; use SSH tunneling to loopback.

## State and migration

Keep stable state and modes. Created resources are owned at ncloud_vpc.managed[0], ncloud_subnet.managed[0], ncloud_access_control_group.managed[0]. Reruns resolve state IDs, not names. Lost state requires protected backup restoration or explicit approved imports, never name adoption.

Mode/CIDR/zone/subnet/ACG changes may remove or replace resources and server/NIC. Disabling public IP releases it. Managed VPC/subnet/ACG prevent_destroy guards block destruction including count-to-zero while blocks remain, but removing configuration or editing state can bypass them. Never remove guards merely to make a plan pass. Review all destroys/replacements.

Reuse requires no import. To intentionally adopt verified resources: obtain ownership approval, back up state, set create inputs to exact live attributes, then run separately approved imports (examples only, not executed):

```bash
terraform -chdir=terraform import 'ncloud_vpc.managed[0]' VERIFIED_VPC_ID
terraform -chdir=terraform import 'ncloud_subnet.managed[0]' VERIFIED_SUBNET_ID
```

Review a fresh plan for zero unintended changes. ACG adoption also needs its single rule owner; rule management may replace all rules, so do not import shared/default ACGs. Relinquishing ownership needs a separately reviewed state-only migration, e.g. removed blocks with destroy=false in a suitable migration configuration, not a blind create→reuse toggle or state deletion.

Public IP address migration from ncloud_public_ip.openclaw to [0] has a moved block. Legacy default plans should not recreate it solely for this change. Server/NIC addresses are unchanged. A new local terraform_data contract is expected.

## Validation and sources

Configuration floor remains Terraform >=1.6; mock tests require >=1.7. Validated CLI: 1.9.8, locked NaverCloudPlatform/ncloud 4.0.7. Run fmt -check -recursive, validate, and test with -chdir=terraform. All tests use command=plan and mock_provider: no credentials/API/apply/destroy. Real VM, SSH/Internet, NACL/routes, migration and live rerun idempotency remain unverified gates. API auth/lookup failures are not simulated; they are deliberately not caught.

Version-pinned official provider docs inspected alongside installed providers schema -json (default ACL/route outputs, subnet required ACL/zone/type, ACG VPC and NIC schema):
* https://github.com/NaverCloudPlatform/terraform-provider-ncloud/blob/v4.0.7/docs/resources/vpc.md
* https://github.com/NaverCloudPlatform/terraform-provider-ncloud/blob/v4.0.7/docs/resources/subnet.md
* https://github.com/NaverCloudPlatform/terraform-provider-ncloud/blob/v4.0.7/docs/resources/access_control_group.md
* https://github.com/NaverCloudPlatform/terraform-provider-ncloud/blob/v4.0.7/docs/resources/access_control_group_rule.md

Run ./scripts/test-network.sh for the full offline suite (including two expected
provider-schema CIDR failures). Evidence: evidence/NETWORK-REPORT.md and logs.
Choose one example, copy it to terraform/terraform.tfvars, replace placeholders,
and review the plan; do not load all three examples together.
