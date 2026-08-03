#!/usr/bin/env bash
# Verifies the RELEASE-BLOCKING + bounded-retry + degraded-signal behavior of the
# "Mirror image GHCR→zot" step in .github/workflows/reusable-release.yml
# (#6274 originally; rewritten by #7071).
#
# HEADER CORRECTED 2026-07-30 (#7071). Everything below described the pre-#7071
# design and was left untouched while the body of this file was rewritten around
# it — the diff started ~80 lines down, so the header was never opened. It
# asserted four things that are now false: that the mirror is a SECONDARY/shadow
# copy, that GHCR stays primary + break-glass with an atomic pull-side fallback,
# that the step is non-blocking via `continue-on-error` plus an inner shell whose
# every failure path exits 0, and that a persistent miss surfaces as
# `::warning::`. See the comment block at the `degraded()` assertions below for
# what replaced each.
#
# Current design: GHCR is DEAD as a read path (PAT revoked -> 401, minter
# disabled -> 403 DENIED), so zot is the SOLE registry production can pull from
# and a release that does not land in zot must not publish. `continue-on-error`
# is gone, `degraded()` exits non-zero (except under an explicit dispatch
# override, and never for a digest MISMATCH), a positive post-copy `crane digest`
# assertion proves the manifest is present AT THE EXPECTED DIGEST before
# `mirror_status=ok`, and a persistent miss is `::error::` + a blocked release.
# The bounded `retry` around the network ops survives unchanged — it self-heals
# the transient `connection reset by peer` mid blob-upload over the multi-hop
# CF-tunnel bridge that motivated the original change.
#
# This test removes crane/cosign/curl/the network from the assertion path by
# executing the REAL mirror `run:` block (extracted verbatim from the workflow)
# under deterministic stubs on PATH, exactly like the sibling
# reusable-release-idempotency.test.sh convention. Run via:
#   bash plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"

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
assert_eq() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    pass "$desc"
  else
    fail "$desc -> got '$got', want '$want'"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Extract a step's `run:` block verbatim from the workflow (dedented to the
# block-scalar base indent). Same helper as reusable-release-idempotency.test.sh
# — index() (literal substring), not a `$0 ~` regex: the step name contains
# regex metachars ("(crane)", "→") a dynamic regex would mis-handle.
# ---------------------------------------------------------------------------
extract_run_block() {
  local step_name="$1"
  awk -v target="$step_name" '
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

MIRROR_BLOCK="$TMP/mirror.sh"
extract_run_block "Mirror image GHCR→zot (crane) + cosign-sign the zot digest" > "$MIRROR_BLOCK"

if [[ ! -s "$MIRROR_BLOCK" ]]; then
  fail "could not extract the mirror run block from $WF"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# Deterministic stubs. The install prelude (curl/sha256sum/sudo/tar) is
# no-op'd so the test exercises only the retry + degraded-signal logic; `sleep`
# is no-op'd so the retry backoff does not add real wall-clock. `crane copy`
# behavior is driven by MOCK_CRANE_MODE (always_ok | always_fail | fail_once)
# and every `copy` invocation is counted to $MOCK_CRANE_COUNT.
# ---------------------------------------------------------------------------
STUB_DIR="$TMP/bin"
mkdir -p "$STUB_DIR"
for c in sha256sum sudo tar sleep; do
  cat > "$STUB_DIR/$c" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_DIR/$c"
done
# `curl` and `cosign` are mode-aware so the crane-INSTALL arm and the cosign-SIGN arm can
# be driven. Both had zero fixtures: each was individually deletable from the workflow with
# the whole suite green, and the sign arm is the only stage whose message may legitimately
# name Sigstore — the negative T8 asserts on the copy arm had no positive anywhere.
cat > "$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
[[ "${MOCK_CRANE_MODE:-}" == "install_fail" ]] && exit 22
exit 0
STUB
chmod +x "$STUB_DIR/curl"
cat > "$STUB_DIR/cosign" <<'STUB'
#!/usr/bin/env bash
[[ "${MOCK_CRANE_MODE:-}" == "sign_fail" && "${1:-}" == "sign" ]] && exit 1
exit 0
STUB
chmod +x "$STUB_DIR/cosign"
cat > "$STUB_DIR/crane" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "copy" ]]; then
  c=0
  [[ -f "$MOCK_CRANE_COUNT" ]] && c=$(cat "$MOCK_CRANE_COUNT")
  c=$((c + 1)); echo "$c" > "$MOCK_CRANE_COUNT"
  case "${MOCK_CRANE_MODE:-always_ok}" in
    always_fail) exit 1 ;;
    fail_once)   [[ "$c" -eq 1 ]] && exit 1 || exit 0 ;;
    # Fail only the ${COMMIT_SHA} tag's arm, matched on the REF rather than on the
    # invocation counter: the counter would have to encode retry arithmetic (tag 1 costs
    # 1 call, the failing tag costs 3), so it would silently target the wrong arm the
    # moment the retry bound changes. This drives the "a later copy arm fails, so the
    # loop aborts before cosign sign" case.
    fail_sha_tag) [[ "$*" == *"${MOCK_SHA_TAG:-abc123def}"* ]] && exit 1 || exit 0 ;;
    # The THIRD copy arm, matched on the ref for the same reason as fail_sha_tag.
    fail_latest_tag) [[ "$*" == *":latest"* ]] && exit 1 || exit 0 ;;
    *)           exit 0 ;;
  esac
