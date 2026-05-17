#!/usr/bin/env bash
# gdpr-override.sh — GDPR Art. 17 admin-override driver for cla-evidence R2 Lock Rules.
#
# Companion to bootstrap.sh (which mints the bucket + Lock Rules). When a
# verified Art. 17 erasure request lands AND the CLO confirms the Art. 17(3)(e)
# carveout does not apply, an operator runs this script to:
#   1. verify a 1-hour CF admin token (Account → R2 Edit + User → API Tokens Edit)
#   2. GET the current Lock Rule list and snapshot it
#   3. PUT a temporarily-modified rule list (per --shape=) that unblocks DELETE
#   4. DELETE the offending object via the S3-compat HMAC creds in Doppler prd_cla
#      (NEVER the bearer admin token — see Sharp Edges in the plan)
#   5. PUT-restore the byte-equal snapshot
#   6. verify via main.test.sh --live --strict-rule-count
#   7. write a tombstone (schema_version: "1.0") via the same HMAC creds
#   8. self-revoke the admin token via the CF API
#
# Tested via apps/cla-evidence/scripts/gdpr-override.test.sh (dry-run, all
# network IO stubbed via PATH-shadowed curl/aws/doppler).
#
# Runbook: knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md §7

# Suppress xtrace immediately — protects secrets if invoked with `bash -x`
# (see TS-OVERRIDE.j). Redirect silences the `set +x` echo itself.
{ set +x; } 2>/dev/null

set -euo pipefail

# ── Color + log helpers ──────────────────────────────────────────────────────
GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; NC='\033[0m'
red()    { printf '%b%s%b\n' "$RED"    "$*" "$NC" >&2; }
green()  { printf '%b%s%b\n' "$GREEN"  "$*" "$NC"; }
yellow() { printf '%b%s%b\n' "$YELLOW" "$*" "$NC"; }
step()   { printf '\n→ %s\n' "$*"; }

usage_err() { red "::error::usage: $*"; exit 64; }

# ── Help ─────────────────────────────────────────────────────────────────────
show_help() {
  cat <<'EOF'
gdpr-override.sh — GDPR Art. 17 admin-override driver (R2 Lock Rules).

USAGE
  doppler run -p soleur -c prd_cla -- \
    bash apps/cla-evidence/scripts/gdpr-override.sh [OPTIONS]

OPTIONS
  --shape=enabled-false        Flip rule.enabled false → DELETE → true (DEFAULT)
  --shape=age-1s               Lower maxAgeSeconds to 1 during DELETE
  --shape=narrow-prefix        Add a narrow-prefix override rule (REQUIRES ack)
  --I-have-verified-precedence Required ack for --shape=narrow-prefix
                               (operator must dry-run against a synthetic
                               bucket first; CF multi-rule precedence is
                               documented as "longest matching prefix wins"
                               but not yet verified on this codebase)
  --dry-run                    Plan only; no network IO (currently informational)
  --help, -h                   Show this help and exit 0

REQUIRED ENV
  CF_ADMIN_TOKEN              1-hour CF admin token (R2 Edit + API Tokens Edit)
  CF_ACCOUNT_ID               Cloudflare account ID
  R2_CLA_EVIDENCE_BUCKET      Target bucket (e.g. soleur-cla-evidence)
  R2_CLA_EVIDENCE_ENDPOINT    R2 S3-compat endpoint URL
  TARGET_KEY                  Object key to erase (e.g. signatures/<sha>.json)
  GDPR_REQUEST_REF            DPA/incident reference (e.g. DSAR-2026-001)
  PRIOR_SHA                   64-char lowercase hex SHA-256 of the deleted object
  OVERRIDE_REASON             Human rationale (>=10 chars)
  ADMIN_ACTOR                 Operator identity (e.g. ops@example.com)

EXIT CODES
  0   success
  1   pre-PUT abort (token verify or GET failed); self-revoke ran
  2   DELETE failed; best-effort restore + self-revoke ran; no tombstone
  3   PUT-restore FAILED after successful DELETE; CRITICAL;
      no self-revoke; no tombstone — bucket WORM may be void
  64  usage / config error
EOF
}

# ── Arg parsing ──────────────────────────────────────────────────────────────
SHAPE="enabled-false"
DRY_RUN=0
ACK_NARROW=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)           show_help; exit 0 ;;
    --dry-run)           DRY_RUN=1; shift ;;
    --shape=enabled-false|--shape=age-1s|--shape=narrow-prefix)
                         SHAPE="${1#--shape=}"; shift ;;
    --shape=*)           usage_err "unknown shape: ${1#--shape=}" ;;
    --I-have-verified-precedence)
                         ACK_NARROW=1; shift ;;
    *)                   usage_err "unknown arg: $1" ;;
  esac
