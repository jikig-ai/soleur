#!/usr/bin/env bash
# Guard 1 (#7555) — a copy-stage failure is diagnosed from UPLOAD evidence, not host health.
#
# Background. `degraded()` in .github/workflows/reusable-release.yml appended ONE unconditional
# line to every stage's failure output:
#
#   Registry-host health (disk AND zot_restarts/exit_code, which is what an origin flap shows
#   up in): see SOLEUR_ZOT_DISK / Better Stack registry_disk_prd.
#
# For a `copy_*` failure that line is the entire mechanism by which the reader was sent at
# registry-host telemetry. On 2026-08-13 it sent one at a restart loop that was not occurring
# (`zot_restarts=0`, uptime monotonic, none in 48 h) while the real cause was zot's 60 s
# ReadTimeout/WriteTimeout cutting a large-layer PATCH. That is an ADR-166 violation: a CI
# message may only name a cause the job measured.
#
# THE PROPERTY. Every reason the `for TAG_SPEC` loop generates, plus `verify`, emits the
# upload-ceiling pointer and NOT the host-health pointer; `bridge` emits the host-health pointer
# and NOT the upload-ceiling pointer; `crane_install` emits NEITHER (it fails on the runner, so
# both registry channels would name an unmeasured cause); any reason in no family emits BOTH, so
# an unclassified stage can never silently inherit a cause nobody measured.
#
# WHY THE REASON SET IS DERIVED, NOT LISTED. A hand-written list of three copy reasons cannot
# see a fourth tag added to the loop. This suite parses the `for TAG_SPEC in ...` line and
# quantifies over what it actually generates, so adding `"stable:mirror_stable"` without
# extending the branching drives this RED (Guard 1 mutation row 2) — the reason falls to the
# unclassified arm, emits both pointers, and the copy-family assertion sees the host pointer.
#
# The block under test is EXTRACTED VERBATIM from the workflow (no copy-paste of the logic), so
# this exercises the shell that actually ships. Run via:
#   bash plugins/soleur/test/reusable-release-degraded-pointer.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"
STEP_NAME="Mirror image GHCR→zot (crane) + cosign-sign the zot digest"

# A sandbox-relocated copy of this suite would silently measure nothing; fail loud instead.
if [[ ! -f "$WF" ]]; then
  echo "  FAIL: workflow not found at $WF (relocated harness?)"
  echo "=== Results: 0/1 passed, 1 failed ==="
  exit 1
fi

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}

