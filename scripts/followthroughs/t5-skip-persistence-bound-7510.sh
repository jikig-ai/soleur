#!/usr/bin/env bash
# Follow-through verification for the T5 counted-skip persistence bound (PR #7510, issue #7291).
#
# ADR-188 accepts, explicitly, that nothing bounds the T5 mutation arm's skip ACROSS runs. The
# four mechanical conditions bound it per-run; an arm that skips on every run forever satisfies
# all four and reports green, and the only carrier is `Skipped: N` plus a NOTE on the stdout of
# a check that exits 0. This probe is that missing observer.
#
# It reads the ONE signal that already exists — the suite's own loud SKIP line in post-merge
# `infra-validation.yml` logs — so it needs no new instrumentation to be useful today.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (no skip observed in the sampled window; the residual has not materialised)
#   1 = FAIL       (>= 1 skip observed; the deferred pre-bake / S1 extension is now owed)
#   * = TRANSIENT  (gh unreachable, auth failure, no runs to sample)
#
# Required env: GH_TOKEN  (declared via the directive's secrets= clause; the sweeper runs under
#                          `env -i` and strips everything not declared)
#
# Close criteria:
#   - Sample the most recent successful post-merge runs of infra-validation.yml on main
#   - Grep their logs for EVERY marker in SKIP_MARKERS (T5 and S1 today, enumerated
#     below) -- not the single `SKIP (loud): T5 MUTATION` literal this once used,
#     which made the probe blind to the S1 arm #7572 makes skip-eligible
#   - 0 occurrences  => PASS (the skip is not persistent)
#   - >=1 occurrence => FAIL (the deferred pre-bake / S1 extension is owed)
#
# CARRIER (#7574). This probe is NOT enrolled as a `<!-- soleur:followthrough -->`
# directive. The sweeper closes a follow-through on its first PASS and
# `closed_precheck` then refuses to re-litigate, so a probe whose whole purpose
# is to watch a window ACROSS runs would retire itself after one clean sample --
# which is the same shape of un-run instrument reporting a clean bill of health
# that the positive control below exists to prevent. The carrier is instead the
# standing daily monitor `.github/workflows/scheduled-rehearsal-skip-monitor.yml`,
# which does not close on PASS.

set -uo pipefail

# N-CONSECUTIVE-TRANSIENT ESCALATION (#7574). A permanently broken gh auth and a
# healthy quiet window both exit 2 forever, and 2 is the code the carrier treats
# as "nothing to see". So a probe that can never reach a verdict is
# indistinguishable from one that keeps reaching a clean one -- the failure mode
# this whole file exists to close, one level up.
#
# The counter lives in a file the CARRIER is responsible for persisting across
# runs (the workflow restores/saves it). If it is not persisted the counter
# resets every run and escalation simply never fires: that DEGRADES OPEN, so it
# is stated here rather than assumed, and the workflow asserts the round-trip.
T5_PROBE_STATE="${T5_PROBE_STATE:-${TMPDIR:-/tmp}/t5-skip-probe-transient-streak}"
T5_TRANSIENT_ESCALATE_AFTER="${T5_TRANSIENT_ESCALATE_AFTER:-3}"

_transient() {  # $1 = human reason
  local streak=0
  [[ -r "$T5_PROBE_STATE" ]] && streak=$(tr -cd '0-9' < "$T5_PROBE_STATE" 2>/dev/null || echo 0)
  [[ -n "$streak" ]] || streak=0
  streak=$((streak + 1))
  printf '%s' "$streak" > "$T5_PROBE_STATE" 2>/dev/null || true
  echo "TRANSIENT: $1 (consecutive transient runs: ${streak}/${T5_TRANSIENT_ESCALATE_AFTER})" >&2
  if [[ "$streak" -ge "$T5_TRANSIENT_ESCALATE_AFTER" ]]; then
    echo "FAIL: the probe has been unable to reach a verdict for ${streak} consecutive runs." >&2
    echo "      This is no longer a transient condition. A probe that cannot measure is not" >&2
    echo "      evidence that there is nothing to measure -- treat this as a broken instrument," >&2
    echo "      not as a quiet window." >&2
    exit 1
  fi
  exit 2
}

_clear_transient_streak() { rm -f "$T5_PROBE_STATE" 2>/dev/null || true; }

if [[ -z "${GH_TOKEN:-}" ]]; then _transient "GH_TOKEN not set"; fi

REPO="jikig-ai/soleur"
WF="infra-validation.yml"
SAMPLE=20   # ADR-188's declared window: "more than 1 in 20 post-merge runs"

runs=$(gh run list --repo "$REPO" --workflow "$WF" --branch main \
         --limit "$SAMPLE" --json databaseId,conclusion 2>/dev/null) || {
  _transient "gh run list failed"; }