done

if [[ "$SHAPE" == "narrow-prefix" ]] && [[ "$ACK_NARROW" != "1" ]]; then
  usage_err "--shape=narrow-prefix requires --I-have-verified-precedence (operator must dry-run against a synthetic bucket first; see runbook §7.3)"
fi

# ── Env validation ───────────────────────────────────────────────────────────
required_envs=(
  CF_ADMIN_TOKEN CF_ACCOUNT_ID
  R2_CLA_EVIDENCE_BUCKET R2_CLA_EVIDENCE_ENDPOINT
  TARGET_KEY GDPR_REQUEST_REF PRIOR_SHA
  OVERRIDE_REASON ADMIN_ACTOR
)
missing=()
for v in "${required_envs[@]}"; do
  [[ -z "${!v:-}" ]] && missing+=("$v")
done
[[ ${#missing[@]} -gt 0 ]] && usage_err "missing required env: ${missing[*]}"

# PRIOR_SHA must be 64-char lowercase hex (third-consumer schema invariant —
# inspect-evidence.sh exits 3 on malformed values).
if ! [[ "$PRIOR_SHA" =~ ^[0-9a-f]{64}$ ]]; then
  usage_err "PRIOR_SHA must be 64-char lowercase hex (got ${#PRIOR_SHA} chars)"
fi

# ── Dep check ────────────────────────────────────────────────────────────────
for bin in jq curl aws doppler; do
  command -v "$bin" >/dev/null || usage_err "missing $bin on PATH"
done

# ── Workspace + URLs ─────────────────────────────────────────────────────────
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CF_API="https://api.cloudflare.com/client/v4"
LOCK_URL="$CF_API/accounts/$CF_ACCOUNT_ID/r2/buckets/$R2_CLA_EVIDENCE_BUCKET/lock"
# Allow tests to substitute a stub main.test.sh; default resolves alongside infra/.
MAIN_TEST_SH="${GDPR_OVERRIDE_MAIN_TEST_SH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../infra" && pwd)/main.test.sh}"

if [[ "$DRY_RUN" == "1" ]]; then
  green "[dry-run] would: verify CF admin token; GET lock rules; PUT shape=$SHAPE; DELETE $TARGET_KEY via prd_cla HMAC; PUT-restore; verify; tombstone tombstones/$PRIOR_SHA.json; self-revoke admin token."
  exit 0
fi

# Cleanup safety net state (load-bearing per plan §Sharp Edges).
MUTATED=0
RESTORED=0
CF_ADMIN_TOKEN_ID=""

# ── Cleanup safety net ──────────────────────────────────────────────────────
# Pattern mirrors sentinel-pr.sh:167-192. Fires on ERR/INT/TERM between
# PUT-modify (MUTATED=1) and PUT-restore-success (RESTORED=1). Best-effort
# restores from snapshot; does NOT self-revoke (operator needs token to
# investigate). Explicit error paths below set their own exit codes; this
# trap is the safety net for unexpected mid-flow failures (network blip,
# Ctrl-C).
# shellcheck disable=SC2317  # invoked via trap; shellcheck cannot see the indirect call.
_cleanup_partial_override() {
  local rc=$?
  trap - ERR INT TERM
  if [[ "$MUTATED" == "1" ]] && [[ "$RESTORED" != "1" ]] && [[ -s "$WORK/snapshot.json" ]]; then
    red "::error::CRITICAL: lock-rule mutation in flight at interrupt; attempting best-effort restore"
    if curl --max-time 30 -fsS -X PUT \
        -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        --data-binary "@$WORK/snapshot.json" \
        "$LOCK_URL" >/dev/null 2>&1; then
      red "::error::best-effort restore SUCCEEDED — verify with main.test.sh --live"
    else
      red "::error::CRITICAL: best-effort restore FAILED — manual restore required immediately"
    fi
  fi
  exit "$rc"
}

_self_revoke() {
  if [[ -z "$CF_ADMIN_TOKEN_ID" ]]; then
    yellow "  WARN: no admin-token id captured; revoke manually in CF dashboard."
    return 0
  fi
  if curl --max-time 30 -fsS -X DELETE \
      -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
      "$CF_API/user/tokens/$CF_ADMIN_TOKEN_ID" >/dev/null 2>&1; then
    green "  admin token self-revoked"
  else
    yellow "  WARN: self-revoke failed; revoke $CF_ADMIN_TOKEN_ID manually in CF dashboard."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — verify CF admin token
# ─────────────────────────────────────────────────────────────────────────────
step "[1/8] verify CF admin token"
if ! verify=$(curl --max-time 30 -fsS \
    -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
    "$CF_API/user/tokens/verify" 2>/dev/null); then
  red "::error::admin token verify failed; rotate and retry"
  exit 1
fi
status=$(printf '%s' "$verify" | jq -r '.result.status // "unknown"')
if [[ "$status" != "active" ]]; then
  red "::error::admin token status=$status (expected active)"
  exit 1
fi
CF_ADMIN_TOKEN_ID=$(printf '%s' "$verify" | jq -r '.result.id // ""')
if [[ -z "$CF_ADMIN_TOKEN_ID" ]]; then
  red "::error::could not capture admin token id (needed for self-revoke)"
  exit 1
fi
green "  token verified (id captured for self-revoke)"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — GET current lock rules + snapshot canonical state
# ─────────────────────────────────────────────────────────────────────────────
step "[2/8] GET lock rules + snapshot"
get_resp="$WORK/lock-get.json"
if ! curl --max-time 30 -fsS \
    -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
    -o "$get_resp" \
    "$LOCK_URL" 2>/dev/null; then
  red "::error::GET $LOCK_URL failed (HTTP error)"
  _self_revoke
  exit 1
fi
success=$(jq -r '.success // false' "$get_resp")
if [[ "$success" != "true" ]]; then
  err=$(jq -r '.errors // [] | map("\(.code // "?"): \(.message // "?")") | join("; ")' "$get_resp")
  red "::error::GET lock rules returned success:false ($err)"
  _self_revoke
  exit 1
fi
rule_count=$(jq -r '.result.rules | length' "$get_resp")
max_age=$(jq -r '[.result.rules[]? | select(.condition.type == "Age") | .condition.maxAgeSeconds] | max // 0' "$get_resp")
if ! [[ "$rule_count" =~ ^[0-9]+$ ]] || [[ "$rule_count" -lt 1 ]]; then
  red "::error::GET response: rule_count=$rule_count (expected >=1)"
  _self_revoke
  exit 1
fi
if ! [[ "$max_age" =~ ^[0-9]+$ ]] || [[ "$max_age" -lt 315360000 ]]; then
  red "::error::GET response: maxAgeSeconds=$max_age (expected >=315360000)"
  _self_revoke
  exit 1
fi
# Byte-equal restore body: wrap rules array in {rules:...} per CF contract.
jq -c '{rules: .result.rules}' "$get_resp" > "$WORK/snapshot.json"
green "  snapshot saved: rule_count=$rule_count maxAgeSeconds(max)=$max_age"

# ─────────────────────────────────────────────────────────────────────────────
# Build modified body per --shape=
# ─────────────────────────────────────────────────────────────────────────────
modified="$WORK/lock-put-modified.json"
case "$SHAPE" in
  enabled-false)
    jq -c '{rules: (.result.rules | map(.enabled = false))}' "$get_resp" > "$modified"
    ;;
  age-1s)
    jq -c '{rules: (.result.rules | map(if .condition.type == "Age" then .condition.maxAgeSeconds = 1 else . end))}' "$get_resp" > "$modified"
    ;;
  narrow-prefix)
    jq -c --arg key "$TARGET_KEY" '{rules: (.result.rules + [{id:"gdpr-override-narrow", enabled:true, prefix:$key, condition:{type:"Age", maxAgeSeconds:1}}])}' "$get_resp" > "$modified"
    ;;
