#!/usr/bin/env bash
# watchdog-debounce-soak-9686.sh — post-merge soak probe for #9686.
#
# NOTIFY-ONLY probe — this tracker must never be closed by a script. "The
# debounce holds" is established by wall-clock evidence that no human can
# shortcut at file time, and "it still false-fired" is a human-investigate
# verdict either way. So EVERY verdict lands in the sweeper's registered
# TRANSIENT sub-vocabulary (followthrough-convention.md): nothing here exits
# 0 or 1.
#
# What it measures (the issue's done-signal, mirrored as code):
#   main-health-monitor.yml runs on main AFTER the commit that introduced
#   this file (= the debounce PR's squash-merge; `commits?path=` on a file
#   that did not exist before this PR) are inspected newest-first. A run
#   QUALIFIES only when its health-check job log proves the tests step
#   actually dispatched test-all.sh — a suite banner (`--- <name> ---`) or
#   the `=== N suites` terminal. A run that never reached tests is excluded
#   from the denominator, never counted as clean (proof-by-absence is only
#   evidence where the emitter was armed).
#   - DIRTY: any qualifying run carrying `parent process gone` (or the
#     `runner died untrappably` sibling) — the debounce did not hold, or a
#     real orphan reaped; either needs a human.
#   - CLEAN: two consecutive qualifying runs with zero watchdog kills.
#
# Exit semantics:
#   2 = NOT YET           (<2 qualifying post-merge runs measured so far)
#   3 = CANNOT ESTABLISH  (gh/jq missing, GH_TOKEN unset, merge commit or a
#                          run/job/log read failed — an unmeasured window
#                          must never masquerade as a clean one)
#   5 = ACTION REQUIRED   (clean soak → verify + close the tracker manually;
#                          dirty run → investigate the reap)
#  78 = xtrace refusal while GH_TOKEN is set (#7797)
#
# Credential posture: secrets=GH_TOKEN (the sweeper forwards
# secrets.GITHUB_TOKEN with actions:read). Probe reads: workflow runs, jobs,
# compare, and job logs — actions:read only.
#
# RETIREMENT: when #9686's tracker is closed and its follow-through label is
# removed, delete this file, its .test.sh, and its run_suite line in
# scripts/test-all.sh.
set -uo pipefail

# XTRACE REFUSAL (#7797): GH_TOKEN-bound probes refuse `bash -x` — tracing
# echoes the expanded credential into the transcript before first use.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

GH_REPO="${GH_REPO:-jikig-ai/soleur}"
WORKFLOW="main-health-monitor.yml"
SELF_PATH="scripts/followthroughs/watchdog-debounce-soak-9686.sh"
# Upper bounds, not targets: the scan stops at the first dirty run or the
# second clean qualifying run, so a healthy window costs ~3 log fetches.
MAX_CANDIDATES=8