fi
# The post-copy verification read. `crane digest <ref>` prints the manifest digest on
# stdout; the step compares it against the DIGEST the build pushed. Default is the
# MATCH case (echo back $DIGEST) so every pre-existing test keeps describing crane-copy
# behavior only. MOCK_CRANE_DIGEST_MODE drives the two failure shapes the assertion has
# to tell apart — a WRONG digest (zot holds some other build at this tag) and an
# UNRESOLVABLE one (the tag is not in zot at all) — because collapsing them would let a
# "verify" reason be reported for a copy that silently mirrored a different image.
if [[ "${1:-}" == "digest" ]]; then
  case "${MOCK_CRANE_DIGEST_MODE:-match}" in
    mismatch) echo "sha256:0000000000000000000000000000000000000000000000000000000000000000"; exit 0 ;;
    fail)     echo "Error: fetching manifest: unexpected status code 404" >&2; exit 1 ;;
    *)        echo "${DIGEST:-sha256:deadbeef}"; exit 0 ;;
  esac
fi
exit 0
STUB
chmod +x "$STUB_DIR/crane"

# Run the extracted mirror block once; echo
#   "<rc> <mirror_status> <loud|quiet> <crane_copies> <mirror_reason>".
#
# $2 = BRIDGE_OUTCOME (#6416), defaulting to the healthy-bridge case so T1-T3 keep
# describing crane behavior only.
# $3 = MOCK_CRANE_DIGEST_MODE, defaulting to the digest-matches case for the same reason.
# $4 = MIRROR_OVERRIDE_REASON, defaulting to EMPTY — the gate is blocking unless an
#      operator supplies a reason via workflow_dispatch.
#
# The third field is `loud|quiet`, not `warn|nowarn`: the failure annotation is now
# ::error:: rather than ::warning::, because the step no longer degrades a release — it
# blocks one. Matching either keeps the field meaning "did this run shout at the
# operator", which is the property the tests actually assert. The LAST field is the new
# mirror_reason output; the whole point of FR-A3 is that "not ok" alone cannot name a
# cause, so every failing case pins WHICH stage failed rather than only that one did.
run_mirror() {
  local mode="$1"
  local bridge_outcome="${2:-success}"
  local digest_mode="${3:-match}"
  local override_reason="${4:-}"
  local out="$TMP/ghout.$RANDOM" summary="$TMP/ghsum.$RANDOM"
  local log="$TMP/log.$RANDOM" count="$TMP/cranecount.$RANDOM"
  : > "$out"; : > "$summary"; : > "$count"
  local rc
  MOCK_CRANE_MODE="$mode" \
  MOCK_CRANE_COUNT="$count" \
  MOCK_CRANE_DIGEST_MODE="$digest_mode" \
  GITHUB_OUTPUT="$out" \
  GITHUB_STEP_SUMMARY="$summary" \
  IMAGE="ghcr.io/jikig-ai/soleur-web-platform" \
  DIGEST="sha256:deadbeef" \
  VERSION="1.2.3" \
  COMMIT_SHA="abc123def" \
  BRIDGE_OUTCOME="$bridge_outcome" \
  MIRROR_OVERRIDE_REASON="$override_reason" \
  GITHUB_WORKSPACE="$REPO_ROOT" \
  TOKEN_VERDICT="${5:-unmeasured}" \
  TOKEN_CHECKED_AT="${6:-}" \
  TOKEN_CAUSE="${7:-unknown}" \
  PATH="$STUB_DIR:$PATH" \
    bash "$MIRROR_BLOCK" > "$log" 2>&1
  rc=$?
  local status warn copies reason
  status=$(grep -E '^mirror_status=' "$out" | tail -1 | cut -d= -f2)
  reason=$(grep -E '^mirror_reason=' "$out" | tail -1 | cut -d= -f2)
  if grep -qE '::(warning|error)::' "$log"; then warn=loud; else warn=quiet; fi
  copies=$(cat "$count" 2>/dev/null || echo 0)
  echo "$rc ${status:-<unset>} $warn ${copies:-0} ${reason:-<unset>}"
}

