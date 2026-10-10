#!/usr/bin/env bash
# The canonical PR check/merge poll loop for the Monitor tool.
#
# WHY THIS IS A SCRIPT AND NOT A PROSE INSTRUCTION
#
# `pollInstructions()` in plugins/soleur/lib/harness.ts already says to use
# "state-change + heartbeat shell loops", and AGENTS.rules.md carries TWO
# hook-enforced rules about arming a Monitor at all
# (hr-dispatch-async-must-arm-watch, hr-monitor-not-run-in-background-for-polling).
# All three were satisfied, in the same session, by a hand-rolled loop that emitted
# NOTHING for 50 minutes because every one of its `echo`s was behind a terminal-state
# branch. The operator had to ask "why is the monitor not showing progress?".
#
# The rules mandate that a monitor be ARMED. None of them constrains what it EMITS.
# An armed-but-silent monitor satisfies every gate while producing exactly the outcome
# hr-dispatch-async-must-arm-watch names in its own rationale: "Unwatched async work is
# silent, not pending."
#
# THE ASYMMETRY THAT MAKES THIS EASY TO GET WRONG
#
# The Monitor tool's own docs warn about one direction only:
#
#     "if this process crashed right now, would my filter emit anything?"
#
# That catches a filter that greps only the success marker. It does NOT catch the
# inverse, which is what actually happened here: every TERMINAL state was covered
# (merged, failed, cancelled, timed out) and the HEALTHY IN-PROGRESS state was not.
# A correct monitor and a dead monitor then look identical to the operator, and the
# longer the job runs the more it looks like something is stuck.
#
# Rule of thumb this encodes: SILENCE MUST NEVER BE THE HEALTHY SIGNAL. But "emit every poll
# unconditionally" over-corrects into the opposite failure — a 35-minute CI run at a 120s cadence
# is ~17 identical lines, and the Monitor tool auto-stops a watch that produces too many events, so
# over-emitting eventually reproduces silence by another route.
#
# The contract is therefore: emit on CHANGE, and emit a HEARTBEAT every --heartbeat-every polls
# even when nothing changed. Change tells the operator what moved; the heartbeat proves the watch
# is alive. Neither alone is sufficient — change-only is what went silent for 50 minutes, and
# every-poll is what gets throttled.
#
# Usage:
#   monitor-pr-checks.sh <pr-number> [--interval SECONDS] [--max-polls N]
#                        [--heartbeat-every N] [--repo OWNER/REPO]
#
# Emits one line per poll:
#   [OPEN|BLOCKED|automerge=true] 73/78 pass · 0 fail · 0 cancel · 2 pending → test-scripts,...
# and exactly one terminal line:
#   MERGED — ... | CLOSED WITHOUT MERGE — ... | CHECKS SETTLED — ... | TIMEOUT — ...
#
# Exit 0 on a merge or an all-green settle; 1 on a red/closed terminal; 2 on timeout;
# 3 on usage error. The caller's Monitor watch ends when this exits.
#
# CI_DRAFT_LIGHT (ADR-276 S3, #9728): a red `test` row is read through ci-head-verdict.sh. pending-full and no-run report it
# PENDING (`test(ready run <state>)`), stalled and awaiting-approval end the watch (exit 1) with the recovery command, and
# full-decided / n/a / an unanswered resolver keep the row FAILED exactly as before.
#
# Merge queue (#9454): a PR that is IN the merge queue is neither stale nor stuck, so the BEHIND / BLOCKED /
# auto-merge-off verdicts below (which tell the caller to sync, wait on protection, or merge by hand) would
# be wrong or dangerous for it — a push dequeues it. Those arms (and every --heartbeat-every'th poll, so a PR that
# reads CLEAN + armed is covered too) first read the queue through `sync-pr-behind.sh <pr> --queue-state` (the
# one shared read). The read is TRI-STATE: queued / not queued / unknown. A queued PR prints one `IN MERGE QUEUE`
# line and keeps watching. `LEFT THE MERGE QUEUE UNMERGED` (exit 1) needs a POSITIVE not-queued read of an OPEN
# PR from a measured poll, and either a `dequeued` verdict (a removal event newer than the last re-arm / push,
# or seen queued earlier) or a queued sighting of this watch followed by auto-merge off (confirmed by ONE re-read
# first; a not-queued answer whose state is not OPEN, e.g. the queue's own merge landing, is UNKNOWN). An UNKNOWN read (gh
# failed, helper absent) changes nothing: it keeps the previous verdict path, and after a queued sighting it
# holds that verdict (keeps watching) rather than guessing. --repo must be OWNER/REPO (else exit 3).
set -uo pipefail

