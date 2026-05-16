#!/usr/bin/env bash
# Static lint + validate gate for apps/cla-evidence/infra.
#
# Runs in CI via .github/workflows/infra-validation.yml (or directly by an
# operator before `terraform apply`). Three checks:
#   1. terraform fmt -check     — formatting consistency
#   2. terraform validate       — HCL + provider schema (init -backend=false)
#   3. policy lint              — content invariants the plan promises:
#       - prevent_destroy = true on the bucket
#       - CF native Lock Rules age-based retention (maxAgeSeconds=315360000)
#       - Lock Rules PUT URL substring (r2/buckets/.../lock)
#       - no IP-allowlist on the API tokens
#
# Optional --live flag adds:
#   4. live CF Lock Rules assertion — GETs the bucket lock-rule config from
#      the CF native REST API and verifies at least one Age rule with
#      maxAgeSeconds >= 315360000 exists. Requires:
#        CF_ADMIN_TOKEN_BOOTSTRAP, CF_ACCOUNT_ID, R2_CLA_EVIDENCE_BUCKET.
#      The operator MUST run this after `terraform apply` per the plan's
#      Phase 1 Step 3 (post-apply verification). The bucket-creation path
#      relies on a null_resource provisioner whose failure mode is silent —
#      a bucket can complete create but reach the apply step without the
#      Lock Rule applied if the null_resource errored (e.g., wrong
#      credentials). Without the Lock Rule the WORM guarantee underpinning
#      the legal-evidence claim is void; this check is the load-bearing
#      post-apply gate.

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$INFRA_DIR"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

# Single source for the 10-year retention floor; mirrored in object_lock.tf
# via local.lock_rule.rules[0].condition.maxAgeSeconds.
readonly MIN_LOCK_SECONDS=315360000

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
# Anchor on the canonical HCL source (single source of truth in
# local.lock_rule). Format-tolerant: survives heredoc reformats /
# `jq -n` builder migrations as long as the load-bearing values
# remain in the HCL.
if ! grep -qE 'type[[:space:]]*=[[:space:]]*"Age"' object_lock.tf; then
  red "FAIL: object_lock.tf must declare a CF Lock Rule with condition.type = \"Age\"."
  fail=1
fi
if ! grep -qE 'maxAgeSeconds[[:space:]]*=[[:space:]]*315360000' object_lock.tf; then
  red "FAIL: object_lock.tf must declare maxAgeSeconds = 315360000 (10-year retention floor)."
  fail=1
fi
if ! grep -qE 'r2/buckets/.*/lock' object_lock.tf; then
  red "FAIL: object_lock.tf must call the CF native Lock Rules PUT endpoint (.../r2/buckets/<name>/lock)."
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
  echo "→ live CF Lock Rules assertion (--live)"
  : "${CF_ADMIN_TOKEN_BOOTSTRAP:?missing — required for --live mode}"
  : "${CF_ACCOUNT_ID:?missing — required for --live mode}"
  : "${R2_CLA_EVIDENCE_BUCKET:?missing — required for --live mode (e.g. soleur-cla-evidence)}"
  bucket="$R2_CLA_EVIDENCE_BUCKET"
  # Capture stderr separately so curl warnings (TLS, retry) do not corrupt
  # the JSON body fed to jq.
  curl_err=$(mktemp)
  trap 'rm -f "$curl_err"' EXIT
  if ! lock_json=$(curl --max-time 30 -fsS \
        -H "Authorization: Bearer $CF_ADMIN_TOKEN_BOOTSTRAP" \
        "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/r2/buckets/$bucket/lock" 2>"$curl_err"); then
    red "FAIL: GET /r2/buckets/$bucket/lock failed — the CF Lock Rules config is NOT readable."
    red "      The WORM guarantee may be void. Investigate the null_resource.cla_evidence_object_lock state."
    # Emit only the curl stderr — never echo body bytes that could contain
    # an Authorization header reflection or other sensitive material.
    red "      curl stderr: $(cat "$curl_err")"
    fail=1
    lock_json=""
  fi
  if [[ -n "$lock_json" ]]; then
    success=$(printf '%s' "$lock_json" | jq -r '.success // false')
    if [[ "$success" != "true" ]]; then
      # Project only .errors[] (not the full body) so the failure log
      # cannot accidentally include a reflected Authorization header.
      err_msg=$(printf '%s' "$lock_json" | jq -r '.errors // [] | map("\(.code // "?"): \(.message // "?")") | join("; ")')
      red "FAIL: CF API returned success=false. Errors: $err_msg"
      fail=1
    else
      rule_count=$(printf '%s' "$lock_json" | jq -r '.result.rules | length')
      max_age=$(printf '%s' "$lock_json" | jq -r '[.result.rules[]? | select(.condition.type == "Age") | .condition.maxAgeSeconds] | max // 0')
      # Defensive numeric coercion guards — jq can emit "null" if the
      # response shape is unexpected; without these, [[ -lt ]] would
      # silently coerce to 0 and pass the floor check.
      if ! [[ "$rule_count" =~ ^[0-9]+$ ]]; then
        red "FAIL: rule_count is not numeric (got: $rule_count). Response shape unexpected."
        fail=1
      elif [[ "$rule_count" -lt 1 ]]; then
        red "FAIL: bucket $bucket has zero Lock Rules; expected at least one Age rule."
        fail=1
      fi
      if ! [[ "$max_age" =~ ^[0-9]+$ ]]; then
        red "FAIL: max_age is not numeric (got: $max_age). Response shape unexpected."
        fail=1
      elif [[ "$max_age" -lt "$MIN_LOCK_SECONDS" ]]; then
        red "FAIL: bucket $bucket maxAgeSeconds=$max_age, expected >= $MIN_LOCK_SECONDS (10 years)."
        fail=1
      fi
      if [[ "$fail" -eq 0 ]]; then
        green "OK: live CF Lock Rules — rule_count=$rule_count, maxAgeSeconds(max)=$max_age."
      fi
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