# The log / $GITHUB_OUTPUT of the LAST run_mirror call, for content assertions.
last_log() { ls -t "$TMP"/log.* 2>/dev/null | head -1; }
last_out() { ls -t "$TMP"/ghout.* 2>/dev/null | head -1; }

echo "=== reusable-release zot-mirror non-blocking + retry tests ==="
echo ""

# T1 — persistent failure: every crane copy fails. The retry loop runs exactly
# 3 attempts on the first tag, then the step reports the failure and exits NON-ZERO.
#
# The expected rc flipped 0 -> 1 here and at T4. That is the whole change, and freezing
# these two literals would have been a test protecting the bug: they encoded "a mirror
# miss must not red the release", which was correct only while GHCR was a working
# break-glass pull path. With GHCR's pull credential revoked, an image absent from zot
# cannot be deployed at all, so a green release carrying that state is a lie.
# The reason field pins copy_v — the FIRST tag's arm — proving the abort happens where
# the failure is, not at some later stage that would misdirect the operator.
echo "T1: persistent failure -> 3 attempts, mirror_status=degraded, ::error::, exit 1"
assert_eq "persistent fail" "$(run_mirror always_fail)" "1 degraded loud 3 copy_v"

# T2 — transient self-heal: crane fails the first attempt then succeeds. No
# failure signal; the mirror completes clean.
echo "T2: transient self-heal -> mirror_status=ok, exit 0, no ::error::"
out2="$(run_mirror fail_once)"
assert_eq "transient rc/status/warn" "$(echo "$out2" | cut -d' ' -f1-3)" "0 ok quiet"

# T3 — happy path: crane succeeds first try for all three tags.
echo "T3: happy path -> mirror_status=ok, exit 0, no ::error::"
out3="$(run_mirror always_ok)"
assert_eq "happy rc/status/warn" "$(echo "$out3" | cut -d' ' -f1-3)" "0 ok quiet"

# ---------------------------------------------------------------------------
# T4/T5 (#6416) — the bridge-outcome branch.
#
# Before #6416 this step carried `if: steps.zot_bridge.outcome == 'success'`, so a
# FAILED bridge SKIPPED the step entirely. A skipped step runs no emitter, so
# `steps.zot_mirror.outputs.mirror_status` stayed unset and the Slack ⚠️ that reads
# it (by step id) said nothing — zot silently never received images while the
# release stayed green. The gate now keys on docker_build and the bridge is handled
# INSIDE the step, so the degraded signal reaches the same output the Slack line
# already consumes.
#
# The crane-copy count is the load-bearing half of T4: it proves the branch exits
# BEFORE attempting a mirror there is no bridge for, rather than merely arriving at
# the same status the long way round (which would pass against an implementation
# that ignored BRIDGE_OUTCOME entirely — crane would fail anyway and emit degraded).
# ---------------------------------------------------------------------------

# T4 — bridge failed: report the failure WITHOUT attempting any crane copy, exit 1.
echo "T4: bridge failure -> mirror_status=degraded, ::error::, exit 1, ZERO crane copies"
assert_eq "bridge failure" "$(run_mirror always_ok failure)" "1 degraded loud 0 bridge"

