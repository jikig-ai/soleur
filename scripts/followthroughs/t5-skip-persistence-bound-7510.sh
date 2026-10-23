#!/usr/bin/env bash
# Follow-through verification for the T5 counted-skip persistence bound (PR #7510, issue #7291).
#
# ADR-188 accepts, explicitly, that nothing bounds the T5 mutation arm's skip ACROSS runs. The
# four mechanical conditions bound it per-run; an arm that skips on every run forever satisfies
# all four and reports green, and the only carrier is `Skipped: N` plus a NOTE on the stdout of
# a check that exits 0. This probe is that missing observer.
#
# It reads the ONE signal that already exists — the suite's own loud SKIP line in post-merge
# `infra-validation.yml` logs. The CARRIER of that line is the runner
# apps/web-platform/infra/run-registered-suites.sh: it captures each suite's output into a per-suite
# file, so the suite's own text never reaches the Actions log; the runner RELAYS the column-0
# `SKIP (loud): ` lines and the rehearsal suite's terminal line as `SOLEUR| relay <basename>: <line>`
# (#10786). Between #8763 (2026-09-25) and that relay the marker below was invisible and this probe
# was TRANSIENT from 2026-09-28 on; run-registered-suites.test.sh (T13) and this probe's own suite
# (section (k), which feeds the real runner's stdout to this file) keep the chain from drifting again.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (no skip observed in the sampled window; the residual has not materialised)
#   1 = FAIL       (>= 1 skip observed; the deferred pre-bake / S1 extension is now owed)
#   2 = TRANSIENT  (gh unreachable, auth failure, no runs to sample)
#  78 = REFUSED    (running under `set -x` with a live GH_TOKEN -- see the guard below, #7797)
#
# 78 IS A FOURTH ROW, ADDED AT REVIEW (#7535 Phase 2). It is deliberately NOT folded into
# TRANSIENT: a refusal is a decision this script made about its own safety, not a failure to
# reach a verdict, and it is fully determined by how the caller invoked it. Amending this block
# rather than leaving it is the point -- the paragraph below says any code outside the list means
# the script did not run to a verdict, and an unamended list would have made that claim false for
# the one exit that is most obviously deliberate.
#
# Beyond those four there is no `*` row. Any OTHER code means the script did not run to a verdict
# (127 missing, 126 not executable, 2-from-bash on a syntax error). The standing monitor treats that as its own RED rather
# than folding it into TRANSIENT -- see scheduled-rehearsal-skip-monitor.yml. Note that
# sweep-followthroughs.sh maps any other exit to TRANSIENT by ITS documented contract; that
# is safe there because leaving an issue open is conservative, whereas in the monitor
# TRANSIENT means green.
#
# Required env: GH_TOKEN  (declared via the directive's secrets= clause; the sweeper runs under
#                          `env -i` and strips everything not declared)
#
# Close criteria:
#   - Sample the most recent successful post-merge runs of infra-validation.yml on main
#   - Grep their logs for EVERY marker in SKIP_MARKERS (T5, S1 and T17 today,
#     enumerated below) -- not the single `SKIP (loud): T5 MUTATION` literal this
#     once used, which made the probe blind to the S1 arm #7572 makes skip-eligible
#     and would equally have missed the T17 arm #7535 Phase 2 makes skip-eligible
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