TMP=$(mktemp -d) || { echo "  FAIL: mktemp"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Extract the step's `run:` block verbatim. Dedent by the MINIMUM leading
# whitespace across non-blank lines (not the first line's), so a reordering edit
# cannot over-dedent and corrupt the shell. index() rather than a dynamic regex:
# the step name contains `(crane)`, which a `$0 ~` match would read as a group.
# ---------------------------------------------------------------------------
extract_run_block() {
  awk -v target="$STEP_NAME" '
    index($0, "- name: " target) && /^[[:space:]]*- name: / { instep=1; next }
    instep && /^[[:space:]]*- name: / { exit }
    instep && /^[[:space:]]*run: \|/ { inrun=1; next }
    inrun {
      lines[n++] = $0
      if ($0 !~ /^[[:space:]]*$/) {
        match($0, /^[[:space:]]*/)
        if (base == 0 || RLENGTH < base) base = RLENGTH
      }
    }
    END { for (i = 0; i < n; i++) print substr(lines[i], base + 1) }
  ' "$WF"
}

BLOCK="$TMP/block.sh"
extract_run_block > "$BLOCK"
if [[ ! -s "$BLOCK" ]]; then
  fail "could not extract the mirror step's run block from $WF"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# Carve `SAFE_TO_RERUN=` and the whole `degraded() { ... }` body out of the block.
# The rest of the block performs the real mirror and must NOT run. The closer is
# matched on a `}` at the SAME indent as the opener, so a nested brace inside the
# body cannot terminate the carve early.
# ---------------------------------------------------------------------------
FN="$TMP/degraded.sh"
awk '
  /^SAFE_TO_RERUN=/ { print; next }
  /^emit_stage_pointer\(\) \{/ { infn=1; print; next }
  /^degraded\(\) \{/ { infn=1; print; next }
  infn { print; if ($0 == "}") infn=0 }
' "$BLOCK" > "$FN"

if ! grep -q '^degraded() {' "$FN" || ! grep -q '^emit_stage_pointer() {' "$FN" || ! grep -q '^}' "$FN"; then
  fail "could not carve degraded() out of the extracted block"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi
if ! grep -q '^SAFE_TO_RERUN=' "$FN"; then
  fail "SAFE_TO_RERUN not carved — degraded() would run unbound under set -u"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# Derive the copy-reason set from the loop that GENERATES it. `${TAG_SPEC##*:}`
# is the reason, so take the text after the last colon of each quoted spec.
# ---------------------------------------------------------------------------
# ANCHORED ON THE STATEMENT, NOT THE TOKEN, AND REQUIRED UNIQUE (#7555 review). A bare
# `grep -m1 'for TAG_SPEC in '` takes the first match ANYWHERE in the file, so one documentation
# comment quoting the old loop above the live one silently redirects this derivation at the decoy
# — measured: a fourth non-copy_* tag then shipped with this suite 21/21 green. This repo's house
# style is a long comment directly above the code it describes, so the decoy is the convention,
# not an attack. `^[[:space:]]*for` cannot match a `#`-led line.
TAG_SPEC_SITES=$(grep -cE '^[[:space:]]*for TAG_SPEC in ' "$WF")
if [[ "$TAG_SPEC_SITES" -ne 1 ]]; then
  fail "expected exactly ONE 'for TAG_SPEC in' statement in $WF, found $TAG_SPEC_SITES — the derivation below would silently pick one of them"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi
mapfile -t COPY_REASONS < <(
  grep -m1 -E '^[[:space:]]*for TAG_SPEC in ' "$WF" \
    | grep -oE '"[^"]+"' \
    | tr -d '"' \
    | sed 's/.*://'
)

if [[ "${#COPY_REASONS[@]}" -lt 3 ]]; then
  fail "derived only ${#COPY_REASONS[@]} copy reasons from the TAG_SPEC loop — expected >= 3"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi
echo "  (derived copy reasons: ${COPY_REASONS[*]})"

# `verify` is not loop-generated but belongs to the same family: it fails on what the upload
# left behind. `sign` is deliberately in NEITHER family — the copy already succeeded, so
# neither pointer is a measured cause for it.
UPLOAD_FAMILY=("${COPY_REASONS[@]}")
# `verify` is its OWN family (#7555 review). It does NOT push — it reads back what the copy left
# in zot, and `verify mismatch` means zot holds DIFFERENT bits, which is a writer question, not a
# transport one. Telling that reader about an upload deadline names a cause the job did not
# measure — the ADR-166 defect this branching exists to remove, re-committed inside its own fix.
VERIFY_FAMILY=(verify)
HOST_FAMILY=(bridge)
# `crane_install` is NOT host family, though it shares bridge's position before any copy. It is a
# curl from github.com plus a sha256sum ON THE RUNNER, and its own degraded() detail says
# "nothing is wrong with zot or the image". Pointing it at registry-host telemetry named a cause
# the job did not measure — this guard's whole subject — and contradicted the detail printed
# beside it. Its family asserts the ABSENCE of both registry channels, which is the only honest
# pointer for a stage where nothing ever reached zot.
RUNNER_FAMILY=(crane_install)
UNCLASSIFIED=(sign)

# ---------------------------------------------------------------------------
# Run degraded() for one reason and echo everything it printed.
#
# THE DETAIL IS SINGLE-LINE ON PURPOSE (#7555 review). It used to force a two-line detail so the
# ::group:: arm would render — which made this suite structurally unable to see that the pointer
# was nested inside that arm while 8 of the 9 live call sites pass a SINGLE-line detail. Measured:
# under the production shape the pointer emitted ZERO times and this suite was still green. Keep
# this fixture on the shape production actually produces.
# ---------------------------------------------------------------------------
run_degraded() {
  local reason="$1"
  (
    export GITHUB_OUTPUT="$TMP/out.$$" GITHUB_STEP_SUMMARY="$TMP/sum.$$" ZOT="example/img:v1"
    : > "$GITHUB_OUTPUT"; : > "$GITHUB_STEP_SUMMARY"
    # shellcheck disable=SC1090
    source "$FN"
    degraded "$reason" "1" "zot did not receive the tag of this image, so the host has nothing to pull."
  ) 2>&1
}

# Content anchors, per AC1. Asserted as the CONTENT the operator must be pointed at, not as a
# whole-sentence literal, so rewording the prose does not falsely red this guard.
UPLOAD_ANCHORS=(PatchBlobUpload latency Content-Length)
HOST_ANCHOR='SOLEUR_ZOT_DISK'

assert_upload_family() {
  local reason="$1" out
  out="$(run_degraded "$reason")"
  local a missing=""
  for a in "${UPLOAD_ANCHORS[@]}"; do
    grep -qF -- "$a" <<<"$out" || missing="$missing $a"
  done
  if [[ -n "$missing" ]]; then
    fail "reason '$reason' (upload family): pointer missing anchor(s):$missing"
  else
    pass "reason '$reason' emits the upload-ceiling pointer (all 3 anchors)"
  fi
  # The inverse half. Without this, mutation row 1 (host pointer unconditional again) passes.
  if grep -qF -- "$HOST_ANCHOR" <<<"$out"; then
    fail "reason '$reason' (upload family): still emits the host-health pointer ($HOST_ANCHOR)"
  else
    pass "reason '$reason' does NOT emit the host-health pointer"
  fi
}

assert_host_family() {
  local reason="$1" out
  out="$(run_degraded "$reason")"
  if grep -qF -- "$HOST_ANCHOR" <<<"$out"; then
    pass "reason '$reason' emits the host-health pointer"
  else
    fail "reason '$reason' (host family): host-health pointer absent"
  fi
  # Mutation row 4 — the inverse error a copy-only assertion cannot see.
  if grep -qF -- "PatchBlobUpload" <<<"$out"; then
    fail "reason '$reason' (host family): wrongly emits the upload-ceiling pointer"
  else
    pass "reason '$reason' does NOT emit the upload-ceiling pointer"
  fi
}

assert_runner_family() {
  local reason="$1" out
  out="$(run_degraded "$reason")"
  # Both directions, because this family is defined by what it must NOT say. An assertion that
  # only checked for the word "runner" would pass a pointer that ALSO named a registry channel,
  # which is the defect being fixed.
  if grep -qF -- "$HOST_ANCHOR" <<<"$out"; then
    fail "reason '$reason' (runner family): emits the host-health pointer for a failure on the RUNNER"
  else
    pass "reason '$reason' does NOT emit the host-health pointer"
  fi
  if grep -qF -- "PatchBlobUpload" <<<"$out"; then
    fail "reason '$reason' (runner family): emits the upload-ceiling pointer though nothing was uploaded"
  else
    pass "reason '$reason' does NOT emit the upload-ceiling pointer"
  fi
  # ...and it must still say something. Naming no channel is only honest if it explains why.
  if grep -qiE 'runner' <<<"$out"; then
    pass "reason '$reason' names the runner as the place to look"
  else
    fail "reason '$reason' (runner family): names no evidence at all — silence is not a diagnosis"
  fi
}

assert_unclassified() {
  local reason="$1" out
  out="$(run_degraded "$reason")"
  if grep -qF -- "$HOST_ANCHOR" <<<"$out" && grep -qF -- "PatchBlobUpload" <<<"$out"; then
    pass "reason '$reason' (unclassified) emits BOTH pointers — names no unmeasured cause"
  else
    fail "reason '$reason' (unclassified): must emit both pointers, got one or neither"
  fi
}

assert_verify_family() {
  local reason="$1" out
  out="$(run_degraded "$reason")"
  if grep -qiF -- "read back" <<<"$out"; then
    pass "reason '$reason' emits the read-back pointer"
  else
    fail "reason '$reason' (verify family): read-back pointer absent"
  fi
  # The inverse half, and the whole point of splitting this family out: verify must NOT be told
  # its failure is an upload deadline.
  if grep -qF -- "deadline expiring mid-upload" <<<"$out"; then
    fail "reason '$reason' (verify family): asserts an upload deadline it did not measure (ADR-166)"
  else
    pass "reason '$reason' does NOT assert an upload deadline"
  fi
  if grep -qF -- "$HOST_ANCHOR" <<<"$out"; then
    fail "reason '$reason' (verify family): still emits the host-health pointer"
  else
    pass "reason '$reason' does NOT emit the host-health pointer"
  fi
}

echo "--- upload family (loop-derived) ---"
for r in "${UPLOAD_FAMILY[@]}"; do assert_upload_family "$r"; done

echo "--- verify family (reads back; must not claim an upload deadline) ---"
for r in "${VERIFY_FAMILY[@]}"; do assert_verify_family "$r"; done

echo "--- host family ---"
for r in "${HOST_FAMILY[@]}"; do assert_host_family "$r"; done
echo "--- runner family (names NO registry channel) ---"
for r in "${RUNNER_FAMILY[@]}"; do assert_runner_family "$r"; done

echo "--- unclassified fail-safe ---"
for r in "${UNCLASSIFIED[@]}"; do assert_unclassified "$r"; done

# ---------------------------------------------------------------------------
# S8 — EVERY LIVE degraded() CALL SITE MUST LAND IN A DECLARED FAMILY.
# The families above are partly hardcoded, so a NEW call site routed to the wrong arm was
# invisible: measured, adding `degraded "copy_manifest_upload"` and routing it to the host arm
# left this suite 21/21 green — reinstating the exact #7555 defect (an upload failure pointed at
# registry-host telemetry) with the guard green. Derive the literal reasons from the run block
# and assert each is accounted for.
# ---------------------------------------------------------------------------
# COMMENT-STRIPPED, and anchored on the CALL form. A bare token grep matches the prose that
# explains the mechanism — this repo documents code directly above it, so an unanchored scan
# reads sentences containing the word "degraded" as call sites (measured: it extracted the
# words "fires message through"). Strip whole-line comments, then require the reason to sit at
# a command position: either line-start or after `|| `.
mapfile -t CALLSITE_REASONS < <(
  sed 's/^[[:space:]]*#.*$//' "$BLOCK" \
    | grep -oE '(^[[:space:]]*|\|\|[[:space:]]*)degraded[[:space:]]+"?[A-Za-z_][A-Za-z0-9_]*"?' \
    | sed -E 's/.*degraded[[:space:]]+"?//; s/"?$//' \
    | sort -u
)
DECLARED=("${UPLOAD_FAMILY[@]}" "${VERIFY_FAMILY[@]}" "${HOST_FAMILY[@]}" "${RUNNER_FAMILY[@]}" "${UNCLASSIFIED[@]}")
unaccounted=""
for r in "${CALLSITE_REASONS[@]}"; do
  [[ -n "$r" ]] || continue
  found=0
  for d in "${DECLARED[@]}"; do [[ "$r" == "$d" ]] && found=1; done
  [[ "$found" -eq 1 ]] || unaccounted="$unaccounted $r"
done
if [[ -z "$unaccounted" ]]; then
  pass "every literal degraded() call-site reason is in a declared family (${CALLSITE_REASONS[*]})"
else
  fail "degraded() call-site reason(s) not in any declared family:$unaccounted — a new stage was added without classifying it"
fi

# ---------------------------------------------------------------------------
# H1 (must-PASS, non-canonical). The guard enforces that the three anchors are
# PRESENT, not that they appear in a fixed order. A reworded pointer carrying all
# three in a different order must still pass — otherwise this suite pins prose
# rather than the property, and every future copy-edit reds it.
# ---------------------------------------------------------------------------
H1_TEXT="Content-Length vs latency on the PatchBlobUpload row is the evidence to read."
h1_missing=""
for a in "${UPLOAD_ANCHORS[@]}"; do
  grep -qF -- "$a" <<<"$H1_TEXT" || h1_missing="$h1_missing $a"
done
if [[ -z "$h1_missing" ]]; then
  pass "H1: a pointer with the three anchors in a different field order satisfies the assertion"
else
  fail "H1: order-independent anchor check rejected a valid pointer:$h1_missing"
fi

# ---------------------------------------------------------------------------
# AC3 — the BRIDGE arm's Better Stack read reports a FAILED READ, never a
# no-samples measurement, when it could not actually read.
#
# This is a DIFFERENT defect on a DIFFERENT arm from everything above, and the two
# are kept separately falsifiable on purpose: neither one's pass is evidence for
# the other. The measured symptom was a release run reporting "no zot_restarts
# samples in the last 3h" for a window that held 36 rows.
#
# Two fail-open paths fed it. The guard tested only BETTERSTACK_QUERY_HOST, so a
# partially-injected job entered the query arm; and betterstack-query.sh runs
# `set -uo pipefail` WITHOUT `-e`, so an internal failure can exit 0 with a
# ClickHouse error payload on stdout — which carries no `zot_restarts=` rows and
# therefore fell through to the no-samples arm.
# ---------------------------------------------------------------------------
BLOCK_DEDENT="$TMP/block2.sh"
sed 's/^  //' "$BLOCK" > "$BLOCK_DEDENT"
READ_FN="$TMP/bridge_read.sh"
awk '
  /^  RESTART_SUMMARY="\(not queried\)"$/ { inb=1 }
  inb { print }
  inb && /^  fi$/ { exit }
' "$BLOCK" | sed 's/^  //' > "$READ_FN"

if ! grep -q 'RESTART_SUMMARY="(not queried)"' "$READ_FN" || ! grep -qE '^fi$' "$READ_FN"; then
  fail "could not carve the bridge-arm Better Stack read out of the extracted block"
else
  pass "carved the bridge-arm Better Stack read from the workflow"

  # Sandbox with a stubbed scripts/betterstack-query.sh. The block invokes it by
  # PATH-relative path (`bash scripts/betterstack-query.sh`), not via $PATH, so the
  # stub must sit at that relative location and the block must run with the sandbox
  # as CWD.
  SBX="$TMP/sbx"; mkdir -p "$SBX/scripts"
  # STUB_MODE: rows | empty | errorpayload
  cat > "$SBX/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
case "${STUB_MODE:-rows}" in
  rows)
    echo 'boot_id=abc123 zot_restarts=41 oom_kills_5m=0'
    echo 'boot_id=abc123 zot_restarts=41 oom_kills_5m=0'
    ;;
  empty) : ;;                                   # a real, successful, genuinely empty read
  errorpayload)
    # The fail-open shape: exit 0, error text on stdout, zero data rows.
    echo 'Code: 241. DB::Exception: Memory limit exceeded'
    ;;