# T5 — bridge SKIPPED (docker_build failed upstream): `== 'failure'` must not fire on
# 'skipped'. Pins the choice of `== 'failure'` over `!= 'success'`: the latter would
# label a build failure a "zot mirror degraded", which is a misleading thing to say
# about a release that never produced an image. Here the mirror proceeds normally.
echo "T5: bridge skipped -> not treated as a bridge failure (no false degraded)"
assert_eq "bridge skipped" "$(run_mirror always_ok skipped)" "0 ok quiet 3 <unset>"

# ---------------------------------------------------------------------------
# T6-T10 — the fail-closed gate itself.
#
# These are NEW cases, not rewrites: T1-T5 above describe crane-copy and bridge-branch
# behavior, and none of them can observe the post-copy assertion (they all ran against a
# step that had no assertion to observe). Every case below pins a state that did not
# exist before this change.
# ---------------------------------------------------------------------------

# T6 — the load-bearing case. Every copy SUCCEEDS and cosign signs, but zot serves a
# DIFFERENT digest at this tag than the one this build pushed. Before the assertion this
# was indistinguishable from a clean mirror: mirror_status=ok, release green, and the
# host would later pull an image that is not the one the release notes describe. The
# copies must all have been attempted (3) — the assertion is post-copy, so a run that
# short-circuits earlier would be testing something else.
echo "T6: zot holds a DIFFERENT digest -> mirror_reason=verify, exit 1, after all 3 copies"
assert_eq "digest mismatch" "$(run_mirror always_ok success mismatch)" "1 degraded loud 3 verify"
_t6_log="$(last_log)"
if grep -qF 'DIFFERENT image' "$_t6_log"; then
  pass "mismatch message names the wrong-image case"
else
  fail "mismatch message must tell the operator zot holds a DIFFERENT image"
fi

# T7 — the tag is not resolvable in zot at all (crane digest exits non-zero). Distinct
# from T6: the copy reported success but nothing is addressable.
#
# The rc/status/reason tuple ALONE cannot tell these two apart — an empty ZOT_DIGEST also
# fails the mismatch comparison, so a run with the unresolvable branch deleted still
# reports exactly "1 degraded loud 3 verify". That was measured: mutating the branch to
# `if false` left this test GREEN. The tuple assertion is therefore kept only as the
# fail-closed check, and the MESSAGE is what pins the branch — because reporting "zot
# holds a DIFFERENT image, zot has <empty>" when in fact nothing is there is precisely
# the name-an-unmeasured-cause defect this PR exists to remove. The negative half
# (must NOT say DIFFERENT image) is the half that has teeth; T6 above proves that string
# is reachable, so this negative is not vacuous.
echo "T7: crane digest cannot resolve the tag -> fail closed, and NOT reported as a mismatch"
assert_eq "digest unresolvable" "$(run_mirror always_ok success fail)" "1 degraded loud 3 verify"
_t7_log="$(last_log)"
_t7_ok=1
grep -qF 'no readable manifest' "$_t7_log" || _t7_ok=0
grep -qF 'DIFFERENT image' "$_t7_log" && _t7_ok=0
if [[ "$_t7_ok" == "1" ]]; then
  pass "unresolvable message names the absent-manifest case and never claims a digest mismatch"
else
  fail "unresolvable read must report an absent manifest, NOT a digest mismatch (got: $(grep -o '::error::.*' "$_t7_log" | head -c 200))"
fi

# T8 — a LATER copy arm fails, so the loop aborts before cosign sign ever runs. The
# reason must name the arm that actually failed (copy_sha), and the operator message
# must NOT mention Sigstore. An earlier draft labelled this state `signing_failed` and
# advised waiting out a Sigstore outage — advice that is wrong for the case it fires on
# most often, since degraded() is a first-failure abort. This asserts the message
# CONTENT, not just the label, because the label being right does not stop the prose
# from naming an unmeasured cause.
echo "T8: second copy arm fails -> mirror_reason=copy_sha and the message never says Sigstore"
_t8_out="$(run_mirror fail_sha_tag success match)"
_t8_log="$(last_log)"
assert_eq "copy_sha reason" "$(echo "$_t8_out" | cut -d' ' -f1,2,5)" "1 degraded copy_sha"
if grep -qi 'sigstore' "$_t8_log"; then
  fail "copy-arm message must not blame Sigstore (it aborts before cosign sign runs)"
else
  pass "copy-arm message does not blame Sigstore"
fi