ids=$(printf '%s' "$runs" | jq -r '.[] | select(.conclusion == "success") | .databaseId' 2>/dev/null) || {
  _transient "could not parse run list"; }

# An empty sample is NOT a clean bill of health — it is an un-run instrument. Absence of evidence
# here is indistinguishable from evidence of absence, which is the exact trap this file's own
# subject matter is about.
[[ -n "$ids" ]] || _transient "no successful post-merge runs to sample"

# THE POSITIVE CONTROL, added at review. Counting occurrences of a marker and reporting PASS on
# zero cannot distinguish "the arm did not skip" from "this probe can no longer see the arm at
# all". Both the prefix `SKIP (loud): ` (emitted by arm_skip in the suite) and the discriminator
# `T5 MUTATION` (the call site's message) are hand-copied here as fixed strings, so a reword on
# either side silently zeroes the count — and a zero reads as the reassuring answer, forever, from
# an instrument that is measuring nothing. That is precisely the unpinned-replicated-literal
# failure the suite spends a hundred lines closing for its own execution marker, and it would land
# in the one artifact that exists to bound ADR-188's accepted residual.
#
# So a run only counts as OBSERVED when its log carries the suite's own terminal summary line.
# If no sampled run does, the sample is unreadable and the verdict is TRANSIENT, never PASS.
SUITE_TERMINAL='git-data-runcmd-rehearsal:'

# AN ENUMERATED SET, NOT ONE LITERAL. This was 'SKIP (loud): T5 MUTATION', which
# made the probe structurally blind to every other skip-eligible arm — including
# S1, which #7572 makes skip-eligible precisely because it has the same
# unbounded-across-runs residual T5 has. A probe that goes quiet on the arm the
# fix creates is worse than no probe.
#
# The discriminator is the ARM NAME, not the 'SKIP (loud): ' prefix. Widening to
# the bare prefix would count infra-config-apply.test.sh's
# 'SKIP (loud): not root…' and alarm forever on a healthy repo.
SKIP_MARKERS=(
  'SKIP (loud): T5 '
  'SKIP (loud): S1 '
)

sampled=0
observed=0
hits=0
declare -A per_arm=()
for _m in "${SKIP_MARKERS[@]}"; do per_arm["$_m"]=0; done

while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  log=$(gh run view "$id" --repo "$REPO" --log 2>/dev/null) || continue
  sampled=$((sampled + 1))
  # HERE-STRING, NOT A PIPE. This was
  #   printf '%s' "$log" | grep -qF "$SUITE_TERMINAL" || continue
  # and under `set -o pipefail` it lost the match it was testing for: grep -q
  # exits on its FIRST hit and closes the pipe, printf takes SIGPIPE (141),
  # pipefail promotes that to the pipeline's status, and `|| continue` fires
  # BECAUSE the match succeeded. Measured 2026-08-19: twenty logs that all
  # contained this line, observed=0, exit 2. A here-string has no pipe and no
  # second process, so there is nothing to break.
  grep -qF "$SUITE_TERMINAL" <<<"$log" || continue
  observed=$((observed + 1))
  for _m in "${SKIP_MARKERS[@]}"; do
    # `grep -c` reads to EOF and never breaks the pipe, so this line was not
    # affected. Converted anyway so the file has ONE form and the next reader
    # does not have to re-derive which shapes are safe.
    n=$(grep -cF "$_m" <<<"$log" || true)
    per_arm["$_m"]=$(( ${per_arm["$_m"]} + n ))
    hits=$((hits + n))
  done
done <<< "$ids"

[[ "$sampled" -ge 1 ]] || _transient "no run logs could be fetched"
[[ "$observed" -ge 1 ]] || _transient "fetched ${sampled} run log(s), none containing '${SUITE_TERMINAL}' — the suite did not run in this window, or its output moved. A zero skip-count here would be an un-run instrument reporting a clean bill of health."

_clear_transient_streak

if [[ "$hits" -eq 0 ]]; then
  echo "PASS: 0 loud rehearsal skips (arms: ${SKIP_MARKERS[*]}) across ${observed} observed post-merge run(s) (${sampled} sampled) — the persistence residual has not materialised."
  exit 0
fi

# DENOMINATOR: `observed`, not `sampled`. PASS reported over observed and FAIL
# over sampled, so the two verdicts described different populations and the FAIL
# understated the rate whenever a fetched log did not carry the terminal line.
echo "FAIL: ${hits} loud rehearsal skip(s) across ${observed} observed post-merge run(s) (${sampled} sampled)." >&2
for _m in "${SKIP_MARKERS[@]}"; do
  echo "        ${_m}=${per_arm["$_m"]}" >&2
done
echo "      ADR-188's declared observation window has fired: the skip is masking a persistent" >&2
echo "      condition rather than a transient one. The deferred pre-baked image (#7535) is owed," >&2
echo "      and the S1 extension (#7572) becomes the same class of problem." >&2
exit 1
