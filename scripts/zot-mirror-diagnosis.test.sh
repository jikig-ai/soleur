#!/usr/bin/env bash
# Unit tests for scripts/zot-mirror-diagnosis.sh (#7242 / ADR-166).
#
# WHAT THESE PIN. The zot-mirror failure path had a message that named a cause the job
# had already DISPROVED six minutes earlier in the same run: it told the operator to
# rotate REGISTRY_PUSH_ACCESS_TOKEN_* while the in-job preflight had printed "verified
# live". Two prior iterations (2026-07-15, 2026-07-29) were each "fixed" by rewriting
# the sentence, and each re-drifted. So the assertions below are not about wording —
# they pin the two properties that make re-drift detectable:
#
#   1. the VERDICT is derived from the detector's measured JSON counts, never from its
#      exit code alone (rc=1 means "dead OR unverifiable", and unverifiable is
#      *unmeasured*, not *bad* — collapsing them is the whole defect class); and
#   2. each arm carries a distinguishing literal, so deleting it reddens this suite
#      (cq-assert-anchor-not-bare-token — an assertion count proves the assertions RAN,
#      not that they BITE).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/zot-mirror-diagnosis.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

# Substring assertions grep a FILE, never a pipe: under `set -o pipefail` a
# `printf … | grep -q` whose match lands early takes SIGPIPE on the producer and the
# pipeline exits 141 EVEN THOUGH grep matched, so the negative form fails open.
_TXT="$(mktemp -t zot-diag-assert.XXXXXXXX)"
trap 'rm -f "$_TXT"' EXIT

assert_contains() {
  local desc="$1" needle="$2" hay="$3"
  printf '%s' "$hay" > "$_TXT"
  if grep -qF -- "$needle" "$_TXT"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    missing literal: $needle"; FAIL=$((FAIL + 1)); fi
}

assert_not_contains() {
  local desc="$1" needle="$2" hay="$3"
  printf '%s' "$hay" > "$_TXT"
  if grep -qF -- "$needle" "$_TXT"; then echo "  FAIL: $desc"; echo "    forbidden literal present: $needle"; FAIL=$((FAIL + 1));
  else echo "  PASS: $desc"; PASS=$((PASS + 1)); fi
}

# A verdict fixture is a real file on disk, because "the verdict file is absent or
# unreadable" is one of the states under test and cannot be expressed as a string.
FIXDIR="$(mktemp -d -t zot-diag-fix.XXXXXXXX)"
trap 'rm -rf "$FIXDIR"; rm -f "$_TXT"' EXIT

mkjson() { # $1 = name, $2 = dead, $3 = unverifiable, [$4 = cause]
  local cause="${4:-}" keys="[]"
  [[ -n "$cause" ]] && keys="[{\"key\":\"REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET\",\"cause\":\"${cause}\",\"reason\":\"synthesized fixture\"}]"
  cat > "$FIXDIR/$1" <<EOF
{ "live": 1, "dead": $2, "unverifiable": $3, "probes": 2, "configs": 1,
  "stale": [], "unverifiable_keys": $keys }
EOF
  printf '%s' "$FIXDIR/$1"
}

echo "=== zot-mirror-diagnosis.sh — verdict derivation ==="

# Scenario 1. The clean path. This is the state TODAY'S incident was in, and the one the
# old message contradicted.
assert_eq "rc=0, dead=0, unver=0 → live" "live" \
  "$(zot_mirror_verdict 0 "$(mkjson clean.json 0 0)")"

# Scenario 2. A MEASURED dead count. Rotation genuinely is the remedy here — and only here.
assert_eq "rc=1, dead>0 → stale" "stale" \
  "$(zot_mirror_verdict 1 "$(mkjson dead.json 2 0)")"

# Scenario 3. THE THESIS ASSERTION. The detector exits 1 for `dead>0 OR unverifiable>0`
# (check-cloudflare-token-drift.sh, final `[[ "$DEAD_N" -gt 0 || "$UNVERIFIABLE_N" -gt 0 ]]`),
# so deriving the verdict from rc alone prints "the token is STALE, rotate it" about a
# token NOTHING measured. Without this case the fix reproduces the defect it exists to drain.
assert_eq "rc=1, dead=0, unver>0 → unverifiable (NOT stale)" "unverifiable" \
  "$(zot_mirror_verdict 1 "$(mkjson unver.json 0 1 gate-indeterminate)")"