PR=""; INTERVAL=120; MAX_POLLS=60; HEARTBEAT_EVERY=5; REPO_ARG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)  INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --max-polls) MAX_POLLS="${2:?--max-polls needs a value}"; shift 2 ;;
    --heartbeat-every) HEARTBEAT_EVERY="${2:?--heartbeat-every needs a value}"; shift 2 ;;
    --repo)      [[ "${2:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+$ ]] \
                   || { echo "monitor-pr-checks: --repo must be OWNER/REPO, got '${2:-}' (not a URL, not host-qualified)" >&2; exit 3; }
                 REPO_ARG=(--repo "$2"); shift 2 ;;
    -h|--help)   sed -n '/^# Usage:/,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "monitor-pr-checks: unknown flag $1" >&2; exit 3 ;;
    *)           if [[ -n "$PR" ]]; then echo "monitor-pr-checks: unexpected argument $1" >&2; exit 3; fi
                 PR="$1"; shift ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || { echo "monitor-pr-checks: <pr-number> is required and must be numeric" >&2; exit 3; }
[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -ge 10 ]] || { echo "monitor-pr-checks: --interval must be an integer >= 10" >&2; exit 3; }
[[ "$MAX_POLLS" =~ ^[0-9]+$ && "$MAX_POLLS" -ge 1 ]] || { echo "monitor-pr-checks: --max-polls must be an integer >= 1" >&2; exit 3; }
[[ "$HEARTBEAT_EVERY" =~ ^[0-9]+$ && "$HEARTBEAT_EVERY" -ge 1 ]] || { echo "monitor-pr-checks: --heartbeat-every must be an integer >= 1" >&2; exit 3; }

# REFUSE TO START rather than degrade. `mktemp`'s status was unchecked, and this script runs
# `set -uo pipefail` WITHOUT `-e`: on failure ERRTMP="" — which is SET, so `set -u` does not fire —
# and every `2>"$ERRTMP"` then fails the redirection, so the gh call NEVER RUNS. probe_ok=0 on
# every poll, forever. MEASURED with gh stubbed healthy and mktemp stubbed failing: the monitor
# burned its whole budget printing `gh probe FAILED` and closed with `This is an unreachable
# GitHub, not a quiet PR` while GitHub was reachable and the PR was green.
#
# That is worse than the silence this script was written to fix: silence is ambiguous, a confident
# false verdict is not. And it is a dependency this file INTRODUCED — before stderr capture there
# was no temp file, so a full TMPDIR could not affect the success path at all.
ERRTMP="$(mktemp 2>/dev/null)" || ERRTMP=""
if [[ -z "$ERRTMP" || ! -w "$ERRTMP" ]]; then
  printf 'monitor-pr-checks: cannot create a writable temp file for gh stderr (TMPDIR=%s). Refusing to run: without it every poll reports a gh outage that is not happening.\n' \
    "${TMPDIR:-/tmp}" >&2
  exit 3
fi
trap 'rm -f "$ERRTMP"' EXIT