esac
exit 0
STUB
  chmod +x "$SBX/scripts/betterstack-query.sh"

  run_bridge_read() {
    # $1 = STUB_MODE; remaining args are creds to UNSET.
    local mode="$1"; shift
    (
      cd "$SBX" || exit 9
      export BETTERSTACK_QUERY_HOST="h" BETTERSTACK_QUERY_USERNAME="u" BETTERSTACK_QUERY_PASSWORD="p"
      export STUB_MODE="$mode"
      local v
      for v in "$@"; do unset "$v"; done
      # shellcheck disable=SC1090
      source "$READ_FN"
      printf '%s' "$RESTART_SUMMARY"
    )
  }

  FAILED_READ_MARK='FAILED READ'
  NO_SAMPLES_MARK='no zot_restarts samples'

  assert_failed_read() {
    local desc="$1" out="$2" want_named="${3:-}"
    if ! grep -qF -- "$FAILED_READ_MARK" <<<"$out"; then
      fail "$desc: expected a FAILED READ, got: ${out:0:120}"
      return
    fi
    if grep -qF -- "$NO_SAMPLES_MARK" <<<"$out"; then
      fail "$desc: reported a no-samples MEASUREMENT for a read that did not happen"
      return
    fi
    if [[ -n "$want_named" ]] && ! grep -qF -- "$want_named" <<<"$out"; then
      fail "$desc: failed read does not name the absent credential ($want_named)"
      return
    fi
    pass "$desc: reports a FAILED READ and names no measurement"
  }

  # Each of the three credentials, individually absent. USERNAME and PASSWORD are the
  # ones the HOST-only guard could not see.
  assert_failed_read "BETTERSTACK_QUERY_HOST absent" \
    "$(run_bridge_read rows BETTERSTACK_QUERY_HOST)" "BETTERSTACK_QUERY_HOST"
  assert_failed_read "BETTERSTACK_QUERY_USERNAME absent" \
    "$(run_bridge_read rows BETTERSTACK_QUERY_USERNAME)" "BETTERSTACK_QUERY_USERNAME"
  assert_failed_read "BETTERSTACK_QUERY_PASSWORD absent" \
    "$(run_bridge_read rows BETTERSTACK_QUERY_PASSWORD)" "BETTERSTACK_QUERY_PASSWORD"

  # Exit 0 with an error payload — the `set -uo pipefail` without `-e` fail-open.
  assert_failed_read "error payload on a zero exit" "$(run_bridge_read errorpayload)"

  # CONTROL (must-PASS). A genuinely successful, genuinely empty read is still a
  # MEASUREMENT and must NOT be relabelled a failure — otherwise this fix trades one
  # false message for another, and the suite could not tell the difference.
  EMPTY_OUT="$(run_bridge_read empty)"
  if grep -qF -- "$NO_SAMPLES_MARK" <<<"$EMPTY_OUT" && ! grep -qF -- "$FAILED_READ_MARK" <<<"$EMPTY_OUT"; then
    pass "control: a successful but empty read is still reported as a measurement"
  else
    fail "control: an empty successful read was mislabelled — got: ${EMPTY_OUT:0:120}"
  fi

  # CONTROL (must-PASS). A healthy read still produces the restart series.
  ROWS_OUT="$(run_bridge_read rows)"
  if grep -qF -- "zot_restarts=41" <<<"$ROWS_OUT"; then
    pass "control: a healthy read still reports the restart series"
  else
    fail "control: healthy read lost the restart series — got: ${ROWS_OUT:0:120}"
  fi
