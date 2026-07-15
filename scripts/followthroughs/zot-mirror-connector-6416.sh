#!/usr/bin/env bash
# Follow-through verification for #6416 (web-2 private-net attach + tunnel
# connector homogeneity + the un-masked zot mirror signal).
#
# WHAT WAS BROKEN (measured 2026-07-15, 16 most recent completed release runs that
# built an image):
#   bridge conclusion = success   mirror = skipped   ... 15
#   bridge conclusion = success   mirror = success   ...  1
# The bridge carries `continue-on-error: true`, so its CONCLUSION is forced to
# "success" even when it truly failed. The mirror was gated
# `if: steps.zot_bridge.outcome == 'success'`, so it SKIPPED — and a skipped step
# emits nothing, leaving `mirror_status` unset and the Slack line inert. The actual
# bridge failure, from the job log:
#   Error response from daemon: Get "http://127.0.0.1:5000/v2/": context deadline
#   exceeded (Client.Timeout exceeded while awaiting headers)
# i.e. cloudflared's local forward opened, but the CF tunnel connector that answered
# had no route to zot at 10.0.1.30:5000. zot has therefore been backfilled at most once
# across that window — every other release fell silently through to GHCR.
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
# connector replicas, so a fix could look green by luck. The observed pre-fix rate is
# ~94% failure (15 of 16) — heavily skewed toward the unattached replica, but NOT
# pinned: one run did succeed, which is why a single green mirror proves nothing and
# N=5 consecutive is the gate. (An earlier draft of this header said "14/14" and
# inferred pinning; a later run falsified it. A rate quoted from a snapshot is a claim
# with a timestamp.) Runs where docker_build did not succeed are NOT data points — no
# image was built, so there was nothing to mirror; counting them green would
# manufacture a PASS out of inactivity.
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
  # `[...][0]` pins each extraction to exactly one value.
  #
  # `// "absent"` is a DISTINCT sentinel from any real conclusion, and is handled
  # explicitly below — never allowed to fall through. An earlier draft let "absent"
  # reach the `!= "skipped"` test, so a RENAMED OR DELETED mirror step counted as a
  # clean run: 5 of those would have PASSed and auto-closed #6416 while zot was not
  # being mirrored at all. That is #6416's own defect class (absence read as health)
  # reproduced inside the probe built to prove #6416 fixed. Caught at review.
  steps=$(gh api "repos/${GH_REPO}/actions/jobs/${job_id}" --jq '
    [([.steps[] | select(.name | startswith("Build and push Docker image")) | .conclusion][0] // "absent"),
     ([.steps[] | select(.name | startswith("Mirror image GHCR"))           | .conclusion][0] // "absent")] | @tsv' 2>/dev/null)
  if [[ -z "$steps" ]]; then
    skipped_runs=$((skipped_runs + 1))
    continue
  fi
  build=$(cut -f1 <<<"$steps")
  mirror=$(cut -f2 <<<"$steps")

  # Step-drift: the extraction found no step by that name. NEVER a data point — the
  # probe cannot report a verdict about a step it did not locate.
  if [[ "$mirror" == "absent" || "$build" == "absent" ]]; then
    echo "TRANSIENT: run ${run_id} — could not locate the build ('${build}') and/or mirror ('${mirror}') step by name; they were probably renamed. Update this probe's startswith() anchors before trusting any verdict." >&2
    exit 2
  fi

  # No image built ⇒ nothing to mirror ⇒ not a data point.
  if [[ "$build" != "success" ]]; then
    skipped_runs=$((skipped_runs + 1))
    continue
  fi

  # PRIMARY signal — unmaskable, straight from the API.
  if [[ "$mirror" == "skipped" ]]; then
    echo "FAIL: run ${run_id} (${created_at}) built an image but SKIPPED the zot mirror — zot is not being backfilled."
    echo "  Two causes produce this, check in order:"
    echo "   1. A step between docker_build and the mirror FAILED. The mirror's plain \`if:\` carries an"
    echo "      implicit success(), so e.g. a cosign (Fulcio/Rekor) flake short-circuits it. Read the"
    echo "      job's step list first — this is the more common cause and is NOT a code regression."
    echo "   2. The #6416 silent-skip regressed: zot_mirror gated on zot_bridge again. The bridge's"
    echo "      conclusion is forced to 'success' by continue-on-error, so nothing reds, the mirror"
    echo "      never runs, mirror_status stays unset, and the Slack degraded line stays inert."
    echo "      Fix: gate zot_mirror on steps.docker_build.outcome and branch on the bridge INTERNALLY."
    exit 1
  fi

  logs=$(gh api "repos/${GH_REPO}/actions/jobs/${job_id}/logs" 2>/dev/null)
  if [[ -z "$logs" ]]; then
    skipped_runs=$((skipped_runs + 1))   # logs aged out (~90d): not evidence either way
    continue
  fi

  # DEGRADED — anchored on the interpolated runtime value, never the bare phrase
  # (which also appears in echoed step SOURCE and would false-FAIL). The `<image>`
  # alternate covers degraded() firing before ZOT is assigned: its emitter reads
  # `${ZOT:-<image>}`, so a future call site above that assignment would emit the
  # literal `<image>` and slip an IP-only anchor — counting a degraded run as clean.
  #
  # BOTH `::warning::` and `##[warning]` are accepted, and that is load-bearing:
  # GitHub RENDERS a `::warning::` workflow command as `##[warning]` in the job log.
  # The emitter's SOURCE echo carries the literal `::warning::`; the REAL emit carries
  # `##[warning]`. An anchor matching only `::warning::` therefore matches the source
  # and MISSES every real degraded run — verified against release run 29411418298,
  # whose genuine emit reads:
  #   ##[warning]zot mirror degraded for 127.0.0.1:5000/... (rc=bridge) — release UNAFFECTED
  if grep -qE '(::warning::|##\[warning\])zot mirror degraded for (127\.0\.0\.1:5000/[^ ]*|<image>) \(rc=' <<<"$logs"; then
    echo "FAIL: run ${run_id} (${created_at}) reports a DEGRADED zot mirror."
    grep -oE '(::warning::|##\[warning\])zot mirror degraded for [^ ]+ \(rc=[^)]*\)' <<<"$logs" | head -2 | sed 's/^/  /'
    echo "  If rc=bridge: the CF tunnel connector serving registry.soleur.ai could not route to"
    echo "  10.0.1.30:5000. Verify EVERY web host is a 10.0.1.0/24 member (ADR-114 I1):"
    echo "    hcloud server describe soleur-web-2 -o json | jq .private_net    # must NOT be []"
    exit 1
  fi

  # POSITIVE LIVENESS — the run must prove the mirror actually COMPLETED, not merely
  # that no failure was found. Without this, any change that stops the mirror from
  # emitting at all (step renamed, run block restructured, log-read silently broken)
  # reads as "no degraded found" → clean → PASS → the sweeper auto-resolves #6416 on
  # the ABSENCE of a signal. That is #6416's own defect class; a probe built to prove
  # the fix must not reproduce it.
  #
  # `copied v[0-9][^ ]*,` — the INTERPOLATED version is load-bearing, not decoration.
  # The release job log contains the PR/commit MESSAGE (via the release-notes body),
  # and #6421's own commit prose quotes this very anchor:
  #   marker ("zot mirror ok: copied ... to 127.0.0.1:5000/")
  # A `copied .* to 127.0.0.1:5000/` anchor MATCHES that sentence. Combined with the
  # `::warning::`-only degraded anchor above, the two composed into a FALSE PASS on a
  # genuinely degraded run (verified against 29411418298: degraded missed, liveness
  # satisfied by the echoed commit message → counted clean). Requiring `v<version>,`
  # cannot be satisfied by prose — only `echo "zot mirror ok: copied v${VERSION}, ..."`
  # produces it.
  if ! grep -qE 'zot mirror ok: copied v[0-9][^ ]*, .* to 127\.0\.0\.1:5000/' <<<"$logs"; then
    echo "TRANSIENT: run ${run_id} ran the mirror (conclusion=${mirror}) but emitted neither a degraded warning nor the success marker." >&2
    echo "  The probe cannot certify a run whose producer left no trace — refusing to count it clean." >&2
    exit 2
  fi

  ok=$((ok + 1))
done <<<"$RUNS"

if [[ "$ok" -ge "$NEED" ]]; then
  echo "PASS: ${ok}/${NEED} consecutive releases ran the zot mirror with no degraded signal."
  echo "  Baseline for contrast: 15 of the 16 releases before the fix skipped the mirror entirely."
  exit 0
fi

echo "TRANSIENT: only ${ok} clean mirror(s) so far (need ${NEED}); ${skipped_runs} run(s) carried no mirror data (no image built / logs aged out). Waiting for more releases." >&2
exit 2
