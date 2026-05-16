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
#
# Optional --live flag adds:
#   4. live Object Lock assertion — calls `aws s3api get-object-lock-configuration`
#      against R2 and verifies Mode=GOVERNANCE, Days=3650. Requires:
#        R2_CLA_EVIDENCE_ADMIN_KEY_ID, R2_CLA_EVIDENCE_ADMIN_SECRET,
#        R2_CLA_EVIDENCE_ENDPOINT, R2_CLA_EVIDENCE_BUCKET.
#      The operator MUST run this after `terraform apply` per the plan's
#      Phase 1 Step 3 (post-apply verification). The bucket-creation path
#      relies on a null_resource provisioner whose failure mode is silent —
#      a bucket can complete create but reach the apply step without Object
#      Lock if the null_resource errored (e.g., wrong credentials). Without
#      Object Lock the WORM guarantee underpinning the legal-evidence claim
#      is void; this check is the load-bearing post-apply gate.

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INFRA_DIR"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

LIVE_MODE=0
for arg in "$@"; do
  case "$arg" in
    --live) LIVE_MODE=1 ;;
    *)      red "unknown arg: $arg"; exit 64 ;;
  esac
done

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
# Bucket-scoping regression guard: tokens MUST scope to `com.cloudflare.edge.r2.bucket.*`
# resource strings, NOT the account-wide `com.cloudflare.api.account.<id>` form.
# Per PR #3201 multi-agent review (architecture-strategist + security-sentinel +
# user-impact-reviewer convergence on token blast radius).
if grep -qE '"com\.cloudflare\.api\.account\.\$\{var\.cf_account_id\}"\s*=' iam.tf; then
  red "FAIL: iam.tf grants account-wide R2 scope; tokens MUST be bucket-scoped via com.cloudflare.edge.r2.bucket.<account>_default_<bucket>."
  fail=1
fi
if ! grep -qE 'com\.cloudflare\.edge\.r2\.bucket\.\$\{var\.cf_account_id\}_default_' iam.tf; then
  red "FAIL: iam.tf must declare at least one bucket-scoped R2 resource string."
  fail=1
fi

if [[ "$LIVE_MODE" -eq 1 ]]; then
  echo "→ live Object Lock assertion (--live)"
  : "${R2_CLA_EVIDENCE_ADMIN_KEY_ID:?missing — required for --live mode}"
  : "${R2_CLA_EVIDENCE_ADMIN_SECRET:?missing — required for --live mode}"
  : "${R2_CLA_EVIDENCE_ENDPOINT:?missing — required for --live mode}"
  bucket="${R2_CLA_EVIDENCE_BUCKET:-soleur-cla-evidence}"
  lock_json=$(AWS_ACCESS_KEY_ID="$R2_CLA_EVIDENCE_ADMIN_KEY_ID" \
    AWS_SECRET_ACCESS_KEY="$R2_CLA_EVIDENCE_ADMIN_SECRET" \
    AWS_REGION=auto \
    aws s3api get-object-lock-configuration \
      --bucket "$bucket" \
      --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" \
      --output json 2>&1) || {
        red "FAIL: get-object-lock-configuration failed — Object Lock is NOT configured on bucket $bucket."
        red "      The WORM guarantee is void. Investigate the null_resource.cla_evidence_object_lock state."
        red "      Output: $lock_json"
        fail=1
        lock_json=""
      }
  if [[ -n "$lock_json" ]]; then
    mode=$(printf '%s' "$lock_json" | jq -r '.ObjectLockConfiguration.Rule.DefaultRetention.Mode // "<missing>"')
    days=$(printf '%s' "$lock_json" | jq -r '.ObjectLockConfiguration.Rule.DefaultRetention.Days // "<missing>"')
    if [[ "$mode" != "GOVERNANCE" ]]; then
      red "FAIL: Object Lock Mode=$mode, expected GOVERNANCE."
      fail=1
    fi
    if [[ "$days" != "3650" ]]; then
      red "FAIL: Object Lock Days=$days, expected 3650 (10 years)."
      fail=1
    fi
    if [[ "$fail" -eq 0 ]]; then
      green "OK: live Object Lock = Mode=$mode, Days=$days."
    fi
  fi
fi

if [[ "$fail" -eq 0 ]]; then
  if [[ "$LIVE_MODE" -eq 1 ]]; then
    green "OK: apps/cla-evidence/infra static + live checks passed."
  else
    green "OK: apps/cla-evidence/infra static checks passed."
  fi
fi
exit "$fail"