# A measured dead count outranks an unverifiable one: the accusation is backed by evidence.
assert_eq "rc=1, dead>0 AND unver>0 → stale (measured dominates)" "stale" \
  "$(zot_mirror_verdict 1 "$(mkjson both.json 1 1 unexpected-status)")"

# Scenario 4. Exit 2 is the detector's "nothing was checked at all" — a precondition was
# missing, or it probed zero configs. Not a claim about any credential.
assert_eq "rc=2 → unmeasured" "unmeasured" \
  "$(zot_mirror_verdict 2 "$(mkjson clean2.json 0 0)")"

# Scenario 5. The verdict file never landed (an unwritable --json-file path is itself an
# exit-2 condition, but the file can also be absent for reasons the rc does not carry).
assert_eq "absent verdict file → unmeasured" "unmeasured" \
  "$(zot_mirror_verdict 0 "$FIXDIR/does-not-exist.json")"

printf 'not json at all\n' > "$FIXDIR/garbage.json"
assert_eq "unparseable verdict file → unmeasured" "unmeasured" \
  "$(zot_mirror_verdict 0 "$FIXDIR/garbage.json")"

# An empty file parses as neither — same fail-toward-no-claim direction.
: > "$FIXDIR/empty.json"
assert_eq "empty verdict file → unmeasured" "unmeasured" \
  "$(zot_mirror_verdict 1 "$FIXDIR/empty.json")"

# JSON present but missing the keys the verdict is derived from. Reading a missing key as
# 0 would manufacture `live` out of a file that measured nothing.
printf '{"live":1,"probes":2}\n' > "$FIXDIR/nokeys.json"
assert_eq "verdict file missing dead/unverifiable keys → unmeasured" "unmeasured" \
  "$(zot_mirror_verdict 0 "$FIXDIR/nokeys.json")"

# Inconsistency guard. rc=1 asserts "something was dead or ungradeable", so rc=1 with both
# counts at zero means the exit code and the counts disagree. Resolving that to `live`
# would be the worst direction available: certifying a credential the detector refused to
# certify. Fail toward no claim.
assert_eq "rc=1 but dead=0 and unver=0 (inconsistent) → unmeasured, never live" "unmeasured" \
  "$(zot_mirror_verdict 1 "$(mkjson inconsistent.json 0 0)")"

echo "=== unverifiable cause extraction ==="

# The detector emits a CLOSED cause vocabulary per row precisely so a consumer does not
# have to pattern-match English prose. Each cause carries a different remedy, and all four
# carry "Do NOT rotate".
assert_eq "cause read from unverifiable_keys[0]" "gate-indeterminate" \
  "$(zot_mirror_unverifiable_cause "$(mkjson c1.json 0 1 gate-indeterminate)")"
assert_eq "cause read from unverifiable_keys[0] (stamped-non-refusal)" "stamped-non-refusal" \
  "$(zot_mirror_unverifiable_cause "$(mkjson c2.json 0 1 stamped-non-refusal)")"
assert_eq "no unverifiable rows → unknown (never empty, never invented)" "unknown" \
  "$(zot_mirror_unverifiable_cause "$(mkjson c3.json 0 0)")"
assert_eq "absent file → unknown" "unknown" \
  "$(zot_mirror_unverifiable_cause "$FIXDIR/does-not-exist.json")"

echo "=== arm text — Scenario 7: live ==="

LIVE_TXT="$(zot_mirror_diagnosis live "20:23:05Z" "zot_restarts 0 -> 950 over 4h (+~20 per 5-min sample, oom_kills=0)")"

# The claim's whole basis is that the preflight probed THIS hostname. If a future edit
# drops that mapping the claim silently hollows out, so the message names the function.
assert_contains "live cites the preflight timestamp" "20:23:05Z" "$LIVE_TXT"
assert_contains "live cites access_hostname_for() as the basis of the claim" "access_hostname_for()" "$LIVE_TXT"
assert_contains "live states rotation will not help" "Rotating the token will not help" "$LIVE_TXT"
assert_contains "live carries the measured restart series" "zot_restarts 0 -> 950" "$LIVE_TXT"
# Scope: the preflight settles the CF Access credential. ZOT_PUSH_USER/_TOKEN is a
# distinct docker-login failure mode and must not be absorbed into "origin-side".
assert_contains "live scopes its claim to the Access credential only" "ZOT_PUSH_USER/ZOT_PUSH_TOKEN" "$LIVE_TXT"
assert_contains "live gates the re-run on a plateau, not on the clock" "plateau" "$LIVE_TXT"

