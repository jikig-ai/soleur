#!/usr/bin/env bash
# Follow-through verification for #6416 (web-2 private-net attach + tunnel
# connector homogeneity + the un-masked zot mirror signal).
#
# WHAT WAS BROKEN (measured 2026-07-15, last 14 completed release runs):
#   bridge conclusion = success   mirror = skipped     ... 14/14
# The bridge carries `continue-on-error: true`, so its CONCLUSION is forced to
# "success" even when it truly failed. The mirror was gated
# `if: steps.zot_bridge.outcome == 'success'`, so it SKIPPED — and a skipped step
# emits nothing, leaving `mirror_status` unset and the Slack line inert. The actual
# bridge failure, from the job log:
#   Error response from daemon: Get "http://127.0.0.1:5000/v2/": context deadline
#   exceeded (Client.Timeout exceeded while awaiting headers)
# i.e. cloudflared's local forward opened, but the CF tunnel connector that answered
# had no route to zot at 10.0.1.30:5000. zot has therefore NEVER been backfilled.
#
# THE TWO SIGNALS THIS PROBE READS, and why:
#
#   1. `Mirror image GHCR→zot` conclusion != "skipped"  (PRIMARY, unmaskable)
#      Read from the jobs API, not the log. This is the #6416 regression itself:
#      post-fix the step is gated on docker_build (not on zot_bridge) and branches
#      internally, so it must ALWAYS run when an image was built. A "skipped" here
#      means the old bridge-gate is back and the mirror is silent again.
#      NOTE: the bridge's own step conclusion is deliberately NOT read — it is a LIE
#      by construction (continue-on-error). That masking is what hid this for weeks.
#
#   2. No degraded emit in the log  (SECONDARY)
#      Anchored on the INTERPOLATED runtime value (`for 127.0.0.1:5000/`), never on
#      the bare phrase: GitHub echoes each run-block's SOURCE into the job log, so a
#      plain `grep 'zot mirror degraded'` matches the emitter's own source text AND
#      the Slack step's message template — it reports FAIL on a perfectly healthy
#      run. (Verified: that false positive is exactly what a naive grep produced
#      here.) The source shows `for ${ZOT:-<image>}`; only a real emit shows the
#      resolved `127.0.0.1:5000/...`.
#
# WHY N=5. #6416's mechanism is statistical: the ONE tunnel load-balances across
# connector replicas, so a fix could look green by luck. Observed reality is worse
# than the ~50% that model predicts (14/14 failed), which makes any green mirror
# already strong evidence — but N=5 consecutive stays the conservative gate. Runs
# where docker_build did not succeed are NOT data points (no image was built, so
# there was nothing to mirror); counting them green would manufacture a PASS out of
# inactivity.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (>=5 consecutive clean mirrors; sweeper closes #6416)
#   1 = FAIL       (a skipped or degraded mirror in the window)
#   * = TRANSIENT  (API unreachable, or fewer than 5 data points yet; retry next sweep)
#
# Required env: GH_TOKEN + GH_REPO. Both already exist in
#   scheduled-followthrough-sweeper.yml's env: block, so NO new secret wiring is
#   needed — but they MUST be named in the directive's `secrets=` clause:
#   sweep-followthroughs.sh runs every script under `env -i` with an allowlist, so
#   anything undeclared simply is not present.

set -uo pipefail