esac

# Install ERR/INT/TERM safety net BEFORE PUT-modify (load-bearing per plan
# §Sharp Edges / tasks.md §2.4). Explicit error paths below clear this and
# set their own exit codes; the trap catches mid-flow interrupts only.
trap '_cleanup_partial_override' ERR INT TERM

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — PUT modified lock rules
# ─────────────────────────────────────────────────────────────────────────────
step "[3/8] PUT modified lock rules (shape=$SHAPE)"
if ! curl --max-time 30 -fsS -X PUT \
    -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "@$modified" \
    "$LOCK_URL" >/dev/null 2>&1; then
  red "::error::PUT modified rules failed; lock state unchanged"
  trap - ERR INT TERM
  _self_revoke
  exit 1
fi
MUTATED=1
green "  lock rules temporarily modified"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — DELETE offending object via S3-compat HMAC (Doppler prd_cla env)
#
# Bearer-vs-HMAC separation: this step MUST run via `doppler run -p soleur -c
# prd_cla -- aws ...` so the HMAC pair from Doppler is the credential, NOT
# the bearer admin token. Passing the 53-char bearer to aws would reproduce
# the "Credential access key has length 53, should be 32" failure that bit
# PR #3919's first cron run. See plan §Sharp Edges (bearer-vs-HMAC trap).
# ─────────────────────────────────────────────────────────────────────────────
step "[4/8] DELETE object via S3-compat HMAC (prd_cla env)"
delete_rc=0
doppler run -p soleur -c prd_cla -- \
  aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" \
      s3api delete-object \
      --bucket "$R2_CLA_EVIDENCE_BUCKET" \
      --key "$TARGET_KEY" >/dev/null 2>&1 \
  || delete_rc=$?

