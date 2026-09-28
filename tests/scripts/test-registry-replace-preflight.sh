#!/usr/bin/env bash
# Tests scripts/registry-replace-preflight.sh (#7555) — the read-only preflight for the
# registry-host-replace dispatcher.
#
# Plan AC16 requires the pull-path pre-check to be "exercised by a test with a synthesized red
# reading". Every fixture here is SYNTHESIZED (cq-test-fixtures-synthesized-only); nothing is
# captured from a live query.
#
# The two cases that matter most are the ones a happy-path suite would omit:
#   * P0 fail-closed — a query that could not RUN must never read as "no events found".
#   * P2 must NOT gate — its emitter has been unreachable since #7071, so a gate keyed on it
#     would read CLEAN whether the fleet is healthy or its fallback is destroyed.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$ROOT/scripts/registry-replace-preflight.sh"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -r "$SUT" ]] || { echo "  FAIL: SUT not readable at $SUT"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

# --- stubs -------------------------------------------------------------------------------
# QUERY stub: dispatches on the --grep value, so a stub that ignores argv cannot pass. Exits
# with STUB_QUERY_RC when set, which is how the P0 credential arm is driven.
mk_query() {
  cat > "$TMP/query.sh" <<'STUB'
#!/usr/bin/env bash
marker=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --grep) marker="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$marker" ]] || { echo "stub: no --grep passed (the SUT must name what it queries)" >&2; exit 64; }
if [[ -n "${STUB_QUERY_RC:-}" && "${STUB_QUERY_RC}" != "0" ]]; then exit "${STUB_QUERY_RC}"; fi
case "$marker" in
  'registry=local-cache')   printf '%s' "${STUB_LOCAL_CACHE_ROWS:-}" ;;
  'registry=ghcr-fallback') printf '%s' "${STUB_GHCR_ROWS:-}" ;;
  # P5's two arms. Both default to a NON-empty row so the pre-existing cases keep
  # asserting what they were written to assert; the P5 cases below blank them
  # explicitly. Defaulting these to empty would have made every other test refuse
  # at P5 and silently stop testing P0-P3.
  'SOLEUR_ZOT_DISK')        printf '%s' "${STUB_ZOT_DISK_ROWS-SOLEUR_ZOT_DISK pcent=12 boot=93c52405}" ;;
  # NO BRACES IN THIS DEFAULT. A `}` inside ${VAR-default} terminates the expansion, so a
  # JSON-shaped default leaked a stray `}` when the test set this to empty — the dark-channel
  # case then measured one row and the assertion passed for the wrong reason.
  'HTTP API')               printf '%s' "${STUB_ZOT_LOG_ROWS-zot HTTP API statusCode:200 path:/v2/}" ;;
  *) : ;;
esac
exit 0
STUB
  chmod +x "$TMP/query.sh"
}
# gh stub: only `run list` is used.
#
# STUB_RUNS_DRAIN_AFTER makes the stub state-dependent: it returns STUB_RUNS_JSON for that many
# calls, then `[]`. That is what lets P3's WAIT arm be tested for real — a stub with a single
# fixed answer can only prove "refuses immediately" or "never refuses", never "waited, then
# proceeded once the push drained", which is the behaviour the modal delivery path depends on.
# (#8714 5.3b-iii) `gh api repos/<repo>/releases/tags/<tag>` is P6's read. The stub answers ONLY the
# exact path the SUT must ask for (STUB_API_PATH) and REFUSES (exit 64, logged to $STUB_API_REFUSALS)
# anything else, so a P6 that queried the wrong tag cannot read the right fixture.
mk_runs() {
  cat > "$TMP/gh.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" ]]; then
  if [[ "$#" -ne 2 || "$2" != "$STUB_API_PATH" ]]; then
    printf 'stub: unexpected gh api call: %s\n' "$*" | tee -a "$STUB_API_REFUSALS" >&2; exit 64
  fi
  if [[ -n "${STUB_API_RC:-}" && "${STUB_API_RC}" != "0" ]]; then
    printf '%s\n' "${STUB_API_ERR:-gh: Server Error (HTTP 502)}" >&2; exit "${STUB_API_RC}"
  fi
  printf '%s' "$STUB_API_JSON"; exit 0