fi

# ---------------------------------------------------------------------------
# Anti-vacuity floor. Every assertion above is inside a loop over a derived set;
# if the derivation silently returned a short set, or the carve produced a
# degraded() that emits nothing, the counts collapse and the suite would report a
# green it did not earn. The floor is a function of the derived set size, so it
# cannot be satisfied by a run that examined less than it claims.
# ---------------------------------------------------------------------------
EXPECTED_MIN=$(( (${#UPLOAD_FAMILY[@]} * 2) + (${#VERIFY_FAMILY[@]} * 3) + (${#HOST_FAMILY[@]} * 2) + (${#RUNNER_FAMILY[@]} * 3) + ${#UNCLASSIFIED[@]} + 1 + 7 + 1 ))
# HARNESS CANARY + a floor that does NOT dispatch through the helper it guards. Neutering fail()
# to a no-op previously left this suite fully GREEN, and the floor's only voice was that same
# helper — so one edit disarmed the assertions AND their backstop.
_cp=$PASS; _cf=$FAIL
pass "canary: a true condition registers as PASS"
fail "canary: a false condition MUST register as FAIL (this line is EXPECTED)"
if [[ "$PASS" -ne $((_cp + 1)) || "$FAIL" -ne $((_cf + 1)) ]]; then
  echo "  FATAL: the assertion helpers are not counting — every verdict above is void." >&2
  exit 2
fi
FAIL=$((FAIL - 1))
TOTAL=$((PASS + FAIL))
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  echo "  FATAL: anti-vacuity: ran $TOTAL assertions, expected >= $EXPECTED_MIN — the derived set or the carve is short. Fix the derivation, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