# XTRACE CREDENTIAL REFUSAL (#7797). This probe binds GH_TOKEN, and `set -x` expands every
# command -- including the `gh` invocations carrying that token -- into a log that lands in a
# public Actions run. Refuse to run traced rather than emit it.
#
# PRE-EXISTING GAP, surfaced rather than introduced (#7535 Phase 2). The repo gate
# `lint-shell-trace-credential-refusal.py` runs in `--changed` mode, so it only scans files a
# PR touches; this file has bound a live credential without the guard since it was written, and
# nothing had touched it since the gate landed. Adding the T17 marker to SKIP_MARKERS brought it
# into scope, which is the gate working as designed -- the omission is fixed here rather than
# deferred, because the fix is the eight lines the linter itself prints.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# N-CONSECUTIVE-TRANSIENT ESCALATION (#7574). A permanently broken gh auth and a
# healthy quiet window both exit 2 forever, and 2 is the code the carrier treats
# as "nothing to see". So a probe that can never reach a verdict is
# indistinguishable from one that keeps reaching a clean one -- the failure mode
# this whole file exists to close, one level up.
#
# The counter lives in a file the CARRIER is responsible for persisting across
# runs (the workflow fetches it from, and uploads it to, a workflow artifact; ADR-296).
# If it is not persisted the counter resets every run and escalation simply never
# fires: that DEGRADES OPEN, so it is stated here rather than assumed, and the
# workflow asserts the round-trip.
T5_PROBE_STATE="${T5_PROBE_STATE:-${TMPDIR:-/tmp}/t5-skip-probe-transient-streak}"
T5_TRANSIENT_ESCALATE_AFTER="${T5_TRANSIENT_ESCALATE_AFTER:-3}"