fi
[[ "${1:-} ${2:-}" == "run list" ]] || { printf 'stub: unexpected gh call: %s\n' "$*" | tee -a "$STUB_API_REFUSALS" >&2; exit 64; }
if [[ -n "${STUB_RUNS_RC:-}" && "${STUB_RUNS_RC}" != "0" ]]; then exit "${STUB_RUNS_RC}"; fi
if [[ -n "${STUB_RUNS_DRAIN_AFTER:-}" ]]; then
  cnt=0
  [[ -f "$STUB_CALL_FILE" ]] && cnt="$(cat "$STUB_CALL_FILE")"
  cnt=$(( cnt + 1 )); printf '%s' "$cnt" > "$STUB_CALL_FILE"
  if [[ "$cnt" -gt "$STUB_RUNS_DRAIN_AFTER" ]]; then printf '%s' '[]'; exit 0; fi
fi
printf '%s' "${STUB_RUNS_JSON:-[]}"
exit 0
STUB
  chmod +x "$TMP/gh.sh"
}
mk_query; mk_runs

# P6's default fixture: the asset the REAL zot-registry.tf names, published with its pinned T, as the
# SECOND entry (a must-pass: P6 selects by name, not by position). Derived via --print-asset.
ASSET_INFO="$(bash "$SUT" --print-asset 2>/dev/null)" || { echo "  FATAL: --print-asset failed on the real zot-registry.tf"; exit 2; }
_ai() { printf '%s\n' "$ASSET_INFO" | sed -n "s/^$1=//p"; }
P6_REPO="$(_ai repo)"; P6_TAG="$(_ai tag)"; P6_ASSET="$(_ai asset)"; P6_T="$(_ai sha256)"
[[ -n "$P6_REPO" && -n "$P6_TAG" && -n "$P6_ASSET" && "$P6_T" =~ ^[0-9a-f]{64}$ ]] || { echo "  FATAL: --print-asset output incomplete: $ASSET_INFO"; exit 2; }
p6_json() {  # $1 = digest of the named asset ("" = no such asset), $2 = state
  local named=""
  [[ -n "$1" ]] && named=",{\"name\":\"$P6_ASSET\",\"state\":\"${2:-uploaded}\",\"digest\":\"$1\"}"
  printf '{"tag_name":"%s","draft":false,"assets":[{"name":"README.txt","state":"uploaded","digest":"sha256:%s"}%s]}' \
    "$P6_TAG" "$(printf '0%.0s' {1..64})" "$named"
}
export STUB_API_PATH="repos/$P6_REPO/releases/tags/$P6_TAG"
export STUB_API_JSON; STUB_API_JSON="$(p6_json "sha256:$P6_T")"
export STUB_API_REFUSALS="$TMP/api-refusals.log"; : > "$STUB_API_REFUSALS"

run_sut() {
  # `env -u GITHUB_ACTIONS` IS LOAD-BEARING, not hygiene. The SUT refuses every command seam when
  # GITHUB_ACTIONS is set (the production-path guard), and CI sets it to `true` for every job. So
  # without this the whole suite measured 18/18 on a developer laptop and 6/18 in the CI job that
  # actually gates the merge — the exact green-here-red-there shape this PR exists to remove.
  # The one test that NEEDS the guard active sets GITHUB_ACTIONS=true explicitly, downstream.
  # WAIT_SECS=0 by default so the ordinary P3 cases assert the REFUSAL without sleeping; the two
  # wait-arm tests below override it. A caller may pre-set it in the environment.
  #
  # Args before a literal `--` are STUB_*/env assignments; args after it are passed to the SUT
  # itself. Without the split, `env … -- --manual bash "$SUT"` makes env treat `--manual` as the
  # COMMAND to run, so the flag never reaches the script and the test would pass for the wrong
  # reason — while asserting that a flag works.
  local -a _envs=() _args=()
  local _seen=0
  for _a in "$@"; do
    if [[ "$_a" == "--" ]]; then _seen=1; continue; fi
    if [[ "$_seen" == 1 ]]; then _args+=("$_a"); else _envs+=("$_a"); fi
  done
  env -u GITHUB_ACTIONS \
      REGISTRY_PREFLIGHT_WAIT_SECS="${WANT_WAIT_SECS:-0}" \
      REGISTRY_PREFLIGHT_POLL_SECS="${WANT_POLL_SECS:-1}" \
      STUB_CALL_FILE="$TMP/calls.$RANDOM" \
      REGISTRY_PREFLIGHT_QUERY_CMD="$TMP/query.sh" \
      REGISTRY_PREFLIGHT_RUNS_CMD="$TMP/gh.sh" \
      REGISTRY_PREFLIGHT_ZOT_WRITERS="web-platform-release.yml" \
      "${_envs[@]}" bash "$SUT" "${_args[@]+"${_args[@]}"}" 2>"$TMP/err" ; RC=$?
}