# T9 — every failure message must tell the operator that nothing was half-shipped and
# name the bypass hatch. A blocked release is the safest failure this pipeline has, and
# an operator who does not know that will reach for something more dangerous than
# re-running. Asserted on the bridge arm, the one a human is most likely to meet.
echo "T9: the failure message states the release is an unpublished draft + names a REAL remedy"
run_mirror always_ok failure >/dev/null
_t9_log="$(last_log)"
_t9_ok=1
grep -qF 'UNPUBLISHED DRAFT' "$_t9_log" || _t9_ok=0
# The recovery verb must be the one that preserves the version. "Re-run failed jobs" keeps
# the push event so the merge PR's semver label is re-read; a fresh dispatch defaults the
# bump_type and can strand the draft permanently.
grep -qF 'Re-run failed jobs' "$_t9_log" || _t9_ok=0
# #7242. The `check-cloudflare-token-drift.sh` assertion MOVED, and the move is the point.
#
# Both literals above live in the shared $SAFE_TO_RERUN suffix that degraded() appends to
# EVERY call, so asserting them here proves only that degraded() ran — they pass for any
# arm, including a blank one. That made this test read as per-arm coverage while providing
# none. The detector command is now arm-DEPENDENT (it must appear on stale/unverifiable/
# unmeasured and must NOT headline `live`, because on `live` the job has already measured
# the credential and rotation is ruled out), so pinning it to a fixed string here would
# re-assert the very misdiagnosis this PR removes.
#
# Per-arm text is asserted where it can be driven directly, as function calls, in
# scripts/zot-mirror-diagnosis.test.sh. What belongs HERE is only what this harness alone
# can see: that the block actually reaches the shared helper and renders its OUTPUT.
#
# The anchor is a literal only the REAL helper emits. An earlier version of this line
# grepped for the helper's own filename, which the block's could-not-load FALLBACK also
# prints — so it passed identically whether the helper loaded or not. That is the
# assert-the-definition-not-the-invocation trap, committed inside the fix for it.
grep -qF 'NOTHING WAS MEASURED' "$_t9_log" || _t9_ok=0
grep -qF 'could not be loaded' "$_t9_log" && _t9_ok=0
# NEGATIVE, and the half with teeth: apply-deploy-pipeline-fix.yml must NOT be offered as a
# way to ship past this gate. It redeploys the CURRENTLY RUNNING version (it resolves its
# tag from web-1's /health) and hard-errors without a released semver, so an operator
# following it during an incident spends ~70 minutes to arrive where they started. This
# assertion previously pinned that false claim — a test protecting a lie.
grep -qF 'apply-deploy-pipeline-fix.yml' "$_t9_log" && _t9_ok=0
if [[ "$_t9_ok" == "1" ]]; then
  pass "bridge message: unpublished-draft reassurance + the version-preserving re-run verb + real helper output, and no false bypass hatch"
else
  fail "bridge message must name 'Re-run failed jobs', render the REAL helper output (not its could-not-load fallback), and must NOT name apply-deploy-pipeline-fix.yml as a ship path"
fi

# T17 (#7242) — the arm actually SWITCHES on the verdict the job measured.
#
# This is the assertion scripts/zot-mirror-diagnosis.test.sh structurally cannot make: it
# calls the function directly, so it proves the four texts differ but says nothing about
# whether the BLOCK routes a verdict to them.
#
# SCOPE, stated because the obvious reading is wrong: this harness injects TOKEN_VERDICT
# itself, and it extracts only the step's `run:` BODY — never its `env:` block. So T17
# covers the branching inside the body and is BLIND to the mapping that feeds it. Measured:
# hardcoding `TOKEN_VERDICT: unmeasured` in the workflow's env: leaves T17 fully green.
# That mapping is pinned structurally in T18 instead. Two instruments, because no single
# one here can see both halves.
#
# The LIVE fixture is today's incident: the credential was verified live in-job and the
# origin was crash-looping. Getting a rotation instruction here is the whole defect.
echo "T17: the bridge message branches on the MEASURED verdict, end-to-end through the block"
run_mirror always_ok failure match "" live "20:23:05Z" >/dev/null
_t17_live="$(last_log)"
_t17_ok=1
grep -qF 'MEASURED LIVE' "$_t17_live" || _t17_ok=0
grep -qF '20:23:05Z' "$_t17_live" || _t17_ok=0
# The acute regression: on a verdict of `live`, the message must NOT tell the operator to
# go rotate the credential this same job just proved works.
grep -qF 'MEASURED DEAD' "$_t17_live" && _t17_ok=0

