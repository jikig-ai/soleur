#!/usr/bin/env bash
# Discoverability probe for the masked-dir pre-create alert (#10455, PR-B).
# Question: if the app cannot pre-create a masked dir (a cross-tenant read channel left unmasked), is there a path
# from that failure to a human without anyone reading a dashboard? Two links, derived from the committed files
# (no credentials, no network, pure grep/awk so it fits Preflight Check 10's 15 s cap with a bare PATH):
#   1. a LIVE (uncommented) literal `op: "masked-dir-precreate"` emit in a non-test file under apps/web-platform/server/
#   2. a LIVE (uncommented) sentry_alert rule in apps/web-platform/infra/sentry/*.tf, in ONE resource block: enabled = true,
#      feature eq agent-sandbox AND that op, logic_type "all", and an email action whose fallthrough is not NoOne.
# Comments (whole-line, trailing, and block) are removed before any match, so a commented-out emit or rule cannot satisfy it.
# The full chain (null first argument, dir_kind set, real-path capture) is pinned by
# test/sentry-masked-dir-precreate-alert-op-contract.test.ts; this script only proves the two artifacts still meet.
# Test seam: MASKED_DIR_ALERT_SERVER_DIR / MASKED_DIR_ALERT_SENTRY_DIR replace the two input roots, so the negative controls in
# test/masked-dir-alert-discoverability.test.ts run this same script over mutated temp copies.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OP="masked-dir-precreate"
SERVER_DIR="${MASKED_DIR_ALERT_SERVER_DIR:-$ROOT/apps/web-platform/server}"
SENTRY_DIR="${MASKED_DIR_ALERT_SENTRY_DIR:-$ROOT/apps/web-platform/infra/sentry}"

fail() { echo "MASKED_DIR_ALERT_PATH_FAIL $*"; exit 1; }

# awk prelude: strip(line) removes block comments (state carried across lines) and a trailing `//` or `#` comment that starts at a
# line start or after whitespace (so `http://x` survives). Whole-line comments come out as an empty string.
STRIP='
function strip(line,   out, i) {
  out = ""
  while (length(line) > 0) {
    if (inblk) {
      i = index(line, "*/")
      if (!i) { line = ""; break }
      line = substr(line, i + 2); inblk = 0
    } else {
      i = index(line, "/*")
      if (!i) { out = out line; line = ""; break }
      out = out substr(line, 1, i - 1); line = substr(line, i + 2); inblk = 1
    }
  }
  sub(/(^|[ \t])(\/\/|#).*$/, "", out)
  return out
}
'

emit=""
re="op:[[:space:]]*[\"'\`]${OP}[\"'\`]"
while IFS= read -r f; do
  if awk -v re="$re" "$STRIP"'
    { out = strip($0); if (out ~ re) found = 1 }
    END { exit found ? 0 : 1 }
  ' "$f"; then emit="$f"; break; fi
done < <(find "$SERVER_DIR" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.mts' \) \
  ! -name '*.test.*' ! -name '*.spec.*' ! -path '*/__tests__/*' 2>/dev/null | sort)
[[ -n "$emit" ]] || fail "no live emit site for op ${OP} under ${SERVER_DIR#"$ROOT"/}"

tfs=("$SENTRY_DIR"/*.tf)
[[ -r "${tfs[0]}" ]] || fail "no Terraform files under ${SENTRY_DIR#"$ROOT"/}"

# Read each sentry_alert block (comments stripped) and require every live attribute in the SAME block.
rule="$(awk -v op="$OP" "$STRIP"'
  { out = strip($0) }
  out ~ /^resource[ \t]+"sentry_alert"/ { n = out; sub(/^resource[ \t]+"sentry_alert"[ \t]+"/, "", n); sub(/".*$/, "", n); blk = n; inb = 1; f = o = e = en = la = bad = 0; next }
  !inb { next }
  out ~ /key[ \t]*=[ \t]*"feature"[ \t]*,[ \t]*match[ \t]*=[ \t]*"eq"[ \t]*,[ \t]*value[ \t]*=[ \t]*"agent-sandbox"/ { f = 1 }
  index(out, "value = \"" op "\"") && out ~ /key[ \t]*=[ \t]*"op"[ \t]*,[ \t]*match[ \t]*=[ \t]*"eq"/ { o = 1 }
  out ~ /email[ \t]*=[ \t]*\{[^}]*target_type/ { e = 1 }
  out ~ /fallthrough_type[ \t]*=[ \t]*"NoOne"/ { bad = 1 }
  out ~ /^[ \t]*enabled[ \t]*=[ \t]*true([ \t]|$)/ { en = 1 }
  out ~ /^[ \t]*enabled[ \t]*=/ && out !~ /^[ \t]*enabled[ \t]*=[ \t]*true([ \t]|$)/ { bad = 1 }
  out ~ /logic_type[ \t]*=[ \t]*"all"/ { la = 1 }
  out ~ /logic_type[ \t]*=/ && out !~ /logic_type[ \t]*=[ \t]*"all"/ { bad = 1 }
  out ~ /^\}/ { if (f && o && e && en && la && !bad) { print blk; exit } inb = 0 }
' "${tfs[@]}")"
[[ -n "$rule" ]] || fail "no live sentry_alert rule with enabled=true, feature=agent-sandbox, op=${OP}, logic_type all and an email action that reaches someone"

echo "emit site: ${emit#"$ROOT"/}"
echo "rule: sentry_alert.${rule}"
echo "MASKED_DIR_ALERT_PATH_OK"
