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
# test/masked-dir-alert-discoverability.test.ts run this same script over mutated temp copies. A run with either set prints a
# MASKED_DIR_ALERT_OVERRIDE line and ends with MASKED_DIR_ALERT_SEAM_PASS, never MASKED_DIR_ALERT_PATH_OK (the token Preflight matches
# by substring), so a stray export in a shell or CI step cannot turn a substituted input into a green answer about the repository.
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

# Read each sentry_alert block (comments stripped) and require every live attribute in the SAME block, and the filter attributes in the SAME
# `action_filters` ENTRY (one `{ ... }` of the list, found by brace depth; braces inside strings are ignored):
#   resource: an `enabled = true` line (a false, or a missing one, fails), a non-empty monitor_ids, and event_frequency_count trigger entries
#     that ALL have value = 0 (page on every event; a higher threshold would swallow a single failure) with at least one present
#   entry:    logic_type "all", feature eq agent-sandbox, op eq masked-dir-precreate, and an email action on ONE line whose target_type is
#     "issue_owners" (the only value this file uses) and whose fallthrough_type is not NoOne
# An email in a different entry, or in an entry conditioned on another feature, cannot satisfy the op entry. Multi-line `email = {` actions
# and `event_frequency_count = {` entries fail closed (they do not match), as do two filter entries written on one line (their lines merge).
rule="$(awk -v op="$OP" "$STRIP"'
  function blank(t) { gsub(/"[^"]*"/, "", t); return t }
  function reset_entry() { ef = eo = ee = el = ebad = 0 }
  { out = strip($0) }
  out ~ /^resource[ \t]+"sentry_alert"/ {
    n = out; sub(/^resource[ \t]+"sentry_alert"[ \t]+"/, "", n); sub(/".*$/, "", n); blk = n
    inb = 1; d = 0; inaf = 0; inentry = 0; okentry = 0; mpend = 0
    en = mon = tc = tbad = 0; reset_entry()
  }
  !inb { next }
  {
    pre_in = inentry; pre_af = inaf; started = 0; closing = 0
    if (d == 1 && out ~ /^[ \t]*action_filters[ \t]*=[ \t]*\[/) inaf = 1
    t = blank(out)
    for (i = 1; i <= length(t); i++) {
      c = substr(t, i, 1)
      if (c == "{") { d++; if (inaf && d == 2 && !inentry) { inentry = 1; started = 1; reset_entry() } }
      else if (c == "}") { if (inentry && d == 2) closing = 1; d-- }
    }
    if (pre_in || started) {
      if (out ~ /key[ \t]*=[ \t]*"feature"[ \t]*,[ \t]*match[ \t]*=[ \t]*"eq"[ \t]*,[ \t]*value[ \t]*=[ \t]*"agent-sandbox"/) ef = 1
      if (index(out, "value = \"" op "\"") && out ~ /key[ \t]*=[ \t]*"op"[ \t]*,[ \t]*match[ \t]*=[ \t]*"eq"/) eo = 1
      if (out ~ /email[ \t]*=[ \t]*\{[^}]*target_type[ \t]*=[ \t]*"issue_owners"/) ee = 1
      if (out ~ /fallthrough_type[ \t]*=[ \t]*"NoOne"/) ebad = 1
      if (out ~ /logic_type[ \t]*=[ \t]*"all"/) el = 1
    } else if (!pre_af) {
      if (out ~ /^[ \t]*enabled[ \t]*=[ \t]*true([ \t]|$)/) en = 1
      if (mpend && out !~ /^[ \t]*$/) { if (out !~ /^[ \t]*\]/) mon = 1; mpend = 0 }
      else if (out ~ /^[ \t]*monitor_ids[ \t]*=[ \t]*\[[ \t]*[^ \t\]]/) mon = 1
      else if (out ~ /^[ \t]*monitor_ids[ \t]*=[ \t]*\[[ \t]*$/) mpend = 1
      if (out ~ /event_frequency_count/) {
        if (out ~ /event_frequency_count[ \t]*=[ \t]*\{[^}]*value[ \t]*=[ \t]*0[ \t]*[,}]/) tc = 1
        else tbad = 1
      }
    }
    if (closing) { if (ef && eo && ee && el && !ebad) okentry = 1; inentry = 0 }
    if (inaf && !inentry && d == 1 && out ~ /^[ \t]*\][ \t]*,?[ \t]*$/) inaf = 0
    if (out ~ /^\}/ && d == 0) {
      if (en && mon && tc && !tbad && okentry) { print blk; exit }
      inb = 0
    }
  }
' "${tfs[@]}")"
[[ -n "$rule" ]] || fail "no live sentry_alert rule with enabled=true, a monitor, an event_frequency_count 0 trigger, and ONE action filter with logic_type all, feature=agent-sandbox, op=${OP} and an issue_owners email that reaches someone"

echo "emit site: ${emit#"$ROOT"/}"
echo "rule: sentry_alert.${rule}"
# A run over substituted inputs is a test of this script, not proof about the repository: it must never print the token Preflight matches.
if [[ -n "${MASKED_DIR_ALERT_SERVER_DIR+x}" || -n "${MASKED_DIR_ALERT_SENTRY_DIR+x}" ]]; then
  echo "MASKED_DIR_ALERT_OVERRIDE server=${SERVER_DIR} sentry=${SENTRY_DIR} (inputs overridden by the environment: this is NOT proof about the repository)"
  echo "MASKED_DIR_ALERT_SEAM_PASS"
  exit 0
fi
echo "MASKED_DIR_ALERT_PATH_OK"