_transient() {  # $1 = human reason -- ALWAYS exits, never returns
  local streak=0
  [[ -r "$T5_PROBE_STATE" ]] && streak=$(tr -cd '0-9' < "$T5_PROBE_STATE" 2>/dev/null || echo 0)
  # BASE-10 AND SHAPE-VALIDATED. `$((streak + 1))` reads a LEADING ZERO as octal, so a stored
  # `08`/`09` is an arithmetic EVALUATION ERROR -- and because this file runs without `set -e`,
  # that error made the assignment fail, the function RETURN instead of reaching its exit, and
  # every `... || _transient "..."` caller fall straight through to the PASS path. Measured:
  # with gh entirely broken the probe printed
  #   "PASS: 0 loud rehearsal skips ... across 0 observed post-merge run(s) (0 sampled)"
  # and exited 0 -- a clean bill of health over a sample of zero, which is verbatim the
  # un-run-instrument failure this file exists to prevent. `007` corrupts silently to 8.
  [[ "$streak" =~ ^[0-9]+$ ]] || streak=0
  streak=$((10#$streak + 1))
  printf '%s' "$streak" > "$T5_PROBE_STATE" 2>/dev/null || true
  echo "TRANSIENT: $1 (consecutive transient runs: ${streak}/${T5_TRANSIENT_ESCALATE_AFTER})" >&2
  # The threshold is operator-settable, so it gets the same treatment as the counter.
  [[ "$T5_TRANSIENT_ESCALATE_AFTER" =~ ^[0-9]+$ ]] || T5_TRANSIENT_ESCALATE_AFTER=3
  if [[ "$streak" -ge $((10#$T5_TRANSIENT_ESCALATE_AFTER)) ]]; then
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
SAMPLE=20   # ADR-188's declared window: "more than 1 in 20 post-merge runs"

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
  # T17 (#7535 Phase 2). Added in the SAME change that made the arm skip-eligible, because the
  # suite's own roster guard (_PROBE_NAMED vs _SKIP_CALL_SITES) asserts that every arm_skip call
  # site opens with a name this list greps for. Registering the arm there and not here would
  # satisfy that equality by arithmetic while leaving this probe blind to the new arm — the exact
  # "a probe that goes quiet on the arm the fix creates" failure the note above describes.
  'SKIP (loud): T17 '
)

# SECOND RUN-SOURCE (#10921). The guard-script fixture suites' corrupt-walk rows
# emit `SKIP (loud): g1b.`/`g2b.` (test-bump-inngest-bootstrap-pin.sh) and
# `SKIP (loud): fl.` (test-mint-inngest-bootstrap-tag.sh) inside the
# `guard-script-fixture-tests` job of pr-quality-guards.yml. That workflow has
# NO post-merge leg — its triggers are pull_request + merge_group, and
# merge_group runs land on gh-readonly-queue/* refs — so the rehearsal source's
# `--branch main` / `conclusion==success` sampling cannot be reused: this source
# samples BY EVENT. merge_group legs are REQUIRED evidence (they gate landing
# to main); pull_request legs add density — and they count output from
# UNMERGED branches, so a PR introducing a skip arm trips the monitor pre-merge
# (real evidence, labelled by source).
#
# PER-SUITE discriminators, not per-job: the bump and mint suites' output shares
# one job log, so a single positive control cannot tell "the mint suite didn't
# run" from "no fl. skips". Each marker-emitting suite keys on the
# `=== test-<name>.sh ===` banner run-all.sh prints before it runs that suite.
#
# Format: <unit>|<log discriminator>|<markers, ';'-separated>
GUARD_UNITS=(
  'bump|=== test-bump-inngest-bootstrap-pin.sh ===|SKIP (loud): g1b.;SKIP (loud): g2b.'
  'mint|=== test-mint-inngest-bootstrap-tag.sh ===|SKIP (loud): fl.'
)

# PER-SOURCE accounting, NEVER pooled: each source contributes `observed >= 1`
# independently; a source (or a suite within it) with zero observed logs reads
# TRANSIENT — it never pools into another source's clean reading ("a probe that
# goes quiet on the arm the fix creates is worse than no probe").
any_fail=0
transient_reasons=""

# --- source 1: infra-validation.yml post-merge main runs (rehearsal arms) ----
sampled=0
observed=0
hits=0
declare -A per_arm=()
for _m in "${SKIP_MARKERS[@]}"; do per_arm["$_m"]=0; done

if ! runs=$(gh run list --repo "$REPO" --workflow infra-validation.yml --branch main \
         --limit "$SAMPLE" --json databaseId,conclusion 2>/dev/null); then
  echo "TRANSIENT: infra-validation.yml — gh run list failed" >&2
  transient_reasons="infra-validation gh run list failed"
else
  ids=$(printf '%s' "$runs" | jq -r '.[] | select(.conclusion == "success") | .databaseId' 2>/dev/null)
  # An empty sample is NOT a clean bill of health — it is an un-run instrument.
  if [[ -z "$ids" ]]; then
    echo "TRANSIENT: infra-validation.yml — no successful post-merge runs to sample" >&2
    transient_reasons="no successful infra-validation runs"
  else
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
    if [[ "$sampled" -lt 1 ]]; then
      echo "TRANSIENT: infra-validation.yml — no run logs could be fetched" >&2
      transient_reasons="no infra-validation run logs fetched"
    elif [[ "$observed" -lt 1 ]]; then
      echo "TRANSIENT: infra-validation.yml — fetched ${sampled} run log(s), none containing '${SUITE_TERMINAL}' — the suite did not run in this window, or its output moved. A zero skip-count here would be an un-run instrument reporting a clean bill of health." >&2
      transient_reasons="rehearsal suite unobserved in sampled logs"
    elif [[ "$hits" -eq 0 ]]; then
      echo "PASS: infra-validation.yml — 0 loud rehearsal skips (arms: ${SKIP_MARKERS[*]}) across ${observed} observed post-merge run(s) (${sampled} sampled)"
    else
      # DENOMINATOR: `observed`, not `sampled` — the two verdicts describe
      # different populations and reporting FAIL over sampled understates the rate.
      echo "FAIL: infra-validation.yml — ${hits} loud rehearsal skip(s) across ${observed} observed post-merge run(s) (${sampled} sampled)." >&2
      for _m in "${SKIP_MARKERS[@]}"; do
        echo "        ${_m}=${per_arm["$_m"]}" >&2
      done
      any_fail=1
    fi
  fi
fi

# --- source 2: pr-quality-guards.yml by EVENT (guard-suite corrupt-walk arms) -
declare -A unit_obs=() unit_hits=()
for _u in "${GUARD_UNITS[@]}"; do
  IFS='|' read -r _uname _disc _marks <<< "$_u"
  unit_obs["$_uname"]=0; unit_hits["$_uname"]=0
done

pg_ids=$( {
  gh run list --repo "$REPO" --workflow pr-quality-guards.yml --event merge_group \
    --limit "$SAMPLE" --json databaseId 2>/dev/null | jq -r '.[].databaseId'
  gh run list --repo "$REPO" --workflow pr-quality-guards.yml --event pull_request \
    --limit "$SAMPLE" --json databaseId 2>/dev/null | jq -r '.[].databaseId'
} | awk 'NF && !seen[$0]++' | head -n "$SAMPLE" )

if [[ -z "$pg_ids" ]]; then
  echo "TRANSIENT: pr-quality-guards.yml — no merge_group/pull_request runs to sample" >&2
  transient_reasons="${transient_reasons:+$transient_reasons; }no pr-quality-guards runs"
else
  g_sampled=0
  g_hits=0
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    log=$(gh run view "$id" --repo "$REPO" --log 2>/dev/null) || continue
    g_sampled=$((g_sampled + 1))
    for _u in "${GUARD_UNITS[@]}"; do
      IFS='|' read -r _uname _disc _marks <<< "$_u"
      grep -qF "$_disc" <<<"$log" || continue
      unit_obs["$_uname"]=$(( ${unit_obs["$_uname"]} + 1 ))
      IFS=';' read -ra _marr <<< "$_marks"
      for _m in "${_marr[@]}"; do
        [[ -n "$_m" ]] || continue
        n=$(grep -cF "$_m" <<<"$log" || true)
        unit_hits["$_uname"]=$(( ${unit_hits["$_uname"]} + n ))
        g_hits=$((g_hits + n))
      done
    done
  done <<< "$pg_ids"
  if [[ "$g_sampled" -lt 1 ]]; then
    echo "TRANSIENT: pr-quality-guards.yml — no run logs could be fetched" >&2
    transient_reasons="${transient_reasons:+$transient_reasons; }no pr-quality-guards logs fetched"
  else
    g_all_observed=1
    for _u in "${GUARD_UNITS[@]}"; do
      IFS='|' read -r _uname _disc _marks <<< "$_u"
      if [[ "${unit_obs[$_uname]}" -lt 1 ]]; then
        g_all_observed=0
        echo "TRANSIENT: pr-quality-guards.yml — 0 observed log(s) for suite '${_uname}' (discriminator '${_disc}' absent in all ${g_sampled} sampled log(s)) — the suite did not run or its banner moved; a zero skip-count here would be an un-run instrument reporting a clean bill of health." >&2
        transient_reasons="${transient_reasons:+$transient_reasons; }guard suite ${_uname} unobserved"
      fi
    done
    if [[ "$g_hits" -gt 0 ]]; then
      echo "FAIL: pr-quality-guards.yml — ${g_hits} loud guard-suite skip(s) across ${g_sampled} sampled run log(s) (merge_group + pull_request legs)." >&2
      for _u in "${GUARD_UNITS[@]}"; do
        IFS='|' read -r _uname _disc _marks <<< "$_u"
        echo "        ${_uname}: ${unit_hits[$_uname]} hit(s) in ${unit_obs[$_uname]} observed log(s) — markers: ${_marks//;/, }" >&2
      done
      any_fail=1
    elif [[ "$g_all_observed" -eq 1 ]]; then
      echo "PASS: pr-quality-guards.yml — 0 loud guard-suite skips across ${g_sampled} sampled run log(s) (bump observed ${unit_obs[bump]}, mint observed ${unit_obs[mint]})"
    fi
  fi
fi

# Verdict: FAIL dominates (a hit counts even when another source could not be
# read); otherwise any unreadable source is TRANSIENT — never a clean bill.
if [[ "$any_fail" -eq 1 ]]; then
  _clear_transient_streak
  echo "      ADR-188's declared observation window has fired: a skip is masking a persistent" >&2
  echo "      condition rather than a transient one. For rehearsal-arm hits the deferred" >&2
  echo "      pre-baked image (#7535) is owed and the S1 extension (#7572) becomes the same" >&2
  echo "      class of problem; for g1b./g2b./fl. hits a runner git no longer exhibits the" >&2
  echo "      walk contract the guard-suite rows validate (#10921) — refusal coverage is" >&2
  echo "      degraded until the runner image or the rows change." >&2
  exit 1
fi

if [[ -n "$transient_reasons" ]]; then
  _transient "$transient_reasons"
fi

_clear_transient_streak
echo "PASS: no loud skips in any observed source — the persistence residual has not materialised."
exit 0