run_mirror always_ok failure match "" stale "20:23:05Z" >/dev/null
_t17_stale="$(last_log)"
grep -qF 'MEASURED DEAD' "$_t17_stale" || _t17_ok=0
# ...and the corrected remedy, not the FALSIFIED "set it on the prd ROOT, branches
# inherit" clause the detector itself retracted.
grep -qF 'do NOT inherit' "$_t17_stale" || _t17_ok=0
grep -qF 'MEASURED LIVE' "$_t17_stale" && _t17_ok=0

run_mirror always_ok failure match "" unverifiable "20:23:05Z" gate-indeterminate >/dev/null
_t17_unver="$(last_log)"
grep -qF 'gate-indeterminate' "$_t17_unver" || _t17_ok=0
grep -qF 'Do NOT rotate' "$_t17_unver" || _t17_ok=0

if [[ "$_t17_ok" == "1" ]]; then
  pass "verdict reaches the message: live/stale/unverifiable each render their own arm, and live never says MEASURED DEAD"
else
  fail "the bridge message did not branch on TOKEN_VERDICT — the run body is not consuming the verdict"
fi

# T18 (#7242) — the WIRING that feeds T17, pinned where T17 cannot look.
#
# T17 proves the run body branches correctly on whatever TOKEN_VERDICT holds. It cannot
# prove the workflow puts the right thing there, because this harness supplies that value
# itself. So the mapping is asserted structurally against the parsed YAML.
#
# Three properties, and the third is the subtle one: the verdict must arrive via an `env:`
# mapping and NOT via a `${{ }}` interpolation inside the run body. An interpolation is
# substituted at workflow-parse time, which both bakes the value into the extracted block
# (making per-arm testing impossible) and is the shape that silently pins every arm to one
# value. Asserting the negative is what keeps a future "simplification" from undoing it.
echo "T18: the verdict is WIRED from token_preflight to both consumers (structural)"
if python3 - "$WF" "$REPO_ROOT/.github/actions/cf-tunnel-registry-bridge/action.yml" <<'PY'
import sys, yaml, re
wf = yaml.safe_load(open(sys.argv[1]))
act = yaml.safe_load(open(sys.argv[2]))
errs = []

steps = [s for j in wf["jobs"].values() for s in j.get("steps", [])]
def by_id(i):
    m = [s for s in steps if s.get("id") == i]
    return m[0] if m else None

mirror, bridge = by_id("zot_mirror"), by_id("zot_bridge")
if not mirror: errs.append("no step with id 'zot_mirror'")
if not bridge: errs.append("no step with id 'zot_bridge'")

# 1. The mirror step's env: must source the verdict from the preflight's output.
if mirror:
    v = str(mirror.get("env", {}).get("TOKEN_VERDICT", ""))
    if "steps.token_preflight.outputs.verdict" not in v:
        errs.append(f"zot_mirror env.TOKEN_VERDICT does not read the preflight output: {v!r}")
    # The `|| 'unmeasured'` guard: a composite default does NOT apply to an explicitly
    # empty string, and a skipped preflight yields exactly that.
    if "unmeasured" not in v:
        errs.append(f"zot_mirror env.TOKEN_VERDICT lacks the || 'unmeasured' fallback: {v!r}")

# 2. The bridge step must forward the same value into the composite action.
if bridge:
    w = str(bridge.get("with", {}).get("token-verdict", ""))
    if "steps.token_preflight.outputs.verdict" not in w:
        errs.append(f"zot_bridge with.token-verdict does not read the preflight output: {w!r}")
    if "unmeasured" not in w:
        errs.append(f"zot_bridge with.token-verdict lacks the || 'unmeasured' fallback: {w!r}")

# 3. NEGATIVE: no run: body may interpolate the preflight output directly.
for s in steps:
    body = s.get("run") or ""
    if re.search(r"\$\{\{[^}]*token_preflight[^}]*\}\}", body):
        errs.append(f"step {s.get('id') or s.get('name')!r} interpolates token_preflight inside a run: body — must be an env: mapping")

# 4. The composite action must declare the input and map it into env: at both sites.
if "token-verdict" not in act.get("inputs", {}):
    errs.append("cf-tunnel-registry-bridge declares no token-verdict input")
