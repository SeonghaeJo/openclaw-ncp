#!/usr/bin/env bash
# Offline plan-only tests, including provider-schema failures.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${TERRAFORM:-$ROOT/.tools/terraform}"
"$TF" -chdir="$ROOT/terraform" fmt -check -recursive
"$TF" -chdir="$ROOT/terraform" validate -no-color
"$TF" -chdir="$ROOT/terraform" test -no-color
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Copy only configuration, NEVER credentials/tfvars/state.
cp "$ROOT"/terraform/*.tf "$ROOT/terraform/.terraform.lock.hcl" "$TMP/"
ln -s "$ROOT/terraform/.terraform" "$TMP/.terraform"
mkdir "$TMP/tests"
for cidr in '10.20.1.1/24' 'oops'; do
  cat > "$TMP/tests/invalid.tftest.hcl" <<HCL
mock_provider "ncloud" {}
run "provider_rejects_cidr" {
  command = plan
  variables {
    login_key_name = "offline-test"
    server_image_number = "12345"
    server_spec_code = "test-spec"
    vpc_mode = "create"
    subnet_mode = "create"
    vpc_cidr = "10.20.0.0/16"
    subnet_cidr = "$cidr"
    zone = "KR-2"
  }
  expect_failures = [terraform_data.network_contract]
}
HCL
  if "$TF" -chdir="$TMP" test -no-color > "$TMP/result" 2>&1; then
    echo "FAIL: provider accepted invalid CIDR $cidr"; exit 1
  fi
  grep -q 'CIDRBlock Type Validation Error' "$TMP/result" || { cat "$TMP/result"; exit 1; }
  echo "PASS: provider rejects $cidr (expected nonzero)"
done