# ── Red-on-main annotation (terminal-fail exit path ONLY) ─────────────────────
# Runs at most once per watch — never per-tick. The gh budget for this is
# per-failing-check, and `gh run rerun` operates on completed runs anyway, so
# settle time is the only point attribution can matter. Every failure inside is
# warn-and-continue: a missing probe script, a gh outage, or a probe error must
# NEVER change this script's own verdict or exit code (#9402).
annotate_red_on_main() {
  local probe rows name runid out marker rc probed=0
  probe="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)/check-red-on-main.sh"
  if [[ ! -x "$probe" ]]; then
    printf '    red-on-main: probe script absent (%s) — no main-attribution.\n' "$probe"
    return 0
  fi
  # `link` carries `actions/runs/<run-id>` — the probe's --run-id input. A second
  # `gh pr checks` read, paid once per watch on this exit path only.
  rows="$(gh pr checks "$PR" "${REPO_ARG[@]}" --json name,bucket,link 2>"$ERRTMP" \
    | jq -r '.[] | select(.bucket=="fail" or .bucket=="cancel")
             | (.name // "") + "\t" + (((.link // "") | [match("actions/runs/([0-9]+)") | .captures[0].string])[0] // "")' 2>/dev/null)"
  if [[ -z "$rows" ]]; then
    # Empty here means the gh read failed OR the failing check flipped to pending between
    # the settle verdict and this re-read — the message names both.
    printf '    red-on-main: no failing-check rows on re-read (gh error or checks flipped pending) — no main-attribution.\n'
    return 0
  fi
  while IFS=$'\t' read -r name runid; do
    [[ -n "$name" ]] || continue
    # A name carrying a control character would split this TSV stream / forge terminal
    # output — the probe refuses them too; skip the row before either surface sees it.
    if [[ "$name" == *[[:cntrl:]]* ]]; then
      printf '    red-on-main: a failing check name carries a control character — not probed.\n'
      continue
    fi
    if [[ -z "$runid" ]]; then
      printf '    red-on-main: "%s" has no actions/runs/<id> link — not probed.\n' "$name"
      continue
    fi
    if [[ "$probed" -ge 10 ]]; then
      printf '    red-on-main: probe budget (10 checks) reached — remaining failures unprobed.\n'
      break
    fi
    probed=$((probed + 1))
    # Reuse ERRTMP (mktemp'd + trap-cleaned at startup) for the probe's stderr — this is a
    # terminal path, nothing after us reads it.
    : >"$ERRTMP"
    if command -v timeout >/dev/null 2>&1; then
      out="$(timeout 30 "$probe" "$name" --run-id "$runid" "${REPO_ARG[@]}" 2>"$ERRTMP")"; rc=$?
    else
      out="$("$probe" "$name" --run-id "$runid" "${REPO_ARG[@]}" 2>"$ERRTMP")"; rc=$?
    fi
    marker="$(grep -m1 '^SOLEUR_RED_ON_MAIN ' <<<"$out" || true)"
    if [[ -n "$marker" ]]; then
      printf '    %s\n' "$marker"
    else
      # Surface the probe's own first diagnostic — rc alone ("rc=124") names the shape but
      # not the cause (a gh outage vs a timeout reads identically without it).
      printf '    red-on-main: probe for "%s" gave no verdict (rc=%s%s) — not quarantined.\n' \
        "$name" "$rc" "$(head -1 "$ERRTMP" 2>/dev/null | sed 's/^/; probe said: /')"
    fi
  done <<<"$rows"
}

# in_queue — the TRI-STATE merge-queue read through `sync-pr-behind.sh <pr> --queue-state`: returns 0 = queued,
# 1 = a positive NOT-queued answer, 2 = unknown (gh failed, unparseable, the script absent). It sets Q_DQ=1 when the
# answer's first token is `dequeued` (out of the queue, OPEN, and a removal event newer than the last re-arm/push,
# or seen queued earlier) and Q_RM to the removal reason. Collapsing 2 into 1 ("not queued") is what made one
# transient gh failure end the watch with a false terminal LEFT THE MERGE QUEUE UNMERGED.
QS_SH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)/sync-pr-behind.sh"
Q_DQ=0; Q_RM="none"
in_queue() {
  local out first v st
  Q_DQ=0; Q_RM="none"
  [[ -r "$QS_SH" ]] || return 2
  out="$(PR_QUEUE_REPO="${REPO_ARG[1]:-}" bash "$QS_SH" "$PR" --queue-state 2>/dev/null)" || return 2
  first="${out%%$'\n'*}"; v="${first%% *}"
  case "$first" in *removal=*) Q_RM="${first##*removal=}"; Q_RM="${Q_RM%% *}" ;; esac
  # The verdict's STATE token (2nd field) must be OPEN for a not-queued answer to mean anything: `not_queued MERGED` is the
  # queue's own merge landing (and CLOSED is not a departure), so it is UNKNOWN here (hold, the next view reads it), never
  # a positive "left the queue".
  st="${first#* }"; st="${st%% *}"
  case "$v" in
    queued)     return 0 ;;
    not_queued) [[ "$st" == OPEN ]] || return 2; return 1 ;;
    dequeued)   [[ "$st" == OPEN ]] || return 2; Q_DQ=1; return 1 ;;
    *)          return 2 ;;
  esac
}

