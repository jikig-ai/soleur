#!/usr/bin/env bash
# Verifies the non-blocking + bounded-retry + degraded-signal behavior of the
# "Mirror image GHCR→zot" step in .github/workflows/reusable-release.yml (#6274).
#
# Background: the zot mirror is a SECONDARY/shadow registry copy during the
# ADR-096 soak (GHCR stays primary + break-glass; the pull side does an atomic
# GHCR fallback on any zot miss). A single `connection reset by peer` mid
# blob-upload over the multi-hop CF-tunnel bridge was failing the whole
# `release / release` job even though the deploy already succeeded. The fix
# makes the mirror step non-release-blocking: `continue-on-error: true` (belt) +
# an inner `set -uo pipefail` shell whose every failure path exits 0
# (suspenders), wraps the network ops in a bounded `retry` (self-heal transient
# resets), and emits a `mirror_status` output + `::warning::` + step summary +
# Slack line so a persistent miss is loud, never silently swallowed.
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
for c in curl sha256sum sudo tar sleep cosign; do
  cat > "$STUB_DIR/$c" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_DIR/$c"
done
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

# The step summary and log of the LAST run_mirror call, for message-content assertions.
last_log() { ls -t "$TMP"/log.* 2>/dev/null | head -1; }

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
echo "T9: the failure message states the release is an unpublished draft + names the hatch"
run_mirror always_ok failure >/dev/null
_t9_log="$(last_log)"
_t9_ok=1
grep -qF 'UNPUBLISHED DRAFT' "$_t9_log" || _t9_ok=0
grep -qF 'apply-deploy-pipeline-fix.yml' "$_t9_log" || _t9_ok=0
grep -qF 'check-cloudflare-token-drift.sh' "$_t9_log" || _t9_ok=0
if [[ "$_t9_ok" == "1" ]]; then
  pass "bridge message: unpublished-draft reassurance + bypass hatch + the drift detector to run"
else
  fail "bridge message must state the release is an unpublished draft, name apply-deploy-pipeline-fix.yml, and name check-cloudflare-token-drift.sh"
fi

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
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