[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN not set (secrets= clause)" >&2; exit 3; }
command -v gh  >/dev/null || { echo "CANNOT ESTABLISH: gh not on PATH" >&2; exit 3; }
command -v jq  >/dev/null || { echo "CANNOT ESTABLISH: jq not on PATH" >&2; exit 3; }
command -v timeout >/dev/null || { echo "CANNOT ESTABLISH: timeout not on PATH" >&2; exit 3; }

# ── 1. The merge commit: the NEWEST main commit touching this file. ──────────
# `commits?path=` returns newest-first — today that IS the debounce merge
# (this file is new in this PR). Caveat, named not hidden: a later probe
# edit on main re-anchors the window to the amendment — earlier post-merge
# runs read `behind` and the soak degrades toward NOT YET, never toward a
# false clean. Harmless at RETIREMENT (probe + tracker retire together).
# ts_re: `gh run view --log` prefixes every line with a timestamp — emitted
# lines match `^<ts> <content>`; the runner's ANSI-wrapped `run:`-block echo
# does NOT (e.g. `Z <ESC>[36;1m gone_hits=$(grep … 'ERROR: parent process gone'`).
ts_re='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z'
MERGE_RC=0
# --jq keeps gh's own rc visible to `||`; the emitted JSON string is unquoted
# in a SECOND statement — a `| tr` inside the same $(...) would mask gh's rc.
MERGE_RAW="$(gh api "repos/${GH_REPO}/commits?path=${SELF_PATH}&sha=main&per_page=1" \
  --jq '.[0].sha // "UNPARSEABLE"' 2>/dev/null)" || MERGE_RC=$?
MERGE_SHA="${MERGE_RAW//\"/}"
if [[ "$MERGE_RC" != "0" ]] || [[ ! "$MERGE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "CANNOT ESTABLISH: could not resolve the merge commit for ${SELF_PATH} on main (rc=${MERGE_RC}, sha='${MERGE_SHA}')" >&2
  exit 3
fi

# ── 2. Candidate runs: completed health-monitor runs on main, newest first. ──
RUNS_RC=0
RUNS_JSON="$(gh api "repos/${GH_REPO}/actions/workflows/${WORKFLOW}/runs?status=completed&branch=main&per_page=30" \
  --jq '[.workflow_runs[] | {id, head_sha, created_at, conclusion}]' 2>/dev/null)" || RUNS_RC=$?
if [[ "$RUNS_RC" != "0" ]] || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$RUNS_JSON"; then
  echo "CANNOT ESTABLISH: workflow-runs read failed (rc=${RUNS_RC})" >&2; exit 3
fi

QUALIFYING=0       # qualifying runs measured (tests step demonstrably armed)
CLEAN=0            # consecutive qualifying runs with zero watchdog kills
DIRTY_RUN=""       # first qualifying run carrying a watchdog-kill line
KILLED_TOTAL=0     # [KILLED] suite lines across qualifying runs (any cause)
EXAMINED=0         # candidates inspected (post-merge ancestors only)

while IFS= read -r ROW; do
  [[ "$EXAMINED" -ge "$MAX_CANDIDATES" ]] && break
  RID="$(jq -r '.id' <<<"$ROW")"
  HEAD="$(jq -r '.head_sha' <<<"$ROW")"
  if [[ ! "$RID" =~ ^[0-9]+$ ]] || [[ ! "$HEAD" =~ ^[0-9a-f]{40}$ ]]; then
    echo "CANNOT ESTABLISH: malformed run row (id='${RID}' head_sha='${HEAD}') — API contract drift" >&2; exit 3
  fi
  # Post-merge? compare merge...head — ahead|identical means the run's main
  # already carried the debounce. 'behind' means it predates the fix; skip
  # silently (not a qualifying denominator member either way).
  CMP_RC=0
  CMP_RAW="$(gh api "repos/${GH_REPO}/compare/${MERGE_SHA}...${HEAD}" \
    --jq '.status // "UNPARSEABLE"' 2>/dev/null)" || CMP_RC=$?
  CMP="${CMP_RAW//\"/}"
  if [[ "$CMP_RC" != "0" ]]; then
    echo "CANNOT ESTABLISH: compare read failed for run ${RID} (rc=${CMP_RC})" >&2; exit 3
  fi
  case "$CMP" in
    ahead|identical) ;;
    behind|diverged) continue ;;
    *) echo "CANNOT ESTABLISH: compare for run ${RID} returned '${CMP}' — API contract drift" >&2; exit 3 ;;
  esac
  EXAMINED=$(( EXAMINED + 1 ))

  # The health-check job for this run.
  JOBS_RC=0
  JOB_ID="$(gh api "repos/${GH_REPO}/actions/runs/${RID}/jobs?per_page=50" \
    --jq '[.jobs[] | select(.name == "health-check")][0].id' 2>/dev/null)" || JOBS_RC=$?
  if [[ "$JOBS_RC" != "0" ]] || [[ ! "$JOB_ID" =~ ^[0-9]+$ ]]; then
    echo "CANNOT ESTABLISH: health-check job read failed for run ${RID}" >&2; exit 3
  fi

  # One log fetch feeds all greps. `gh run view --job --log` — NOT
  # `gh api …/jobs/<id>/logs`: measured 2026-09-18 on gh 2.101.0 (see
  # git-data-boot-poll-8178.sh), `gh api` exits 1 on logs carrying terminal
  # escape sequences, and the health-check `run:`-block echo always carries
  # them. timeout bounds the fetch; a temp file bounds memory.
  LOG="$(mktemp -t wd-soak-9686-log.XXXXXXXX)" || { echo "CANNOT ESTABLISH: mktemp failed" >&2; exit 3; }
  LOG_RC=0
  timeout 120 gh run view --job "$JOB_ID" --repo "$GH_REPO" --log > "$LOG" 2>/dev/null || LOG_RC=$?
  if [[ "$LOG_RC" != "0" ]] || [[ ! -s "$LOG" ]]; then
    rm -f "$LOG"
    echo "CANNOT ESTABLISH: job-log read failed for run ${RID} (rc=${LOG_RC})" >&2; exit 3
  fi

  # Watchdog-kill evidence FIRST — the emitted form `^<ts> ERROR: <text>` is
  # dispositive proof the emitter was armed AND that it fired. The raw
  # phrases alone are NOT a dirty signal: main-health-monitor.yml's verdict
  # classifier greps the literal `^ERROR: parent process gone` inside its
  # own run: block, so every job log contains an ANSI-wrapped echo of that
  # source line — counting bare phrases would read every run as dirty.
  WD_KILLS="$(grep -cE "^${ts_re}[[:space:]]+ERROR: (parent process gone|runner died untrappably)" "$LOG" || true)"

  # Emitter-armed? A suite dispatch banner (` <ts> --- name ---` — banner
  # shape unanchored at the front because the timestamp sits before it), the
  # suites terminal line, or the dispositive watchdog emit itself. A reaped
  # run can lack a terminal `===` line AND carry the reap — the emit is the
  # one marker that can never be absent exactly where DIRTY lives. Without
  # one, "zero watchdog lines" proves nothing.
  if ! grep -qE ' --- .+ ---$|=== [0-9]+/[0-9]+ suites passed ===|=== [0-9]+ suites:|^'"${ts_re}"'[[:space:]]+ERROR: ' "$LOG"; then
    rm -f "$LOG"
    continue   # never reached the tests step: excluded, not clean
  fi
  KILLED_TOTAL=$(( KILLED_TOTAL + $(grep -c '\[KILLED\]' "$LOG" || true) ))
  rm -f "$LOG"
  QUALIFYING=$(( QUALIFYING + 1 ))

  if [[ "$WD_KILLS" != "0" ]]; then
    DIRTY_RUN="$RID"
    break
  fi
  CLEAN=$(( CLEAN + 1 ))
  [[ "$CLEAN" -ge 2 ]] && break
  # stop early once the verdict is decidable either way
done < <(jq -c '.[]' <<<"$RUNS_JSON")

printf 'soak: merge=%s | examined=%s qualifying=%s clean-streak=%s dirty=%s | killed-suites=%s\n' \
  "${MERGE_SHA:0:12}" "$EXAMINED" "$QUALIFYING" "$CLEAN" "${DIRTY_RUN:-none}" "$KILLED_TOTAL"

# ── Verdict ──────────────────────────────────────────────────────────────────
if [[ -n "$DIRTY_RUN" ]]; then
  echo "ACTION REQUIRED: post-merge run ${DIRTY_RUN} still shows a watchdog reap line — inspect whether it was a real orphan or the debounce failed (gh run view ${DIRTY_RUN} --log | grep -n 'parent process gone')."
  exit 5
fi
if [[ "$CLEAN" -ge 2 ]]; then
  echo "ACTION REQUIRED: clean soak — ${CLEAN} consecutive post-merge health-monitor runs with zero watchdog kills across ${QUALIFYING} qualifying run(s). The debounce holds; close the #9686 tracker manually."
  exit 5
fi
echo "NOT YET: only ${QUALIFYING} qualifying post-merge run(s) measured so far (need 2 consecutive clean; examined ${EXAMINED})."
exit 2