# --- CONTROL: everything clean -> CLEAR ---------------------------------------------------
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_GHCR_ROWS="" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q 'verdict=CLEAR' "$TMP/out"; then
  pass "control: a clean pull path and no in-flight release yields verdict=CLEAR"
else
  fail "control: expected CLEAR/rc=0, got rc=$RC: $(head -1 "$TMP/out")"
fi

# --- P0: the query could not RUN (missing credentials, rc=3) -> REFUSED, fail-closed -------
# The whole point: a failed read must never be reported as "no local-cache events found".
run_sut STUB_QUERY_RC=3 STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P0' "$TMP/out"; then
  pass "P0 synthesized red: a credential failure (rc=3) REFUSES rather than reading as clean"
else
  fail "P0: expected REFUSED/P0, got rc=$RC: $(head -1 "$TMP/out")"
fi
if grep -qi 'not a clean reading' "$TMP/err"; then
  pass "P0 says WHY on stderr (a failed read is not a clean reading)"
else
  fail "P0 aborted mutely — the operator cannot tell a dead query from a healthy fleet"
fi

# A non-credential query failure must also fail closed, not fall through.
run_sut STUB_QUERY_RC=7 STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P0' "$TMP/out"; then
  pass "P0 synthesized red: a generic query failure (rc=7) also REFUSES"
else
  fail "P0 generic failure fell through: rc=$RC: $(head -1 "$TMP/out")"
fi

# --- P1: sustained local-cache pulls -> REFUSED (the #6400 hazard) ------------------------
run_sut STUB_LOCAL_CACHE_ROWS="$(printf 'pull registry=local-cache image=web\npull registry=local-cache image=inngest\n')" \
        STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P1' "$TMP/out"; then
  pass "P1 synthesized red: local-cache pull events REFUSE the replace"
else
  fail "P1: expected REFUSED/P1, got rc=$RC: $(head -1 "$TMP/out")"
fi
if grep -qi 'last' "$TMP/err"; then
  pass "P1 explains the hazard (the fleet is on its last tier)"
else
  fail "P1 aborted without naming why local-cache is disqualifying"
fi

# --- P2: MUST NOT GATE. A ghcr-fallback hit is advisory only. ------------------------------
# If a future edit promotes P2 to a gate, this case flips and the suite reds. That is the point:
# the operand is dark since #7071, so gating on it would read CLEAN in both worlds.
run_sut STUB_LOCAL_CACHE_ROWS="" \
        STUB_GHCR_ROWS="$(printf 'pull registry=ghcr-fallback image=web\n')" \
        STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q 'verdict=CLEAR' "$TMP/out"; then
  pass "P2 is ADVISORY: a ghcr-fallback hit does NOT gate the dispatch"
else
  fail "P2 gated the dispatch — its emitter is unreachable since #7071, so it cannot be a gate (rc=$RC)"
fi
if grep -q 'ghcr_fallback_hits=1' "$TMP/out"; then
  pass "P2 still REPORTS the count it refuses to gate on"
else
  fail "P2 dropped the count entirely — advisory must mean reported, not ignored"
fi
if grep -qi 'advisory' "$TMP/out"; then
  pass "P2's zero is explicitly marked as not-evidence in the output"
else
  fail "P2 emitted a bare count with no note that zero says nothing (a future reader will gate on it)"
fi

# --- P3: an in-progress release -> REFUSED -------------------------------------------------
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"in_progress"}]' > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "P3 synthesized red: an in-progress release run REFUSES the replace"
else
  fail "P3: expected REFUSED/P3, got rc=$RC: $(head -1 "$TMP/out")"
fi

# A failure to LIST runs must fail closed too — unknown is not zero.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_RC=1 > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "P3 fail-closed: an unlistable run set REFUSES rather than assuming zero"
else
  fail "P3 assumed zero in-flight releases when it could not list them: rc=$RC"
fi