mapped = [s for s in act["runs"]["steps"]
          if "${{ inputs.token-verdict }}" in str(s.get("env", {}).get("TOKEN_VERDICT", ""))]
if len(mapped) < 2:
    errs.append(f"cf-tunnel-registry-bridge maps token-verdict into env: on only {len(mapped)} step(s); both ::error:: sites need it")

for e in errs: print("   " + e)
sys.exit(1 if errs else 0)
PY
then
  pass "token_preflight verdict is wired to the mirror step and the composite action via env:/with:, with the || 'unmeasured' guard, and never interpolated into a run body"
else
  fail "the verdict wiring is broken — see the lines above (T17 cannot catch this: it injects TOKEN_VERDICT itself)"
fi

# T11-T14 close arms the earlier battery never mutated: it mutated the branch the PR
# WROTE, so crane_install, the cosign-sign arm, copy_latest and mirror_verified all had
# zero fixtures and were individually deletable with the suite fully green.
echo "T11: the crane-install arm fires with its own reason"
assert_eq "crane_install" "$(run_mirror install_fail)" "1 degraded loud 0 crane_install"

echo "T12: the cosign-sign arm fires, and it is the ONE stage allowed to name Sigstore"
_t12_out="$(run_mirror sign_fail)"
_t12_log="$(last_log)"
assert_eq "sign reason" "$(echo "$_t12_out" | cut -d' ' -f1,2,5)" "1 degraded sign"
if grep -qiF 'sigstore' "$_t12_log"; then
  pass "sign-arm message names Sigstore as a plausible cause (the positive T8's negative needs)"
else
  fail "the sign arm is the one stage where a third-party outage is plausible — its message should say so"
fi

echo "T13: the third copy arm carries its own label (not copy_v)"
assert_eq "copy_latest" "$(run_mirror fail_latest_tag)" "1 degraded loud 5 copy_latest"

echo "T14: mirror_verified is emitted true ONLY on the verified path"
_t14_ok=1
run_mirror always_ok >/dev/null; grep -qF 'mirror_verified=true' "$(last_out)" || _t14_ok=0
run_mirror always_ok success mismatch >/dev/null; grep -qF 'mirror_verified=true' "$(last_out)" && _t14_ok=0
run_mirror always_fail success match 'override for a flaky bridge' >/dev/null
grep -qF 'mirror_verified=true' "$(last_out)" && _t14_ok=0
if [[ "$_t14_ok" == "1" ]]; then
  pass "mirror_verified=true on the clean path only — absent on mismatch and on override"
else
  fail "mirror_verified must be emitted true exactly on the verified path (FR-A9/AC8 was untested)"
fi

echo "T15: a whitespace-only override reason does NOT activate the override"
assert_eq "blank override blocked" "$(run_mirror always_fail success match '   ')" "1 degraded loud 3 copy_v"

echo "T16: a digest MISMATCH is not overridable, whatever reason is supplied"
assert_eq "mismatch not overridable" "$(run_mirror always_ok success mismatch 'shipping past a flaky mirror')" "1 degraded loud 3 verify"

# T10 — the dispatch-only override. INERT without a reason (T1 already proves the same
# failure blocks when MIRROR_OVERRIDE_REASON is empty), and when a reason IS supplied the
# step publishes anyway while still recording the failure. mirror_status stays `degraded`
# and the reason label survives: an override must not be able to launder a failed mirror
# into a clean one, or the FR-A9 legibility output would report a verified release that
# never was.
echo "T10: override with a reason -> exit 0 but status/reason still record the failure"
assert_eq "override active" "$(run_mirror always_fail success match 'zot host down, shipping the service_role remediation')" "0 degraded loud 3 copy_v"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
# ANTI-VACUITY FLOOR. Measured: replacing every assert_eq/pass/fail CALL with `:` yields
# "0/0 passed, 0 failed" and exit 0, and test-all.sh reads only the exit code — so a suite
# that executed no assertion at all is indistinguishable from one where everything passed.
# The `[[ ! -s "$MIRROR_BLOCK" ]]` guard above protects EXTRACTION, not assertion count.
# A FLOOR, not equality, so adding a case never requires editing this line.
if [[ "$((PASS + FAIL))" -lt 20 ]]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran; expected >= 20. The suite did not execute what it claims to." >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