if [[ "$delete_rc" -ne 0 ]]; then
  red "::error::DELETE object failed (rc=$delete_rc); attempting best-effort restore (no tombstone)"
  if curl --max-time 30 -fsS -X PUT \
      -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary "@$WORK/snapshot.json" \
      "$LOCK_URL" >/dev/null 2>&1; then
    RESTORED=1
    green "  best-effort restore succeeded"
  else
    red "::error::CRITICAL: best-effort restore ALSO failed; manual restore required"
  fi
  trap - ERR INT TERM
  _self_revoke
  exit 2
fi
green "  object deleted from R2"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — PUT-restore canonical rules (byte-equal snapshot)
# ─────────────────────────────────────────────────────────────────────────────
step "[5/8] PUT-restore canonical lock rules"
if ! curl --max-time 30 -fsS -X PUT \
    -H "Authorization: Bearer $CF_ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary "@$WORK/snapshot.json" \
    "$LOCK_URL" >/dev/null 2>&1; then
  red "::error::CRITICAL: PUT-restore FAILED after successful DELETE; bucket WORM may be void; manual restore required immediately"
  # Per plan §Sharp Edges: do NOT self-revoke (operator needs token).
  # Do NOT write tombstone (bucket state degraded).
  trap - ERR INT TERM
  exit 3
fi
RESTORED=1
trap - ERR INT TERM
green "  lock rules restored to canonical state"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6 — verify via main.test.sh --live --strict-rule-count
# ─────────────────────────────────────────────────────────────────────────────
step "[6/8] verify restored state (main.test.sh --live --strict-rule-count)"
if [[ -x "$MAIN_TEST_SH" ]]; then
  if ! CF_ADMIN_TOKEN_BOOTSTRAP="$CF_ADMIN_TOKEN" \
       CF_ACCOUNT_ID="$CF_ACCOUNT_ID" \
       R2_CLA_EVIDENCE_BUCKET="$R2_CLA_EVIDENCE_BUCKET" \
       bash "$MAIN_TEST_SH" --live --strict-rule-count; then
    yellow "  WARN: verify reported issues; review canonical state before next override"
  fi
else
  yellow "  WARN: main.test.sh not executable at $MAIN_TEST_SH; skipping verify"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 7 — write tombstone (HMAC env via doppler run)
#
# Schema is the §7.4 runbook contract (schema_version: "1.0"); changing it
# breaks the third consumer-boundary at inspect-evidence.sh (exit 3). See
# learning 2026-05-04-cla-evidence-sidecar-pattern.md §3.
# ─────────────────────────────────────────────────────────────────────────────
step "[7/8] write tombstone via S3-compat HMAC (prd_cla env)"
tomb_key="tombstones/${PRIOR_SHA}.json"
deleted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tomb_body="$WORK/tombstone.json"
jq -n \
  --arg sv "1.0" \
  --arg dt "$deleted_at" \
  --arg actor "$ADMIN_ACTOR" \
  --arg ref "$GDPR_REQUEST_REF" \
  --arg sha "$PRIOR_SHA" \
  --arg reason "$OVERRIDE_REASON" \
  '{schema_version:$sv, deleted_at:$dt, admin_actor:$actor, gdpr_request_ref:$ref, prior_object_sha:$sha, override_reason:$reason}' \
  > "$tomb_body"

if ! doppler run -p soleur -c prd_cla -- \
    aws --endpoint-url "$R2_CLA_EVIDENCE_ENDPOINT" \
        s3api put-object \
        --bucket "$R2_CLA_EVIDENCE_BUCKET" \
        --key "$tomb_key" \
        --body "$tomb_body" \
        --content-type "application/json" >/dev/null 2>&1; then
  red "::error::tombstone PUT failed; chain coherence at risk — write tombstone manually"
fi
green "  tombstone written: $tomb_key"

# ─────────────────────────────────────────────────────────────────────────────
# Step 8 — self-revoke admin token
# ─────────────────────────────────────────────────────────────────────────────
step "[8/8] self-revoke admin token"
_self_revoke

green ""
green "GDPR override complete (key=$TARGET_KEY, request=$GDPR_REQUEST_REF)."
exit 0