# --- P3: a QUEUED run must gate too. Merging fires the release and the dispatcher on the SAME
# push, so at preflight time the release is very likely queued. `--status` takes one value, so the
# old single-status filter reported 0 for exactly the case P3 exists to catch.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"queued"}]' > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "P3 synthesized red: a QUEUED release run REFUSES the replace (not just in_progress)"
else
  fail "P3 missed a queued run: rc=$RC — this is the case the same-merge race actually produces"
fi

# --- P3 WAIT ARM: the modal delivery case must resolve ITSELF, not hand off to an operator. ----
# Merging a user_data change fires the release and this dispatcher on the same push, so "a
# release is queued" is the EXPECTED state. Refusing there made every ordinary delivery end in a
# comment telling a non-technical operator to type `gh workflow run`. These two pin the split:
# drains inside the budget -> proceed; still busy at the budget -> refuse.
WANT_WAIT_SECS=6 WANT_POLL_SECS=1 \
  run_sut STUB_LOCAL_CACHE_ROWS="" STUB_GHCR_ROWS="" \
          STUB_RUNS_JSON='[{"status":"queued"}]' STUB_RUNS_DRAIN_AFTER=2 > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q 'verdict=CLEAR' "$TMP/out" && grep -q 'waiting for the push to drain' "$TMP/out"; then
  pass "P3 wait: a queued run that DRAINS inside the budget proceeds without an operator step"
else
  fail "P3 wait: expected CLEAR after the writers drained, got rc=$RC: $(head -2 "$TMP/out" | tr '\n' ' ')"
fi

WANT_WAIT_SECS=3 WANT_POLL_SECS=1 \
  run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"in_progress"}]' > "$TMP/out"
# The verdict line goes to stdout; abort()'s explanation goes to stderr. Assert both, so a
# refusal that stopped saying HOW LONG it waited still reds.
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out" && grep -q 'after waiting' "$TMP/err"; then
  pass "P3 wait: a run still in flight at the budget REFUSES, and says how long it waited"
else
  fail "P3 wait: expected a bounded wait then REFUSED, got rc=$RC: $(head -1 "$TMP/out")"
fi

# --- the manual arm is reachable BY FLAG, and downgrades P1 only. ---------------------------
# `REGISTRY_PREFLIGHT_MANUAL` was read by the script and set by NO caller, so the documented
# recovery from a dark replace did not exist while the dispatcher's refusal comment asserted it
# did. The supported route is now a flag, because github.event_name is unforgeable where an env
# var of the same name is exactly what the seam guard refuses.
LC_ROWS="$(printf 'pull registry=local-cache image=web\n')"
run_sut STUB_LOCAL_CACHE_ROWS="$LC_ROWS" STUB_GHCR_ROWS="" STUB_RUNS_JSON="[]" -- --manual > "$TMP/out" 2>/dev/null || true
if grep -q 'verdict=CLEAR' "$TMP/out" && grep -qi 'MANUAL re-fire' "$TMP/out"; then
  pass "manual arm: --manual downgrades P1 to a NOTE so a replace outage cannot block its own recovery"
else
  fail "manual arm: --manual did not reach the P1 skip — the documented recovery path is inert: $(head -2 "$TMP/out" | tr '\n' ' ')"
fi

# ...but it must NOT be a blanket bypass: P3 still gates under --manual.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"in_progress"}]' -- --manual > "$TMP/out" 2>/dev/null || true
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "manual arm: --manual skips P1 ONLY — P3 still refuses a replace mid-push"
else
  fail "manual arm: --manual widened into a blanket bypass, which would allow a replace mid-push: rc=$RC"
fi

# An unknown argument must be refused, not ignored — a silently-dropped flag is how a caller
# believes it passed --manual when it did not.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON="[]" -- --manaul > "$TMP/out" || true
if [[ "$RC" -ne 0 ]] && grep -qi 'unknown argument' "$TMP/err"; then
  pass "a misspelled flag is refused rather than silently ignored"
else
  fail "an unknown argument was accepted — a typo'd --manual would silently keep P1 gating: rc=$RC"
fi

