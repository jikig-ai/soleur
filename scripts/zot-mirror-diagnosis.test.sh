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

# $5/$6 default to a HEALTHY measured run so existing cases read unchanged, but they are
# parameters because holding them constant is exactly what hid the absence-of-bad-news
# defect: every fixture said `live:1, probes:2`, so the axis "did the detector actually
# probe this credential?" was never sampled and `probes:0` silently graded `live`.
mkjson() { # $1 = name, $2 = dead, $3 = unverifiable, [$4 = cause] [$5 = live] [$6 = probes]
  local cause="${4:-}" alive="${5:-1}" probes="${6:-2}" keys="[]"
  [[ -n "$cause" ]] && keys="[{\"key\":\"REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET\",\"cause\":\"${cause}\",\"reason\":\"synthesized fixture\"}]"
  cat > "$FIXDIR/$1" <<EOF
{ "live": $alive, "dead": $2, "unverifiable": $3, "probes": $probes, "configs": 1,
  "stale": [], "unverifiable_keys": $keys }
EOF
  printf '%s' "$FIXDIR/$1"
}

# A multi-row unverifiable_keys fixture. `mkjson` can only build 0 or 1 rows, so the
# "which row does the cause come from?" axis was unsampled and `rows[0]` -> `rows[-1]`
# survived every mutation.
mkjson_multi() { # $1 = name, $2... = cause tokens
  local name="$1"; shift
  local rows="" c
  for c in "$@"; do
    [[ -n "$rows" ]] && rows="${rows},"
    rows="${rows}{\"key\":\"KEY_${c}\",\"cause\":\"${c}\",\"reason\":\"synthesized fixture\"}"
  done
  cat > "$FIXDIR/$name" <<EOF
{ "live": 0, "dead": 0, "unverifiable": $#, "probes": 2, "configs": 1,
  "stale": [], "unverifiable_keys": [${rows}] }
EOF
  printf '%s' "$FIXDIR/$name"
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

echo "=== positive evidence, and the cells no fixture sampled ==="

# THE ABSENCE-OF-BAD-NEWS CELL. Every arm above this tests for the absence of a negative,
# and a detector run that probed NOTHING produces exactly that. Without this case,
# {"live":0,"dead":0,"unverifiable":0,"probes":0} at rc=0 graded `live` and rendered
# "Cloudflare Access ADMITTED them" about a measurement that never happened — this
# library's own thesis violated in its primary function.
assert_eq "rc=0 but live=0 and probes=0 → unmeasured, NEVER live" "unmeasured" \
  "$(zot_mirror_verdict 0 "$(mkjson zeroprobe.json 0 0 "" 0 0)")"

# The mirror image of the rc=1/counts-disagree case. A MEASURED dead count is an accusation
# backed by evidence whatever the exit code says; pinning it stops a future edit from
# quietly conditioning `stale` on rc and flipping the direction.
assert_eq "rc=0 but dead>0 → stale (a measured count outranks the exit code)" "stale" \
  "$(zot_mirror_verdict 0 "$(mkjson rc0dead.json 3 0)")"

# Cardinality. mkjson can only build 0 or 1 rows, so "which row does the cause come from?"
# was unsampled and rows[0] -> rows[-1] survived every mutation.
assert_eq "multi-row unverifiable_keys reads the FIRST row" "gate-absent" \
  "$(zot_mirror_unverifiable_cause "$(mkjson_multi multi.json gate-absent refused-unstamped detector-env)")"

# unverifiable>0 with an EMPTY keys array: the count says several keys were ungradeable and
# the rows say nothing. Report unknown rather than inventing one.
printf '{"live":0,"dead":0,"unverifiable":3,"probes":2,"unverifiable_keys":[]}\n' > "$FIXDIR/unver-nokeys.json"
assert_eq "unverifiable>0 with empty keys → unknown" "unknown" \
  "$(zot_mirror_unverifiable_cause "$FIXDIR/unver-nokeys.json")"

echo "=== cause vocabulary: SET-EQUALITY against the detector, not a spot-check ==="

# A per-member spot-check ("does it grep <member>?") cannot detect a MISSING member, which
# is how a four-row table shipped under a claim that it was exhaustive while the detector
# emits TEN. This derives the producer's set from its source and asserts the consumer
# renders a specific remedy for every one — so adding a cause to the detector reddens here.
DETECTOR="$SCRIPT_DIR/check-cloudflare-token-drift.sh"
# `edge-error-<NNNN>` is a FAMILY the detector builds from the measured code
# (`|edge-error-${_edge_code}|`), so no literal member exists to grep. Its presence is
# detected from that row template and sampled as 1000 (the zone-move code) and 1016 (a
# non-1000 member, so a remedy keyed on 1000 alone cannot satisfy the family). The
# `UNVERIFIABLE:[a-z-]+` grep would otherwise extract the bare prefix `edge-error-`.
# The row literals are read with the same regex token-drift-workflow-causes.test.sh uses, so a
# new `|<cause>|` row reds here without anyone editing a list in this file.
mapfile -t DETECTOR_CAUSES < <(
  { grep -oE 'UNVERIFIABLE:[a-z-]+' "$DETECTOR" | sed 's/UNVERIFIABLE://' | grep -vxF 'edge-error-'
    grep -oE 'UNVERIFIABLE_ROWS\+=\("\$\{base\}_ID/_SECRET\|[a-z0-9-]+\|' "$DETECTOR" | grep -oE '\|[a-z0-9-]+\|$' | tr -d '|'
    if grep -qF '|edge-error-${_edge_code}|' "$DETECTOR"; then printf '%s\n' edge-error-1000 edge-error-1016; fi
  } | sort -u
)
assert_eq "the detector's cause vocabulary was extracted (non-vacuity control)" "true" \
  "$([[ "${#DETECTOR_CAUSES[@]}" -ge 14 ]] && echo true || echo "false (${#DETECTOR_CAUSES[@]} found)")"
# The three #12937 edge causes are IN the extracted set — pinned by name, so a regression
# that drops one from the detector reds here rather than shrinking the set silently.
for _c in host-nxdomain tunnel-down edge-error-1000; do
  assert_eq "the detector emits the edge cause ${_c}" "yes" \
    "$(_hit=no; for _d in "${DETECTOR_CAUSES[@]}"; do [[ "$_d" == "$_c" ]] && _hit=yes; done; echo "$_hit")"
done

_unmapped=""
for c in "${DETECTOR_CAUSES[@]}"; do
  h="$(zot_mirror_cause_help "$c")"
  # The `*)` fallback names the token and says "does not recognise" — so a member that fell
  # through is detectable, which is the whole point of routing through a keyed helper.
  case "$h" in *"does not recognise"*) _unmapped="${_unmapped} ${c}" ;; esac
done
assert_eq "every cause the detector can emit has its own remedy" "" "$_unmapped"

# ...and the fallback itself must still work, or the check above would be unfalsifiable.
assert_contains "an unrecognised cause is reported, not silently blank" \
  "does not recognise" "$(zot_mirror_cause_help "not-a-real-cause")"

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
LIVE_HEAD="${LIVE_TXT%%$'\n'*}"
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
assert_contains "stale names the Terraform rotation for the registry pair" "client_secret_version" "$STALE_TXT"
# Terraform writes this pair (no ignore_changes), so the old "Terraform will NOT fix this" is false.
assert_not_contains "stale does not claim Terraform cannot fix the registry pair" "ignore_changes = [value]" "$STALE_TXT"
assert_contains "stale warns that a hand-set prd value is reverted" "next apply writes the state's value back" "$STALE_TXT"
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

# ACTIONABLE STANDALONE — this is a contract, not a nicety, and it is what makes the
# cross-consumer answer defensible. cf-tunnel-registry-bridge has THREE callers and only
# reusable-release.yml runs a token preflight; build-inngest-config-bundle.yml and
# build-inngest-bootstrap-image.yml therefore sit on `unmeasured` PERMANENTLY. If this arm
# were merely a degraded placeholder, those two workflows would have been handed a worse
# message than they had before. So it must carry a runnable command of its own.
assert_contains "unmeasured is actionable standalone: it names the detector command" \
  "check-cloudflare-token-drift.sh" "$UNMEAS_TXT"
assert_contains "unmeasured points at the origin telemetry by marker name" \
  "SOLEUR_ZOT_DISK" "$UNMEAS_TXT"

echo "=== cross-arm: no arm may name an unmeasured cause ==="

# The ADR-166 invariant, asserted mechanically across every arm rather than left to review.
for v in live stale unverifiable unmeasured; do
  t="$(zot_mirror_diagnosis "$v" "20:23:05Z" "series" "gate-indeterminate")"
  # The needle is the literal that ACTUALLY shipped on this code path and caused the
  # incident (action.yml on main: "which is the stale-service-token shape"). The previous
  # needle was "the EDGE rejected you", which has only ever existed in a RUNBOOK and in this
  # test file — it cannot regress into the library, so all four assertions were vacuous.
  assert_not_contains "$v arm does not revive the falsified stale-service-token inference" \
    "stale-service-token" "$t"
  # Every arm must carry the recovery instruction, because a blocked release is a draft.
  assert_contains "$v arm is non-empty" "zot" "$t"
done

# An unknown verdict must not silently render as one of the four. Fail loud instead —
# a message that renders empty is indistinguishable from a step that never ran.
UNKNOWN_TXT="$(zot_mirror_diagnosis banana "" "" "" 2>&1 || true)"
assert_contains "an unrecognised verdict is reported, not silently rendered" "unrecognised verdict" "$UNKNOWN_TXT"

echo "=== SOLEUR_ZOT_BRIDGE marker (#12937) ==="

RUNBOOK_SUFFIX="runbook=knowledge-base/engineering/operations/runbooks/zot-registry-revert.md#grep-for-the-bridge-markers-first"

# The acceptance line, byte for byte: field ORDER is part of the grammar (a log grep and the
# release workflow's re-validation both anchor on it).
assert_eq "the marker prints the exact acceptance line" \
  "SOLEUR_ZOT_BRIDGE stage=push verdict=live cause=edge-error-1000 host=registry.soleur.ai rc=1 ${RUNBOOK_SUFFIX}" \
  "$(zot_bridge_marker push live edge-error-1000 registry.soleur.ai 1)"
assert_eq "field order is stage verdict cause host rc runbook" \
  "stage= verdict= cause= host= rc= runbook=" \
  "$(zot_bridge_marker login unverifiable host-nxdomain registry.soleur.ai 6 | grep -oE '[a-z]+=' | tr '\n' ' ' | sed 's/ $//')"
assert_eq "exactly one line is printed" "1" \
  "$(zot_bridge_marker listener unmeasured unknown registry.soleur.ai 1 | wc -l | tr -d ' ')"

# Every member of each closed set passes through unchanged.
for _s in setup listener login push; do
  assert_contains "stage ${_s} is printed as itself" "stage=${_s} " "$(zot_bridge_marker "$_s" live unknown h.example 1)"
done
for _v in live stale unverifiable unmeasured; do
  assert_contains "verdict ${_v} is printed as itself" "verdict=${_v} " "$(zot_bridge_marker push "$_v" unknown h.example 1)"
done
for _c in "${DETECTOR_CAUSES[@]}" unknown; do
  assert_contains "detector cause ${_c} is printed as itself" "cause=${_c} " "$(zot_bridge_marker push unverifiable "$_c" h.example 1)"
done

# An UNKNOWN but well-formed cause is `unknown`, never echoed (a cause the detector cannot
# emit has no remedy and must not look like one).
assert_contains "a well-formed cause outside the vocabulary prints cause=unknown" \
  "cause=unknown " "$(zot_bridge_marker push unverifiable made-up-cause h.example 1)"
assert_contains "edge-error outside 1000-1999 is not in the family" \
  "cause=unknown " "$(zot_bridge_marker push unverifiable edge-error-2000 h.example 1)"

# Forgery rows (Guard 1). Each hostile value must collapse to `invalid` AND leave the output
# as one line containing no workflow-command prefix.
_ls=$' '
for _bad in $'edge-error-1000\n::error::forged' $'x\r::warning::y' "::add-mask::z" "a${_ls}b" "has space" ""; do
  _m="$(zot_bridge_marker push unverifiable "$_bad" registry.soleur.ai 1)"
  assert_contains "hostile cause collapses to invalid" "cause=invalid " "$_m"
  assert_not_contains "hostile cause cannot inject a workflow command" "::" "$_m"
  assert_eq "hostile cause still yields one line" "1" "$(printf '%s\n' "$_m" | wc -l | tr -d ' ')"
  assert_contains "hostile stage collapses to invalid" "stage=invalid " "$(zot_bridge_marker "$_bad" live unknown h.example 1)"
  assert_contains "hostile verdict collapses to invalid" "verdict=invalid " "$(zot_bridge_marker push "$_bad" unknown h.example 1)"
  assert_contains "hostile host collapses to invalid" "host=invalid " "$(zot_bridge_marker push live unknown "$_bad" 1)"
  assert_contains "hostile rc collapses to invalid" "rc=invalid " "$(zot_bridge_marker push live unknown h.example "$_bad")"
done
assert_contains "an upper-case host is not in ^[a-z0-9.-]+$" "host=invalid " "$(zot_bridge_marker push live unknown Registry.soleur.ai 1)"
assert_contains "a non-numeric rc is invalid" "rc=invalid " "$(zot_bridge_marker push live unknown h.example n/a)"
assert_contains "Stage names outside the set (preflight) are invalid" "stage=invalid " "$(zot_bridge_marker preflight live unknown h.example 1)"

# The validator accepts exactly what the helper prints, and nothing it would not.
_good="$(zot_bridge_marker login unverifiable edge-error-1000 registry.soleur.ai 1)"
assert_eq "validator accepts the helper's own line" "ok" "$(zot_bridge_marker_valid "$_good" && echo ok || echo rejected)"
assert_eq "validator accepts an all-invalid line from the helper" "ok" \
  "$(zot_bridge_marker_valid "$(zot_bridge_marker '' '' $'\n' '' '')" && echo ok || echo rejected)"
assert_eq "validator rejects a trailing injected line" "rejected" \
  "$(zot_bridge_marker_valid "${_good}"$'\n::error::x' && echo ok || echo rejected)"
assert_eq "validator rejects a cause outside the vocabulary" "rejected" \
  "$(zot_bridge_marker_valid "${_good/edge-error-1000/made-up}" && echo ok || echo rejected)"
assert_eq "validator rejects a different runbook" "rejected" \
  "$(zot_bridge_marker_valid "${_good/zot-registry-revert/other}" && echo ok || echo rejected)"
assert_eq "validator rejects the runbook without its section anchor" "rejected" \
  "$(zot_bridge_marker_valid "${_good%#*}" && echo ok || echo rejected)"
assert_eq "validator accepts the setup stage" "ok" \
  "$(zot_bridge_marker_valid "$(zot_bridge_marker setup unmeasured unknown invalid '')" && echo ok || echo rejected)"
assert_eq "validator rejects an empty value" "rejected" \
  "$(zot_bridge_marker_valid "" && echo ok || echo rejected)"

# Discoverability probe from the plan's Observability block: the marker's single emitter is
# in this library.
assert_eq "discoverability: the marker name is in the library" "SOLEUR_ZOT_BRIDGE" \
  "$(grep -o -m1 -e SOLEUR_ZOT_BRIDGE "$SCRIPT_DIR/zot-mirror-diagnosis.sh")"

echo "=== remedies for the #12937 edge causes ==="
assert_contains "edge-error-1000 names the authoritative-zone remedy" \
  "DNS record is wrong or missing in the zone that is authoritative for" "$(zot_mirror_cause_help edge-error-1000)"
# curl exit 6 is also a runner resolver failure, so host-nxdomain must not assert the zone is wrong.
assert_contains "host-nxdomain admits the runner's resolver as a cause" \
  "NXDOMAIN, or the runner's resolver failed" "$(zot_mirror_cause_help host-nxdomain)"
assert_not_contains "host-nxdomain does not assert the zone record is wrong" \
  "DNS record is wrong" "$(zot_mirror_cause_help host-nxdomain)"
for _c in host-nxdomain edge-error-1000; do
  assert_contains "${_c} points at #12931" "#12931" "$(zot_mirror_cause_help "$_c")"
done
assert_contains "tunnel-down names the connector" "connector" "$(zot_mirror_cause_help tunnel-down)"
# Each edge cause names one command an agent can run.
assert_contains "host-nxdomain names a runnable command" "gh issue list --label ci/tunnel-zone-authority" "$(zot_mirror_cause_help host-nxdomain)"
assert_contains "edge-error-1000 names a runnable command" "gh issue list --label ci/tunnel-zone-authority" "$(zot_mirror_cause_help edge-error-1000)"
assert_contains "other edge codes name a runnable command" "gh workflow run scheduled-terraform-drift.yml" "$(zot_mirror_cause_help edge-error-1016)"
assert_contains "tunnel-down names a runnable command" "gh issue list --label ci/tunnel-connector-drift" "$(zot_mirror_cause_help tunnel-down)"
assert_contains "a non-1000 edge code renders its own code" "(1016)" "$(zot_mirror_cause_help edge-error-1016)"
assert_contains "the unverifiable arm surfaces an edge cause verbatim" "edge-error-1000" \
  "$(zot_mirror_diagnosis unverifiable "20:23:05Z" "" "edge-error-1000")"

echo "=== Results: $PASS passed, $FAIL failed ==="

# ANTI-VACUITY DISPATCH FLOOR. Every assertion above is reached through assert_eq /
# assert_contains / assert_not_contains, so commenting out the CALLS — an edit that reads
# like ordinary cleanup — yields "0 passed, 0 failed" and exit 0, and scripts/test-all.sh
# reads only the exit code. A floor (never equality: equality makes every new assertion a
# spurious failure) is the only thing that notices.
MIN_ASSERTIONS=153  # the REALIZED count on a green run
if [[ $((PASS + FAIL)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $((PASS + FAIL)) assertions ran, expected >= ${MIN_ASSERTIONS}." >&2
  echo "      The suite did not execute what it claims to. Fix the dispatch, do not lower the floor." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