# "No rotation headline" is a claim about the FIRST line specifically — the body legitimately
# says "Rotating the token will not help", so a whole-text grep would be the wrong anchor.
LIVE_HEAD="$(printf '%s' "$LIVE_TXT" | head -1)"
assert_not_contains "live HEADLINE does not lead with token rotation" "check-cloudflare-token-drift.sh" "$LIVE_HEAD"
assert_contains "live headline names the measured verdict" "MEASURED LIVE" "$LIVE_HEAD"

echo "=== arm text — Scenario 8: stale ==="

STALE_TXT="$(zot_mirror_diagnosis stale "20:23:05Z" "" "")"
# Assert the PRESENCE of the corrected remedy, not the absence of the falsified clause:
# an absence-grep false-fails on any file that documents its own prohibition.
assert_contains "stale states the CORRECTED remedy (every config, no inheritance)" \
  "Doppler branch configs do NOT inherit" "$STALE_TXT"
assert_contains "stale names the detector as the way to list the affected configs" \
  "check-cloudflare-token-drift.sh" "$STALE_TXT"
assert_contains "stale warns terraform apply cannot propagate a rotation" "No changes" "$STALE_TXT"
assert_contains "stale headline names the measured verdict" "MEASURED DEAD" "$STALE_TXT"
# The falsified clause must not come back on the arm that a real rotation lands on.
assert_not_contains "stale does not repeat the falsified root-config-inherits clause" \
  "branch configs inherit" "$STALE_TXT"

echo "=== arm text — Scenario 9: unverifiable ==="

UNVER_TXT="$(zot_mirror_diagnosis unverifiable "20:23:05Z" "" "gate-indeterminate")"
assert_contains "unverifiable surfaces the detector's own cause token" "gate-indeterminate" "$UNVER_TXT"
assert_contains "unverifiable repeats the detector's Do NOT rotate instruction" "Do NOT rotate" "$UNVER_TXT"
assert_contains "unverifiable headline says the credential was NOT GRADED" "NOT GRADED" "$UNVER_TXT"
# The distinction this arm exists for: ungraded is not dead.
assert_not_contains "unverifiable does not assert the token is dead" "MEASURED DEAD" "$UNVER_TXT"

echo "=== arm text — Scenario 10: unmeasured ==="

UNMEAS_TXT="$(zot_mirror_diagnosis unmeasured "" "" "")"
assert_contains "unmeasured says plainly that nothing was measured" "NOTHING WAS MEASURED" "$UNMEAS_TXT"
assert_contains "unmeasured lists candidates as unranked" "in no particular order" "$UNMEAS_TXT"
# The base case is what stops the operator looping on a probe that just failed.
assert_contains "unmeasured has a base case when the settling probe is itself unavailable" \
  "escalate" "$UNMEAS_TXT"
# This arm's entire contract is that it ranks nothing.
assert_not_contains "unmeasured never names a most-likely cause" "most likely" "$UNMEAS_TXT"
assert_not_contains "unmeasured does not assert the token is dead" "MEASURED DEAD" "$UNMEAS_TXT"

echo "=== cross-arm: no arm may name an unmeasured cause ==="

# The ADR-166 invariant, asserted mechanically across every arm rather than left to review.
for v in live stale unverifiable unmeasured; do
  t="$(zot_mirror_diagnosis "$v" "20:23:05Z" "series" "gate-indeterminate")"
  assert_not_contains "$v arm does not use the falsified edge-vs-origin heuristic" \
    "the EDGE rejected you" "$t"
  # Every arm must carry the recovery instruction, because a blocked release is a draft.
  assert_contains "$v arm is non-empty" "zot" "$t"
done

# An unknown verdict must not silently render as one of the four. Fail loud instead —
# a message that renders empty is indistinguishable from a step that never ran.
UNKNOWN_TXT="$(zot_mirror_diagnosis banana "" "" "" 2>&1 || true)"
assert_contains "an unrecognised verdict is reported, not silently rendered" "unrecognised verdict" "$UNKNOWN_TXT"

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