# --- P5: can the result of this replace be OBSERVED at all? --------------------------------
# P4 (a live serving probe) is deliberately absent, and its absence is defensible only because
# #7556 later reads zot's boot line out of the warehouse. P5 checks that justification is still
# true AT THE MOMENT OF THE REPLACE. The hazard is the #6400 escalation: a degraded zot still
# SERVES pulls today and only fails large-layer pushes, so firing blind trades a blocked release
# for a total deploy outage — with no SSH and no GHCR fallback (#7071) beneath it.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_GHCR_ROWS="" STUB_RUNS_JSON="[]" \
        STUB_ZOT_LOG_ROWS="" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P5' "$TMP/out"; then
  pass "P5 synthesized red: control alive but the CONTAINER-LOG channel is dark REFUSES the replace (#7569)"
else
  fail "P5: a dark container-log channel did not refuse — the replace would be unverifiable: rc=$RC: $(head -1 "$TMP/out")"
fi
# ...and it must say WHY, naming the tracking issue, or the operator cannot act on it.
if grep -qi '7569' "$TMP/err"; then
  pass "P5 names the tracking issue so the refusal is actionable"
else
  fail "P5 refused without naming what to fix"
fi

# The positive control is the load-bearing half: an EMPTY query is not evidence of a dark
# channel. If the control marker is also silent, the READ is broken and P5 must refuse for that
# reason instead — reading it as "channel dark" would misattribute a broken query to #7569.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_GHCR_ROWS="" STUB_RUNS_JSON="[]" \
        STUB_ZOT_DISK_ROWS="" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P5' "$TMP/out" && grep -qi 'warehouse read itself' "$TMP/err"; then
  pass "P5 distinguishes a BROKEN READ from a dark channel, and refuses on the read"
else
  fail "P5 attributed a broken read to a dark channel (or did not refuse): rc=$RC"
fi

# Both arms alive -> P5 must NOT gate. Without this the predicate could refuse unconditionally
# and every case above would still pass.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_GHCR_ROWS="" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q 'obs_channel_hits=' "$TMP/out"; then
  pass "P5 passes when both arms deliver, and REPORTS both observed counts"
else
  fail "P5 refused (or dropped its counts) on a healthy channel: rc=$RC: $(head -1 "$TMP/out")"
fi

# --- P6: the boot-image asset the replaced host will fetch must exist and match the pin ----------
# (#8714 5.3b-iii) The host refuses to start zot unless the asset's sha256 is the pinned T, so a
# replace onto an absent or altered asset darks the sole pull path. Each row changes ONE input.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q "boot_asset=$P6_TAG/$P6_ASSET" "$TMP/out" && grep -q 'NOTE: P6' "$TMP/out"; then
  pass "P6 must-pass: the pinned asset published with digest == T (not the first asset listed) is CLEAR"
else
  fail "P6 refused a correctly published asset: rc=$RC: $(head -2 "$TMP/out" | tr '\n' ' ')"
fi
run_sut STUB_API_RC=1 STUB_API_ERR="gh: Not Found (HTTP 404)" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out" && grep -q 'not published' "$TMP/err"; then
  pass "P6 synthesized red: an UNPUBLISHED release (404) REFUSES the replace, and says how to publish"
else
  fail "P6: a missing release did not refuse as P6: rc=$RC: $(head -1 "$TMP/out")"
fi
run_sut STUB_API_RC=1 STUB_API_ERR="gh: Server Error (HTTP 502)" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out" && grep -qi 'failed read is not a present asset' "$TMP/err"; then
  pass "P6 fail-closed (M1): an API ERROR refuses rather than reading as present"
else
  fail "P6: an API error fell through: rc=$RC: $(head -1 "$TMP/out")"
fi
run_sut STUB_API_JSON="$(p6_json "sha256:$(printf 'e%.0s' {1..64})")" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out" && grep -q 'pins sha256' "$TMP/err"; then
  pass "P6 synthesized red (M3): an asset whose digest != T REFUSES (presence alone is not enough)"
else
  fail "P6: a digest mismatch did not refuse: rc=$RC: $(head -1 "$TMP/out")"
fi
run_sut STUB_API_JSON="$(p6_json "")" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out" && grep -q 'no uploaded' "$TMP/err"; then
  pass "P6 synthesized red: a published release WITHOUT the asset REFUSES"
else
  fail "P6: a release missing the asset did not refuse: rc=$RC: $(head -1 "$TMP/out")"
fi
run_sut STUB_API_JSON="$(p6_json "sha256:$P6_T" starter)" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out"; then
  pass "P6 synthesized red: an asset still in state=starter (not uploaded) REFUSES"