# ci_verdict — the head verdict from ci-head-verdict.sh (ADR-276 S3, #9728). With CI_DRAFT_LIGHT on, a draft's `test`
# is red BY DESIGN; after `gh pr ready` that row stays the newest `test` row until the ready run's aggregator posts
# (38 to 51 minutes), so `gh pr checks` reads `fail` for a PR that is merely waiting. Sets V_STATE to the resolver's
# state, or "" when it cannot answer (script absent, gh failed): every caller then keeps today's reading, never a
# softer one. CI_HEAD_VERDICT_BIN is the test seam.
VERDICT_SH="${CI_HEAD_VERDICT_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)/ci-head-verdict.sh}"
V_STATE=""
ci_verdict() {
  local m
  V_STATE=""
  [[ -r "$VERDICT_SH" ]] || return 1
  m="$(bash "$VERDICT_SH" verdict "$PR" "${REPO_ARG[@]}" 2>/dev/null)" || true
  m="$(grep -m1 '^SOLEUR_CI_HEAD_VERDICT ' <<<"$m")" || return 1
  m="${m#*state=}"; m="${m%% *}"
  case "$m" in n/a|full-decided|pending-full|no-run|stalled|awaiting-approval) V_STATE="$m" ;; *) return 1 ;; esac
}

n=0; prev_sig=""; queue_seen=0
while :; do
  n=$((n + 1))

  # `|| true` on BOTH probes and a literal fallback: a transient gh/network failure must not kill
  # the loop. A monitor that dies on one bad request is the silent failure one level up.
  # stderr is CAPTURED, not discarded. A bare "probe FAILED" line names neither which call failed
  # nor why, so a recurring failure cannot be diagnosed from the transcript afterwards — which is
  # the same "a signal that does not say what it means" problem this script exists to fix, one
  # level in. `|| true` keeps a failure from killing the loop.
  view_err=""
  view="$(gh pr view "$PR" "${REPO_ARG[@]}" --json state,mergeStateStatus,autoMergeRequest \
           --jq '"\(.state)|\(.mergeStateStatus)|\(.autoMergeRequest != null)"' 2>"$ERRTMP" || true)"
  view_err="$(head -c 160 "$ERRTMP" 2>/dev/null | tr '\n' ' ')"
  probe_ok=1; failed_probe=""; view_fail_err=""; checks_fail_err=""
  [[ -n "$view" ]] || { view="UNKNOWN|UNKNOWN|false"; probe_ok=0; failed_probe="pr view"; view_fail_err="$view_err"; }
  IFS='|' read -r state mergestate automerge <<<"$view"

  checks="$(gh pr checks "$PR" "${REPO_ARG[@]}" --json name,bucket 2>"$ERRTMP" || true)"
  checks_err="$(head -c 160 "$ERRTMP" 2>/dev/null | tr '\n' ' ')"
  [[ -n "$checks" ]] || { checks='[]'; probe_ok=0; failed_probe="${failed_probe:+$failed_probe + }pr checks"; checks_fail_err="$checks_err"; }

  # A red `test` row on a PR whose ready run is pending (or missing) is the DRAFT run's row: report it PENDING under a
  # label that says why, never FAILED. full-decided / n/a / an unanswered resolver leave the row exactly as read.
  V_STATE=""
  if [[ "$probe_ok" == "1" && "$(jq '[.[]|select(.name=="test" and .bucket=="fail")]|length' <<<"$checks" 2>/dev/null || echo 0)" -gt 0 ]]; then
    ci_verdict || true
    case "$V_STATE" in
      pending-full|no-run|stalled|awaiting-approval)
        checks="$(jq -c --arg l "test(ready run $V_STATE)" '[.[]|if (.name=="test" and .bucket=="fail") then (.bucket="pending" | .name=$l) else . end]' <<<"$checks")" ;;
    esac
  fi

  tot=$(jq  'length'                                        <<<"$checks" 2>/dev/null || echo 0)
  pass=$(jq '[.[]|select(.bucket=="pass")]|length'          <<<"$checks" 2>/dev/null || echo 0)
  fail=$(jq '[.[]|select(.bucket=="fail")]|length'          <<<"$checks" 2>/dev/null || echo 0)
  cancel=$(jq '[.[]|select(.bucket=="cancel")]|length'      <<<"$checks" 2>/dev/null || echo 0)
  pend=$(jq '[.[]|select(.bucket=="pending")]|length'       <<<"$checks" 2>/dev/null || echo 0)
  # `skipping` IS a documented gh bucket (pass|fail|pending|skipping|cancel) and it is part of the
  # array length. Counting it in `tot` but in none of the tallies made the pass fraction
  # unreachable on any PR with a path-filtered job: `1/3 pass` printed next to `ALL GREEN`.
  skip=$(jq '[.[]|select(.bucket=="skipping")]|length'      <<<"$checks" 2>/dev/null || echo 0)
  # The denominator is what CAN pass. Skipped checks are reported separately rather than folded in.
  gradable=$(( tot - skip ))
  waiting=$(jq -r '[.[]|select(.bucket=="pending")|.name]|join(",")' <<<"$checks" 2>/dev/null | cut -c1-90)
  red=$(jq -r '[.[]|select(.bucket=="fail" or .bucket=="cancel")|"\(.bucket):\(.name)"]|join(" ")' <<<"$checks" 2>/dev/null | cut -c1-160)

  # ── THE EMISSION DECISION, before any terminal branch. Emit when the observable state CHANGED,
  # and otherwise every HEARTBEAT_EVERY polls so a long quiet stretch still proves liveness. The
  # first poll always emits (prev is empty), so the operator sees a baseline immediately.
  # `waiting` and `red` are IN the signature: a re-run that swaps which check is pending, or a
  # different check failing at the same count, changes nothing numeric but changes what the
  # operator is waiting on. probe_ok is in it so repeated outages are not collapsed.
  sig="${probe_ok}|${failed_probe}|${state}|${mergestate}|${automerge}|${pass}|${tot}|${skip}|${fail}|${cancel}|${pend}|${waiting}|${red}"
  if [[ "$sig" != "${prev_sig:-}" ]]; then
    why=""
  elif [[ $(( n % HEARTBEAT_EVERY )) -eq 0 ]]; then
    why=" · unchanged, still watching"
  else
    why="SKIP"
  fi
  if [[ "$why" != "SKIP" ]]; then
    if [[ "$probe_ok" != "1" ]]; then
      # DEGRADED INPUT MUST NOT RENDER AS MEASURED INPUT. The fallbacks below are literals, not
      # readings; printing them in the same shape as real counts is the "a zero that does not say
      # what it means" class this repo fixed twice on the observability side.
      if [[ "$failed_probe" == "pr checks" ]]; then
        # `pr view` SUCCEEDED — state, mergeState and automerge are real readings. Saying "state
        # unknown" here would discard data we hold and hide a merge/disarm/DIRTY transition for the
        # whole outage.
        printf '[%s|%s|automerge=%s] check counts UNAVAILABLE — `gh pr checks` failed (poll %s/%s)%s%s\n' \
          "$state" "$mergestate" "$automerge" "$n" "$MAX_POLLS" \
          "${checks_fail_err:+ · checks: }${checks_fail_err}" "$why"
      else
        printf '[gh probe FAILED: %s — state unknown] (poll %s/%s)%s%s%s\n' \
          "${failed_probe:-unknown}" "$n" "$MAX_POLLS" \
          "${view_fail_err:+ · view: }${view_fail_err}" \
          "${checks_fail_err:+ · checks: }${checks_fail_err}" "$why"
      fi
    else
      printf '[%s|%s|automerge=%s] %s/%s pass · %s fail · %s cancel · %s pending%s skipped · (poll %s/%s)%s%s%s\n' \
        "$state" "$mergestate" "$automerge" "$pass" "$gradable" "$fail" "$cancel" "$pend" \
        " · $skip" "$n" "$MAX_POLLS" \
        "${waiting:+ → }" "$waiting" "$why"
    fi
    [[ -n "$red" ]] && printf '    NON-PASS: %s\n' "$red"
  fi
  prev_sig="$sig"

  case "$state" in
    # `$gradable`, NOT `$tot` — the same denominator the poll line uses. Fixing the fraction in the
    # per-poll renderer and leaving it raw here made the landing run print `68/68 pass` and
    # `68/73 pass` two lines apart. The instance fixed, the class left.
    MERGED)
      # The degraded guard belongs here too. `gh pr checks` failing on the very poll that first
      # observes MERGED is a REALISTIC co-occurrence, not a contrived one: the head branch has just
      # been auto-deleted, and gh reports `no checks reported on the '<branch>' branch` with empty
      # stdout and a non-zero exit — this script's failure condition exactly. Without the guard the
      # closing line read `landed (0/0 pass, 0 skipped, 0 fail, 0 cancel)` from the `[]` literal.
      if [[ "$probe_ok" != "1" ]]; then
        printf 'MERGED — PR #%s landed, but the %s probe FAILED on this poll, so the check counts were NOT measured.\n' "$PR" "${failed_probe:-gh}"
      else
        printf 'MERGED — PR #%s landed (%s/%s pass, %s skipped, %s fail, %s cancel).\n' "$PR" "$pass" "$gradable" "$skip" "$fail" "$cancel"
      fi
      exit 0 ;;
    CLOSED) printf 'CLOSED WITHOUT MERGE — PR #%s.\n' "$PR"; exit 1 ;;
  esac

  # The ready run will never decide on its own: say so and stop. No fix loop on the draft-red row, and a manual re-run of
  # the draft run is not a recovery (it reuses the cached draft-light output and can cancel the in-flight ready run).
  case "$V_STATE" in
    stalled)
      printf 'READY RUN STALLED — PR #%s was marked ready but no full CI run decided within 75 minutes of the ready event; the red test row is the DRAFT run'"'"'s, by design. Do NOT start a fix loop on it. Recovery with a user token (never GITHUB_TOKEN): gh pr ready --undo %s ; gh pr ready %s\n' "$PR" "$PR" "$PR"
      exit 1 ;;
    awaiting-approval)
      printf 'READY RUN AWAITING APPROVAL — PR #%s: the ready run is waiting for a maintainer to approve a fork workflow run (Actions tab, "Approve and run"); nothing starts until it is approved, and the red test row is the draft run'"'"'s.\n' "$PR"
      exit 1 ;;
  esac

  # Auto-merge silently switching off is a state the operator must hear about: the PR then sits
  # green and unmerged forever, which reads exactly like "still waiting".
  # NOTHING TO GRADE is its own verdict. `gradable` was introduced as "the denominator is what CAN
  # pass", and this gate — which decides whether anything settled at all — was left asking `tot`.
  # On a PR whose every job is path-filtered that produced `0/0 pass` immediately above `ALL GREEN`.
  # `ALL GREEN` and `68/68 pass` render identically to the eye and mean entirely different things.
  if [[ "$tot" -gt 0 && "$pend" -eq 0 && "$gradable" -eq 0 && "$probe_ok" == "1" ]]; then
    printf 'CHECKS SETTLED, NOTHING TO GRADE — PR #%s: all %s check(s) were skipped (path filters); no check actually ran (mergeState=%s).\n' \
      "$PR" "$skip" "$mergestate"; exit 0
  fi

  if [[ "$tot" -gt 0 && "$pend" -eq 0 ]]; then
    if [[ "$fail" -gt 0 || "$cancel" -gt 0 ]]; then
      # UNSTABLE/CLEAN + auto-merge armed means the failing check is NOT required — GitHub still
      # considers the PR mergeable and auto-merge is expected to land it. Exiting rc=1 there is a
      # false red that stops the operator watching a PR that is about to merge anyway.
      if [[ "$automerge" == "true" && ( "$mergestate" == "UNSTABLE" || "$mergestate" == "CLEAN" ) ]]; then
        printf 'NON-REQUIRED CHECK FAILED — PR #%s: %s · mergeState=%s, auto-merge still expected to land it; continuing to watch.\n' "$PR" "$red" "$mergestate"
      else
        printf 'CHECKS SETTLED WITH NON-PASS — PR #%s: %s\n' "$PR" "$red"
        annotate_red_on_main
        exit 1
      fi
    fi
    # Merge queue (#9454): BEHIND, BLOCKED and an unarmed auto-merge are what a QUEUED PR can look like,
    # and each verdict below is wrong for it (syncing or merging by hand dequeues it / skips the
    # merge_group run). Read the queue only for those states; a healthy CLEAN + armed PR costs no call.
    queued=0; qread=2
    if [[ "$state" == "OPEN" && ( "$mergestate" == "BEHIND" || "$mergestate" == "BLOCKED" || "$automerge" == "false" \
          || $(( n % HEARTBEAT_EVERY )) -eq 0 ) ]]; then
      in_queue; qread=$?
      # A positive not-queued OPEN answer with NO removal evidence (not `dequeued`) that would end the watch because a queued
      # sighting is followed by auto-merge off is confirmed by ONE re-read first (as queue_read_settled does for the script's
      # own candidates): the instant the queue's own merge lands reads not queued + OPEN once, then MERGED. The re-read's
      # answer replaces the first (queued again: keeps watching; unknown: holds; not queued OPEN: the departure stands).
      if [[ "$qread" == "1" && "$Q_DQ" != "1" && "$queue_seen" == "1" && "$automerge" == "false" ]]; then
        in_queue; qread=$?
      fi
    fi
    if [[ "$qread" == "0" ]]; then
      queued=1
    elif [[ "$qread" == "2" && "$queue_seen" == "1" ]]; then
      queued=1   # UNKNOWN read after a queued sighting: hold that verdict quietly, never guess a dequeue
    fi
    if [[ "$queued" == "1" ]]; then
      if [[ "$qread" == "0" && "$queue_seen" != "1" ]]; then
        printf 'IN MERGE QUEUE — PR #%s is queued (mergeState=%s): checks are green and the queue merges it. Do NOT sync, update-branch, push or --admin it (a push dequeues it); watching for MERGED or removal from the queue.\n' "$PR" "$mergestate"
      fi
      [[ "$qread" != "0" ]] || queue_seen=1
    elif [[ "$qread" == "1" && ( "$Q_DQ" == "1" || ( "$queue_seen" == "1" && "$automerge" == "false" ) ) ]]; then
      # qread is 1 only when the read ran: state OPEN (the gate above) inside this settled block, which needs a
      # measured `gh pr checks` (tot > 0) and, with a failed `gh pr view`, state UNKNOWN: T24i pins it.
      printf 'LEFT THE MERGE QUEUE UNMERGED — PR #%s is OPEN and out of the queue (removal: %s; auto-merge %s): a failed merge_group run or a removal. Do NOT merge it by hand or --admin it. Read it: gh run list --event merge_group --limit 100 --json databaseId,headBranch,conclusion,url --jq '"'"'.[] | select(.headBranch | startswith("gh-readonly-queue/main/pr-%s-"))'"'"'; recovery (ONE re-enqueue): plugins/soleur/skills/ship/references/merge-queue-dequeue.md.\n' "$PR" "$Q_RM" "$([[ "$automerge" == "true" ]] && echo armed || echo disarmed)" "$PR"
      exit 1
    fi

    # Green but still OPEN with auto-merge armed: keep watching for the merge itself, but say so
    # rather than looping silently.
    # BEHIND and DIRTY are both "green, but a human has to do something", and both are reachable
    # WHILE auto-merge is armed — auto-merge does not resync a stale branch and cannot resolve a
    # conflict. FOUND BY DOGFOODING: the first cut handled BEHIND and not DIRTY, so watching a real
    # PR that went green-then-DIRTY kept polling a state that needed action. The bug was in the
    # branch the operator would read as "still working".
    if [[ "$queued" != "1" ]]; then
      case "$mergestate" in
        BEHIND)  printf 'CHECKS GREEN BUT BEHIND — PR #%s needs a sync before it can merge (auto-merge does not resync). On a repo whose main has a merge queue, an armed PR that reads BEHIND just after its checks settle is usually about to be enqueued by GitHub: re-run this watch once before syncing.\n' "$PR"; exit 1 ;;
        DIRTY)   printf 'CHECKS GREEN BUT DIRTY — PR #%s has a merge conflict; auto-merge cannot resolve it.\n' "$PR"; exit 1 ;;
        DRAFT)   printf 'CHECKS GREEN BUT DRAFT — PR #%s cannot merge until it is marked ready.\n' "$PR"; exit 1 ;;
        # BLOCKED with nothing pending means branch protection is unsatisfied by something OUTSIDE
        # the check list — a missing required review, a required context that never posts, a merge
        # queue. Auto-merge sits there indefinitely. It renders identically to CLEAN, which lands in
        # seconds: same line, opposite futures. That is the defect class this script exists to close,
        # and it is the sibling of the DIRTY miss found by dogfooding.
        BLOCKED) printf 'CHECKS GREEN BUT BLOCKED — PR #%s is held by branch protection outside the check list (a required review or an unposted required context; a PR already in the merge queue reads IN MERGE QUEUE instead). Auto-merge will not resolve it.\n' "$PR"; exit 1 ;;
      esac
    fi

    # ORDER IS THE POINT. This branch must run AFTER the mergeStateStatus dispatch above, never
    # before it. The first cut ran it first and special-cased only DRAFT — so a green PR that was
    # BEHIND (or DIRTY, or BLOCKED) with auto-merge off was told "ALL GREEN, needs an explicit
    # merge" for a merge GitHub would refuse. MEASURED on this script's own PR: it printed exactly
    # that at `mergeState=BEHIND`. Fixing DRAFT alone fixed the INSTANCE and left the CLASS; the
    # dispatch above is the complete set of "cannot merge right now" states, so deferring to it is
    # the fix that does not need revisiting per-state.
    if [[ "$queued" != "1" && "$automerge" == "false" && "$state" == "OPEN" \
          && "$fail" -eq 0 && "$cancel" -eq 0 ]]; then
      printf 'CHECKS SETTLED, ALL GREEN, AUTO-MERGE NOT ARMED — PR #%s needs an explicit merge (mergeState=%s). Before any --admin merge, admin-merge-ready.sh <PR> <sha> must exit 0 — this line reads only checks that exist.\n' "$PR" "$mergestate"; exit 0
    fi
  fi

  if [[ "$n" -ge "$MAX_POLLS" ]]; then
    # The TIMEOUT line must not fabricate counts either — it was the last place a total gh outage
    # still rendered `0/0 pass, 0 pending` as if measured.
    if [[ "$probe_ok" != "1" ]]; then
      printf 'TIMEOUT — PR #%s: the gh probe FAILED on the final poll, so no state was measured (%s polls, %ss apart). This is an unreachable GitHub, not a quiet PR.\n' \
        "$PR" "$n" "$INTERVAL"; exit 2
    fi
    printf 'TIMEOUT — PR #%s still %s after %s polls (%ss apart); last: %s/%s pass, %s skipped, %s pending.\n' \
      "$PR" "$state" "$n" "$INTERVAL" "$pass" "$gradable" "$skip" "$pend"; exit 2
  fi
  sleep "$INTERVAL"
done