# Fail-safe env check. Deliberately NOT `: "${VAR:?msg}"` — under a non-interactive
# shell that word-expansion aborts with status 1, which this contract reads as FAIL
# ("criteria not met") when the truth is "the probe could not run". An unprovisioned
# env must never be able to report a verdict. See followthrough-convention.md.
for v in GH_TOKEN GH_REPO; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is unset or empty — cannot query release history (declare it in the directive's secrets= clause)" >&2
    exit 2
  fi
done

WORKFLOW="web-platform-release.yml"   # the only reusable-release caller passing docker_image
JOB_NAME="release / release"
NEED=5
SCAN=25

RUNS=$(gh api "repos/${GH_REPO}/actions/workflows/${WORKFLOW}/runs?branch=main&per_page=${SCAN}" \
  --jq '.workflow_runs[] | select(.status == "completed") | "\(.id) \(.created_at)"' 2>/dev/null)

if [[ -z "$RUNS" ]]; then
  echo "TRANSIENT: could not list ${WORKFLOW} runs (GitHub API unreachable, or no completed runs)" >&2
  exit 2
fi

ok=0
skipped_runs=0

while read -r run_id created_at; do
  [[ -n "${run_id:-}" ]] || continue
  [[ "$ok" -lt "$NEED" ]] || break

  # NOTE: `gh api --jq` takes a filter only — it does NOT accept jq's `--arg`, so the
  # job name is interpolated into the filter rather than bound. (An `--arg` here
  # silently yields nothing, which this probe's fail-safe would report as TRANSIENT
  # forever — a probe that can never PASS is as useless as one that always does.)
  job_id=$(gh api "repos/${GH_REPO}/actions/runs/${run_id}/jobs" \
    --jq ".jobs[] | select(.name == \"${JOB_NAME}\") | .id" 2>/dev/null | head -1)
  if [[ -z "${job_id:-}" ]]; then
    skipped_runs=$((skipped_runs + 1))
    continue
  fi

  # `startswith`, NOT `test()`: the job also contains an auto-generated "Post Build
  # and push Docker image" teardown step, and an unanchored `test("Build and push
  # Docker image")` matches BOTH — emitting a third field, shifting `mirror` onto the
  # post-step's "success", and reporting a false PASS against a run whose mirror was
  # actually skipped. (Observed: that is exactly what the unanchored form did here.)
  # `[...][0]` pins each extraction to exactly one value so the TSV is always 2 fields.
  steps=$(gh api "repos/${GH_REPO}/actions/jobs/${job_id}" --jq '
    [([.steps[] | select(.name | startswith("Build and push Docker image")) | .conclusion][0] // "absent"),
     ([.steps[] | select(.name | startswith("Mirror image GHCR"))           | .conclusion][0] // "absent")] | @tsv' 2>/dev/null)
  if [[ -z "$steps" ]]; then
    skipped_runs=$((skipped_runs + 1))
    continue
  fi
  # Shape guard: anything other than exactly 2 fields means the extraction drifted
  # (a renamed step, a new matching step). Fail TRANSIENT rather than silently read
  # the wrong column — the false-PASS mode this probe exists to avoid.
  if [[ "$(awk -F'\t' '{print NF}' <<<"$steps")" != "2" ]]; then
    echo "TRANSIENT: step extraction returned $(awk -F'\t' '{print NF}' <<<"$steps") fields, expected 2 (step names drifted?): $steps" >&2
    exit 2
  fi
  build=$(cut -f1 <<<"$steps")
  mirror=$(cut -f2 <<<"$steps")

  # No image built ⇒ nothing to mirror ⇒ not a data point.
  if [[ "$build" != "success" ]]; then
    skipped_runs=$((skipped_runs + 1))
    continue
  fi

  # PRIMARY signal — unmaskable, straight from the API.
  if [[ "$mirror" == "skipped" ]]; then
    echo "FAIL: run ${run_id} (${created_at}) built an image but SKIPPED the zot mirror."
    echo "  A skip means the mirror is gated on zot_bridge again — the #6416 silent-skip is back:"
    echo "  the bridge's conclusion is forced to 'success' by continue-on-error, so nothing reds,"
    echo "  the mirror never runs, mirror_status stays unset, and the Slack degraded line stays inert."
    echo "  zot is not being backfilled. Check reusable-release.yml: zot_mirror must be gated on"
    echo "  steps.docker_build.outcome, and branch on steps.zot_bridge.outcome INTERNALLY."
    exit 1
  fi

  # SECONDARY signal — anchored on the interpolated runtime value, never the bare
  # phrase (which also appears in echoed step SOURCE and would false-FAIL).
  logs=$(gh api "repos/${GH_REPO}/actions/jobs/${job_id}/logs" 2>/dev/null)
  if [[ -z "$logs" ]]; then
    skipped_runs=$((skipped_runs + 1))   # logs aged out (~90d): not evidence either way
    continue
  fi
  if grep -qE '::warning::zot mirror degraded for 127\.0\.0\.1:5000/' <<<"$logs"; then
    echo "FAIL: run ${run_id} (${created_at}) reports a DEGRADED zot mirror."
    grep -oE '::warning::zot mirror degraded for 127\.0\.0\.1:5000/[^"]{0,120}' <<<"$logs" | head -2 | sed 's/^/  /'
    echo "  If rc=bridge: the CF tunnel connector serving registry.soleur.ai could not route to"
    echo "  10.0.1.30:5000. Verify EVERY web host is a 10.0.1.0/24 member (ADR-113 I1):"
    echo "    hcloud server describe soleur-web-2 -o json | jq .private_net    # must NOT be []"
    exit 1
  fi

  ok=$((ok + 1))
done <<<"$RUNS"

if [[ "$ok" -ge "$NEED" ]]; then
  echo "PASS: ${ok}/${NEED} consecutive releases ran the zot mirror with no degraded signal."
  echo "  Baseline for contrast: 14/14 releases before the fix skipped the mirror entirely."
  exit 0
fi

echo "TRANSIENT: only ${ok} clean mirror(s) so far (need ${NEED}); ${skipped_runs} run(s) carried no mirror data (no image built / logs aged out). Waiting for more releases." >&2
exit 2