else
  fail "P6: a not-yet-uploaded asset was accepted: rc=$RC: $(head -1 "$TMP/out")"
fi
run_sut STUB_API_JSON='not json' STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out"; then
  pass "P6 fail-closed: an unparseable API response REFUSES"
else
  fail "P6: unparseable JSON was accepted: rc=$RC: $(head -1 "$TMP/out")"
fi
# M2: T comes from the .tf, never a copy. A .tf whose T moved (a bump pinned before its asset was
# published) must refuse even though the stub still serves the OLD digest for the same tag.
sed "s/$P6_T/$(printf 'a%.0s' {1..64})/" "$ROOT/apps/web-platform/infra/zot-registry.tf" > "$TMP/zot-registry.moved-T.tf"
grep -q "$(printf 'a%.0s' {1..64})" "$TMP/zot-registry.moved-T.tf" || { echo "  FATAL: the moved-T mutation did not land"; exit 2; }
run_sut REGISTRY_PREFLIGHT_TF="$TMP/zot-registry.moved-T.tf" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out"; then
  pass "P6 synthesized red (M2): the .tf's T changed while the asset kept the old digest -> REFUSES"
else
  fail "P6 compared against something other than the .tf's T: rc=$RC: $(head -1 "$TMP/out")"
fi
sed '/zot_mirror_asset_sha256_amd64[[:space:]]*=/d' "$ROOT/apps/web-platform/infra/zot-registry.tf" > "$TMP/zot-registry.no-T.tf"
run_sut REGISTRY_PREFLIGHT_TF="$TMP/zot-registry.no-T.tf" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out"; then
  pass "P6 fail-closed: a .tf with no pinned T REFUSES rather than skipping the check"
else
  fail "P6: an unreadable pin did not refuse: rc=$RC: $(head -1 "$TMP/out")"
fi
# P6 is NOT skipped on the manual arm (M4-adjacent: it must stay gating on every route).
run_sut STUB_API_RC=1 STUB_API_ERR="gh: Not Found (HTTP 404)" STUB_RUNS_JSON="[]" -- --manual > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out"; then
  pass "P6 still gates a --manual re-fire (a manual replace onto a missing asset darks the host too)"
else
  fail "P6 was bypassed by --manual: rc=$RC"
fi
# P6 refuses BEFORE P3's drain wait: a missing asset must not hold the job for 35 minutes first.
WANT_WAIT_SECS=30 WANT_POLL_SECS=1 \
  run_sut STUB_API_RC=1 STUB_API_ERR="gh: Not Found (HTTP 404)" STUB_RUNS_JSON='[{"status":"queued"}]' > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out" && ! grep -q 'waiting for the push to drain' "$TMP/out"; then
  pass "P6 refuses before P3 waits"
else
  fail "P6 ran after (or not instead of) P3's wait: rc=$RC: $(head -2 "$TMP/out" | tr '\n' ' ')"
fi
run_sut STUB_API_JSON="$(printf '{"assets":[{"name":"%s","state":"uploaded","digest":"sha256:%s"},{"name":"%s","state":"uploaded","digest":"sha256:%s"}]}' "$P6_ASSET" "$P6_T" "$P6_ASSET" "$P6_T")" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out" && grep -q 'ambiguous' "$TMP/err"; then
  pass "P6 synthesized red: two uploaded assets with the asset's name (even both == T) REFUSE as ambiguous"
else
  fail "P6 accepted an ambiguous asset list: rc=$RC: $(head -1 "$TMP/out")"
fi
# --check-asset: P6 ALONE, for the routes that create a registry host without this dispatcher
# (apply-web-platform-infra.yml registry_host_replace / luks_recut / region_migrate) and rule-audit.
run_sut STUB_LOCAL_CACHE_ROWS="$(printf 'pull registry=local-cache image=web\n')" STUB_RUNS_JSON='[{"status":"in_progress"}]' -- --check-asset > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -qx "verdict=CLEAR predicate=P6 boot_asset=$P6_TAG/$P6_ASSET" "$TMP/out" && ! grep -q 'local_cache_hits' "$TMP/out"; then
  pass "--check-asset runs P6 only: CLEAR on a published asset even with P1/P3 conditions that would refuse a replace"
else
  fail "--check-asset did not run P6 alone: rc=$RC: $(head -2 "$TMP/out" | tr '\n' ' ')"
