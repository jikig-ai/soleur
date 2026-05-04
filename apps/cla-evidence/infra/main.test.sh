#!/usr/bin/env bash
# Static lint + validate gate for apps/cla-evidence/infra.
#
# Runs in CI via .github/workflows/infra-validation.yml (or directly by an
# operator before `terraform apply`). Three checks:
#   1. terraform fmt -check     — formatting consistency
#   2. terraform validate       — HCL + provider schema (init -backend=false)
#   3. policy lint              — content invariants the plan promises:
#       - prevent_destroy = true on the bucket
#       - Governance object-lock mode
#       - 3650-day retention
#       - no IP-allowlist on the API tokens

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INFRA_DIR"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

fail=0

echo "→ terraform fmt -check"
if ! terraform fmt -check; then
  red "FAIL: terraform fmt found formatting violations. Run \`terraform fmt\` to fix."
  fail=1
fi

echo "→ terraform validate"
if ! terraform init -backend=false -input=false -no-color >/dev/null; then
  red "FAIL: terraform init failed."
  fail=1
fi
if ! terraform validate -no-color; then
  red "FAIL: terraform validate found schema errors."
  fail=1
fi

echo "→ policy lint"
if ! grep -q 'prevent_destroy *= *true' bucket.tf; then
  red "FAIL: bucket.tf must declare lifecycle { prevent_destroy = true } on the bucket."
  fail=1
fi
if ! grep -q '"Mode":"GOVERNANCE"' object_lock.tf; then
  red "FAIL: object_lock.tf must set Object Lock Mode to GOVERNANCE."
  fail=1
fi
if ! grep -q '"Days":3650' object_lock.tf; then
  red "FAIL: object_lock.tf must set 10-year (3650 day) retention."
  fail=1
fi
if grep -q 'allowed_ips' iam.tf; then
  red "FAIL: iam.tf must NOT use allowed_ips on tokens (plan-review converged: no IP-allowlist)."
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  green "OK: apps/cla-evidence/infra static checks passed."
fi
exit "$fail"
