#!/usr/bin/env bash
# Discoverability probe for the masked-dir pre-create alert (#10455, PR-B).
# Question: if the app cannot pre-create a masked dir (a cross-tenant read channel left unmasked), is there a path
# from that failure to a human without anyone reading a dashboard? Two links, derived from the committed files
# (no credentials, no network, pure grep/awk so it fits Preflight Check 10's 15 s cap with a bare PATH):
#   1. a literal `op: "masked-dir-precreate"` emit in a non-test file under apps/web-platform/server/
#   2. a LIVE (uncommented) sentry_alert rule in apps/web-platform/infra/sentry/*.tf with feature eq agent-sandbox,
#      that op, and an email action.
# The full chain (null first argument, dir_kind set, real-path capture) is pinned by
# test/sentry-masked-dir-precreate-alert-op-contract.test.ts; this script only proves the two artifacts still meet.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OP="masked-dir-precreate"

fail() { echo "MASKED_DIR_ALERT_PATH_FAIL $*"; exit 1; }

emit="$(grep -rlE --include='*.ts' --include='*.tsx' --include='*.mts' \
  --exclude='*.test.*' --exclude='*.spec.*' "op:[[:space:]]*[\"'\`]${OP}[\"'\`]" \
  "$ROOT/apps/web-platform/server" 2>/dev/null | head -1)"
[[ -n "$emit" ]] || fail "no emit site for op ${OP} under apps/web-platform/server/"

tfs=("$ROOT"/apps/web-platform/infra/sentry/*.tf)
[[ -r "${tfs[0]}" ]] || fail "no Terraform files under apps/web-platform/infra/sentry/"

# Strip whole-line # and // comments, then read each sentry_alert block and require the three live attributes.
rule="$(awk '
  /^[[:space:]]*(#|\/\/)/ { next }
  /^resource[[:space:]]+"sentry_alert"/ { n = $3; gsub(/"/, "", n); blk = n; f = 0; o = 0; e = 0; inb = 1 }
  inb && /key[[:space:]]*=[[:space:]]*"feature"[[:space:]]*,[[:space:]]*match[[:space:]]*=[[:space:]]*"eq"[[:space:]]*,[[:space:]]*value[[:space:]]*=[[:space:]]*"agent-sandbox"/ { f = 1 }
  inb && /key[[:space:]]*=[[:space:]]*"op"[[:space:]]*,[[:space:]]*match[[:space:]]*=[[:space:]]*"eq"[[:space:]]*,[[:space:]]*value[[:space:]]*=[[:space:]]*"'"$OP"'"/ { o = 1 }
  inb && /email[[:space:]]*=[[:space:]]*\{[^}]*target_type/ { e = 1 }
  inb && /^\}/ { if (f && o && e) { print blk; exit } inb = 0 }
' "${tfs[@]}")"
[[ -n "$rule" ]] || fail "no live sentry_alert rule with feature=agent-sandbox, op=${OP} and an email action"

echo "emit site: ${emit#"$ROOT"/}"
echo "rule: sentry_alert.${rule}"
echo "MASKED_DIR_ALERT_PATH_OK"