fi
run_sut STUB_API_RC=1 STUB_API_ERR="gh: Not Found (HTTP 404)" -- --check-asset > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P6' "$TMP/out" && grep -q 'immutable releases' "$TMP/err"; then
  pass "--check-asset refuses a missing asset, and says a vanished release cannot be re-created under its tag"
else
  fail "--check-asset passed a missing asset: rc=$RC: $(head -1 "$TMP/out")"
fi
if [[ ! -s "$STUB_API_REFUSALS" ]]; then
  pass "P6 asked the gh stub only for repos/$P6_REPO/releases/tags/$P6_TAG (no refused call)"
else
  fail "the SUT made a gh call the stub refused: $(head -3 "$STUB_API_REFUSALS" | tr '\n' ' ')"
fi

# --- the seam guard: a seam set on the production path must REFUSE, not manufacture CLEAR ------
SEAM_OUT="$(env GITHUB_ACTIONS=true REGISTRY_PREFLIGHT_QUERY_CMD=/bin/true \
  REGISTRY_PREFLIGHT_RUNS_CMD=/bin/true bash "$SUT" 2>"$TMP/seamerr")"; SEAM_RC=$?
if [[ "$SEAM_RC" -ne 0 ]] && grep -q 'predicate=SEAM' <<<"$SEAM_OUT"; then
  pass "seam guard: a test seam set inside GitHub Actions REFUSES rather than reporting CLEAR"
else
  fail "seam guard absent: seams manufactured a verdict on the production path (rc=$SEAM_RC)"
fi

# The COMMAND seams were on that list; the DATA seams were not, and they are the ones that
# manufacture a CLEAR verdict rather than an error. Measured: with the three real writers
# mid-push, retargeting ZOT_WRITERS at an idle workflow turned REFUSED/P3 into CLEAR. One arm per
# seam, because a loop over a list is satisfied by any single member being present.
for _dseam in REGISTRY_PREFLIGHT_ZOT_WRITERS REGISTRY_PREFLIGHT_P5_CONTROL REGISTRY_PREFLIGHT_P5_CHANNEL REGISTRY_PREFLIGHT_TF; do
  DS_OUT="$(env GITHUB_ACTIONS=true "$_dseam=x" bash "$SUT" 2>/dev/null)"; DS_RC=$?
  if [[ "$DS_RC" -ne 0 ]] && grep -q 'predicate=SEAM' <<<"$DS_OUT"; then
    pass "seam guard: $_dseam is refused on the production path"
  else
    fail "$_dseam was NOT refused inside Actions — it can manufacture a CLEAR verdict (rc=$DS_RC)"
  fi
done

# --- P4 must stay absent, and the reason must stay recorded -------------------------------
if grep -q 'P4' "$SUT" && grep -qi 'DELIBERATELY ABSENT' "$SUT"; then
  pass "P4's deliberate absence is recorded in-file (or it gets re-added)"
else
  fail "P4's exclusion rationale is missing — a serving probe will be re-added"
fi
if grep -qiE 'GET /v2/|serving probe' "$SUT" && ! grep -qE '^\s*[^#]*curl.*(/v2/|health)' "$SUT"; then
  pass "P4 is named but not implemented (no live serving probe in the code path)"
else
  fail "a live serving probe appears to have been added — see ADR-169 ground 2"
fi

# --- The anti-recoupling guard the CTO decision requires ----------------------------------
if grep -q 'registry-pull-path-health.sh' "$SUT" && grep -qi 'NOT scripts/registry-pull-path-health.sh' "$SUT"; then
  pass "the header pre-empts re-coupling to the D10 recut gate"
else
  fail "the header does not warn against calling registry-pull-path-health.sh — it will be re-coupled"
fi
if grep -qE '^\s*[^#]*registry-pull-path-health\.sh' "$SUT"; then
  fail "the preflight actually INVOKES the D10 recut gate — a volume-preserving replace must not"
else
  pass "the preflight does not invoke the D10 recut gate"
fi

# --- anti-vacuity floor -------------------------------------------------------------------
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
TOTAL=$((PASS+FAIL))
# 30 assertions ran before #8714 5.3b-iii (floor was 26); +15 P6/--check-asset rows and +1 seam-guard arm = 46.
if [[ "$TOTAL" -lt 46 ]]; then
  echo "  FATAL: anti-vacuity: ran $TOTAL assertions, expected >= 46. Fix the dispatch, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
