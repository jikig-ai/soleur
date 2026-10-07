---
title: "fix: ship Phase 7 stops syncing an armed BEHIND PR when the base branch has a merge queue"
date: 2026-10-07
slug: ship-phase-7-merge-queue-aware-behind-sync
branch: feat-one-shot-merge-queue-aware-behind-sync
issue: 8683
type: fix
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-07
**Passes run:** deepen-plan halt gates 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 4.12 (all pass or skip, see below); live verification of every cited issue and PR number and rule id; empirical bash-semantics check of the new fence lines; a read-only re-measurement of #9697. The plan had already been through a four-seat review panel (DHH, Kieran, code-simplicity, CTO devex lens) whose findings are applied above.

**Gate results.** 4.6 User-Brand Impact: present, threshold `aggregate pattern`. 4.7 Observability: present, five fields, probe `curl ... | jq` is an allowlisted verb, no SSH, finishes well inside 15 s, `expected_output` is the literal `1` (and was run live: it prints `1`). 4.8 PAT-shaped variables: none. 4.9 UI wireframe: no UI surface, skipped. 4.10 Encryption posture: no `.tf`, migration, cloud-init or compose file in either Files list and no persistent store introduced (the "merge queue" is GitHub's, not a store this plan creates), skipped. 4.11 Guard Contract: `lint-guard-contract.py` green, one entry, assembly names the chokepoint (the single `if/elif` chain on `$s == "OPEN BEHIND"`) and the out-of-fence pushers it does not cover. 4.12 Scope Check: one unfenced section, every ask mapped, no `unmapped`, no `status: BLOCKED`. 4.4 / 4.45 / 4.5 / 4.55: no precedent-bound SQL or lock pattern, no network-outage trigger, no downtime-inducing operation (a fence edit in a skill file), skipped.

**Verification of cited facts (live, this pass).** #8683, #9454, #9670, #9697, #9482 OPEN; #8474 and #8611 MERGED (they are the two recurrence PRs named inside #8683); #9401 CLOSED (the disjoint-delta skip the hook's own comments cite); #9710 is this PR. Every `knowledge-base/` path in the plan exists. `wg-architecture-decision-is-a-plan-deliverable` is a migrated-but-active rule (`scripts/migrated-rule-ids.txt` line 76, now in plan Phase 2.10); every other rule id is active in `AGENTS.md`. Fence anchors confirmed at `ship/SKILL.md` 2267 / 2448 and `merge-pr/SKILL.md` 371 / 517; `model.c4` has `ship` (line 211) and `github` (line 343).

**Bash semantics, run and observed (scratch script, `set -e`).** `[[ ... ]] && real_behind=1`, `(( real_behind == 1 )) || qidle=0` (keeps the count on a BEHIND tick, zeroes it otherwise), `[[ "$(cmd || true)" =~ ^[1-9][0-9]*$ ]] && QUEUE_RULE=1` (a failing or empty read leaves 0 and the shell alive), a `case ... dequeued*) ...; break ;;` inside `if` inside the loop (breaks the loop), an empty `pend` counted as idle, and a trailing `(( queue_waits == 1 )) && echo` in a list (no errexit). `gh pr checks <n> --json bucket --jq '[...] | length'` exits 0 even with pending checks (measured on #9710: prints `25`, rc 0), and `gh pr view <n> --json autoMergeRequest --jq '.autoMergeRequest != null'` prints exactly `true` or `false`.

### New considerations discovered

1. **The BEHIND reading appears while checks are still pending.** Re-measured on #9697 at 12:33Z: `OPEN BEHIND`, 78 pass / 1 pending / 9 skipping, armed, `--queue-state` = `not_queued OPEN armed removal=none`, head `4b0bb6d78d` two `main` commits behind. So BEHIND is not a "CI is done" signal under the strict policy; it is shown while a check is pending, which is exactly the window the wait arm covers. Once everything settled the same PR read `OPEN CLEAN` (still 2 commits behind) and was enqueued about 90 s later; earlier (12:14Z, `behind_by` 0) it read `OPEN BLOCKED`.
2. **#9697 resolved it before the end of the planning session** (see the Premise section): enqueued by GitHub at 12:39:57Z while 2 `main` commits behind, about 90 s after its last check settled, with no push. Latency, the CLEAN-once-settled behaviour and the `disarmed`-while-queued reading are now measured, not assumed.
3. **`--queue-state` consumes the seen-queued marker when it prints `dequeued`** (sync-pr-behind.sh, consume-on-report). Any new caller must therefore treat `dequeued` as terminal, which is why the grace-crossing `case` breaks the poll on it instead of falling through to `--step` (a marker-only dequeue would otherwise read as plain "not queued" and push).

## Overview

The Phase 7 poll in the ship skill (and its byte-synced mirror in merge-pr section 5.2) pushes a merge of
`origin/main` into the PR on every `OPEN BEHIND` reading, through `sync-pr-behind.sh --step`. Each push restarts
the full required-check set (a PR CI run is ~17 to 33 min). `main` merges faster than that, so the branch is BEHIND
again when CI ends. Measured on PR #9697: syncs at 13:19, 13:25 and 13:53 local, a fourth cycle still running at
14:07, no merge.

`main` now has a `merge_queue` rule (ADR-270, #9454). The queue builds each candidate against the projected
post-merge `main`, so "up to date" is satisfied by construction and the sync buys nothing for an armed PR. The code
already refuses to sync a PR that IS in the queue (`kind=queued`, exit 11). The gap is the window BEFORE enqueue,
which is where a PR spends its whole CI cycle. This plan closes that window with the smallest change that can be
made fail-safe: a fence-only "queue mode" that waits instead of syncing, bounded by an idle-grace escape back to
today's behaviour. `sync-pr-behind.sh` itself is not changed.

## Premise Validation and the Open Question (measured, 2026-10-07)

**Question.** The CI Required rule still has `strict_required_status_checks_policy = true`. Does GitHub enqueue an
armed PR that is BEHIND once its checks are green? (a) yes, on its own, so skip the sync and wait; or (b) no, strict
blocks auto-enqueue, so the design needs an explicit enqueue or a ruleset decision.

**Answer: (a), measured.** Method: for each PR merged through the queue in the last day, take the first
`added_to_merge_queue` timeline event, take `git merge-base origin/main <final head>`, and count commits on `main`
dated before that enqueue and after the merge-base. A positive count means the PR head was missing at least that many
`main` commits when GitHub enqueued it. This is a lower bound for any PR that was pushed again after the first
enqueue, and exact for a PR with a single enqueue event.

| PR | auto-merge armed to first enqueue | `main` commits the head was missing at enqueue | enqueue events |
|---|---|---|---|
| #9635 | 20:45 to 21:07 UTC, 22 min | 14 | 1 |
| #9668 | 20:00 to 20:47, 47 min | 4 | 1 |
| #9654 | 20:09 to 20:18, 9 min | 2 | 1 |
| #9665 | 20:13 to 20:45, 33 min | 2 | 1 |
| #9673 | 07:31 to 07:56, 26 min | 1 | 1 |
| #9684, #9655, #9636, #9683 | various | 4, 1, 2, 2 (lower bound) | 2 or 3 |
| #9660, #9672, #9652 | various | 0 | (were up to date) |

Five single-enqueue PRs were enqueued by GitHub while 1 to 14 `main` commits behind, with `auto_merge_enabled`
present in the timeline 9 to 47 minutes BEFORE the enqueue (so each spent its CI window armed and behind), under `strict_required_status_checks_policy = true`
(`gh api repos/jikig-ai/soleur/rules/branches/main` shows `strict: true` on the 23-context rule and `merge_queue`
with SQUASH / ALLGREEN / max_entries_to_build 2 / max_entries_to_merge 1 / min_entries_to_merge_wait_minutes 0 /
check_response_timeout_minutes 60). Outcome (b) was not observed in 5 of 5, which is sufficient to drop the explicit-enqueue design because the expiry arm below carries the PR if GitHub ever behaves otherwise. The green-to-enqueue latency itself is not measured (the table's windows are dominated by CI time); the post-merge check records it. No ruleset change is needed and none is
proposed; `infra/github/ruleset-ci-required.tf` is not touched.

**The motivating PR resolved it (read-only, 2026-10-07).** PR #9697 (never touched by this session) was `OPEN BLOCKED` at
12:14Z (50 pass / 28 pending, `behind_by` 0), became `OPEN BEHIND` once `main` advanced by 2 commits while one check was
still pending (12:33Z: 78 pass / 1 pending, armed, `not_queued`), read `OPEN BEHIND` with every check settled at 12:38:30Z
(79 pass, 0 pending), flipped to `OPEN CLEAN` by 12:38:38Z with its head still 2 `main` commits behind, and GitHub added
it to the merge queue at **12:39:57Z** (`added_to_merge_queue` in its timeline), about 90 seconds after its last check
settled, with no push from anyone. That is a sixth observation for outcome (a), made on the exact PR that motivated this
plan, and it measures the two things the table could not: **last-green-to-enqueue latency is about 90 s**, and **under the
queue the strict-policy BEHIND reading lasts only while a check is pending**; once the checks settle the state reads
CLEAN. The BEHIND window the fence mishandles is therefore exactly the CI window. Two more facts it measured: **a queued PR
reads `disarmed`** (`autoMergeRequest` is null while queued: `--queue-state` printed `queued OPEN disarmed`) and its
`mergeStateStatus` is `CLEAN`. So a queued PR never enters the wait arm; it reaches the existing `--step` queue gate, which
skips it (exit 11), as scenario 18 already pins.

**Still not measured:** the removal-event payload on a real ejection (ADR-270 canary 3, second half). The design does not depend on it.

## Research Insights

**Premise validation (Phase 0.6).** Cited by reference: #8683 (OPEN, scope-out, re-eval 2026-10-24, no closing PR;
its option B, "rely on the merge queue", is what #9454 delivered at the infra layer), #9454 (OPEN, the adoption
issue), #9670 (OPEN, a flake in a `merge_group` run; context only), #9697 (OPEN, another session's PR; read-only).
Cited paths all exist on `origin/main`: the fence markers (`ship/SKILL.md` 2267 / 2448, `merge-pr/SKILL.md` 371 /
517), `sync-pr-behind.sh` (473 lines, `queue_gate` already present), `settle-then-admin-merge.md` line 7 (the
"Under the merge queue" paragraph), the fixture suite (1885 lines). The ADR corpus was grepped for the mechanism:
ADR-270 Decision 5 already makes the merge tooling queue-aware for a queued PR, dequeue, and the hook; it says
nothing about an armed-but-not-yet-queued PR, so this is an extension, not a reversal. The ask's claim "the poll
already fetches this endpoint" is true but narrow: it is fetched once, and only the `required_status_checks` contexts
are kept, so the `merge_queue` entry is not derived today.

**Property List (Phase 0.6b).**

1. An armed PR on a base branch that has a merge queue is not pushed to merely because it reads BEHIND.
2. A repo with no `merge_queue` rule, or one whose rules API cannot be read, behaves exactly as today.
3. A queue-mode PR that GitHub never enqueues does not wait forever; it falls back to today's sync.
4. The operator sees that the poll is waiting by design, and sees when the PR enters the queue.
5. The required-check-failure exit, the DIRTY exit, the dequeue exit and the `MAX_BEHIND_SYNCS` budget are unchanged.

**Cut List (Phase 0.6b).**

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| GraphQL `enqueuePullRequest` from the fence | 3 under outcome (b) | Outcome (b) is refuted by the measurement above; GitHub enqueues on its own. Adds a merge-authority action to a poll. Property 3 is carried by the expiry arm instead. |
| A new flag or exit kind in `sync-pr-behind.sh` (`--step --defer-to-queue`, `kind=queue_pending`) | 1 | `--step` does not know the real `mergeStateStatus`: the fence rewrites a DIRTY reading to `OPEN BEHIND` for the clean-merge-tree and regen cases, and those MUST still push. The Phase 7 fences run a frozen snapshot of the script and refuse a copy whose `--help` lacks `--step`, so a new flag needs a second probe and a skew arm. The fence already holds every input. |
| Changing `strict_required_status_checks_policy` | 3 under (b) | Not needed under (a); a ruleset change is an infra and permissions change and out of scope. |
| Option A of #8683 (settle before sync) for repos with no queue | 1 for queue-less repos | Changes behaviour for every user without a queue, contested design (latency vs convergence). Deferred with a tracking issue, see the #8683 decision. |
| Derived `[ship.phase7.queue*]` tag census as a second guard | 1 (mirror parity) | The anchored parity tokens plus every scenario running through `run_scenario_both` already redden when the mirror lacks a tag; a census would be a second copy of the same pin (plan-review, three reviewers). |
| Folding the armed read into the per-tick `gh pr view` `s=` line, or hoisting the pending count out of the required-check scan | fewer `gh` calls | `s=` is a parity token whose output shape several arms consume, and the scan only runs when `REQUIRED_CHECKS` is non-empty; the two extra reads run only on a queue repo's BEHIND ticks. |
| Editing `.claude/hooks/pre-merge-rebase.sh` | 1 | It runs on a `gh pr merge` command, once per arm, not every 60 s: one push per manual arm or re-arm, not a cycle. It already skips a queued PR and a provably disjoint delta (#9401). Acknowledged, not changed. |
| Editing `plugins/soleur/lib/pr-merge-poll.ts` or `harness.ts` | 4 | Their match patterns already contain `\[ship\.phase7\.`, so the new tags are matched without an edit. |

**Institutional learnings applied.** `2026-06-02-auto-merge-livelock-fast-moving-main.md` (the livelock and its
recurrences; append only). `2026-10-04-a-queue-candidate-trust-check-premised-on-an-unmeasured-commit-shape.md` (a
push to a queued PR dequeues it; dequeue must be readable on every tick). `2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md`
(select the rule by `.type`, never by index; a `merge_queue` entry can sit anywhere in the array).
`2026-05-25-ship-phase-7-state-machine-extension.md` (required-check scan is fail-open on purpose; fixtures execute both
blocks). ADR-270 Decision 5 (the queue reads and the 5th-tick dequeue read this plan builds on). The `settle-then-admin-merge`
reference and `merge-queue-dequeue.md` (recovery text the new lines point at).

**Consumers found.** `git grep -n "behind_syncs\|BEHIND detected\|ship.phase7" -- plugins .claude scripts`: the two fences,
the fixture, `harness.ts` and `pr-merge-poll.ts` (match patterns, no edit), `background-poll-prefer-monitor.sh` (names
the fence, no edit), `monitor-pr-checks.sh` (never syncs, no edit), `sync-pr-behind.sh` (unchanged). The fixture is
registered in `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` and `scripts/lib/test-affected-paths.sh`.
No open `code-review` issue cites any planned file.

**Baseline.** `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` on this branch: 636 pass, 0 fail, 2m33s
wall here. Run it detached (it outlives a Monitor's 30 min cap only if launched with `setsid nohup`, rc written last).

## Research Reconciliation: Brief vs Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "the poll already fetches this endpoint for required checks" | One fetch at loop entry, `--jq` keeps only `required_status_checks` contexts; the `merge_queue` entry is discarded. | Add a second one-time fetch with its own `--jq` rather than restructure the existing `mapfile` line (it is a parity token and has its own fail-open contract). |
| "sync-pr-behind.sh's `kind=queued` skip" | True, but only once the PR is IN the queue, and only when `--step` runs. | Unchanged; this plan covers the window before enqueue. |
| "settle-then-admin-merge.md line 7" | Line 7 is the "Under the merge queue (#9454) a BEHIND livelock is not the failure mode" paragraph; it says the hatch is for BEHIND and NOT queued (before enqueue, or after a dequeue). | Reword that sentence: before enqueue, an armed PR on a queue repo is no longer synced at all. |
| "23 CI Required contexts re-run on merge_group" | Live API: required_status_checks arrays of 23 and 2 (the CLA pair), matching the IaC comment. | None. |
| Brief: pre-merge-rebase.sh "does it also defeat a queued/armed PR?" | It skips a queued PR (`_q_state == queued`) and a provably disjoint delta; it syncs an armed-but-not-queued PR that is behind, but only when a `gh pr merge` command runs (once per arm). | Cut and acknowledged (Cut List). |

## Proposed Solution

All logic lives in the fence (ship canonical, merge-pr mirror), edited in the same commit. Variable names are
final; the code below is the prescription.

**1. Once, before `while true`** (after the `REQUIRED_CHECKS` fetch). Fail-open by construction: the only way
`QUEUE_RULE` becomes 1 is a numeric `>= 1` answer from the rules endpoint.

```bash
# Merge-queue mode (#9710): rule present on the base branch AND auto-merge armed (read per tick below) means the
# queue, not a push, makes the PR current. Fail toward today's behaviour: any unreadable answer leaves QUEUE_RULE=0.
# Only with auto-sync usable (sync_ok and a snapshot): without SYNC_SNAP neither the dequeue read nor the
# enqueue report can run, and today's behaviour there is a named stop with the manual command.
QUEUE_RULE=0; QUEUE_GRACE_TICKS=5; queue_waits=0; qidle=0; qwait_expired=0; queued_reported=0
if [[ "$sync_ok" -eq 1 && -n "$SYNC_SNAP" ]]; then
  [[ "$(gh api 'repos/{owner}/{repo}/rules/branches/main' \
    --jq '[.[] | select(.type == "merge_queue")] | length' 2>/dev/null || true)" =~ ^[1-9][0-9]*$ ]] && QUEUE_RULE=1
fi
```

**2. Report the enqueue** in the existing every-5th-OPEN-tick block, after the `dequeued*` line (no new gh call: it
reuses `$qs`; gated on `QUEUE_RULE` so a repo with no queue prints nothing new):

```bash
[[ "$QUEUE_RULE" -eq 1 && "$qs" == queued* && "$queued_reported" -eq 0 ]] && { queued_reported=1; echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.queued] PR $PR is in the merge queue ($qs) — no sync from here (a push would dequeue it); waiting for MERGED or removal"; }
```

**3. Mark a GitHub-reported BEHIND** immediately after the fast-exit line and before the DIRTY block, so the two
DIRTY arms that rewrite `s="OPEN BEHIND"` (clean local merge-tree; regen-resolved local commit that must be pushed)
can never be taken for it:

```bash
real_behind=0; [[ "$s" == "OPEN BEHIND" ]] && real_behind=1
(( real_behind == 1 )) || qidle=0   # the idle count is CONSECUTIVE: a tick that is not a real BEHIND resets it
```

**4. The wait arm**, placed after the DIRTY block and before the sync `if`, which becomes the `elif` of the new first
arm:

```bash
qwait=0
if (( real_behind == 1 && QUEUE_RULE == 1 && qwait_expired == 0 )) \
   && [[ "$(gh pr view "$PR" --json autoMergeRequest --jq '.autoMergeRequest != null' 2>/dev/null || true)" == true ]]; then
  qwait=1
  # A positive pending count is the only thing that resets the idle count; 0, "no checks", or an unreadable answer
  # all count as idle, so a broken read walks toward the fallback (a sync), never toward waiting forever.
  pend="$(gh pr checks "$PR" --json bucket --jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null || true)"
  if [[ "$pend" =~ ^[1-9][0-9]*$ ]]; then qidle=0; else qidle=$((qidle+1)); fi
  if (( qidle > QUEUE_GRACE_TICKS )); then
    # A PR already IN the queue also shows no pending PR check (measured: a queued PR reads disarmed and CLEAN, so it
    # normally never reaches this arm; the read stays as a cheap guard for an armed-and-queued reading), so ask before
    # calling it un-enqueued. A dequeue is
    # reported here exactly as the every-5th-tick read does (--queue-state consumes the seen-queued marker, so
    # falling through to --step after it would read "not queued" and push).
    qs="$(bash "$SYNC_SNAP" "$PR" --queue-state 2>/dev/null || true)"
    case "$qs" in
      queued*)   qidle=0 ;;
      dequeued*) echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.dequeued] PR $PR left the merge queue unmerged ($qs). Stopping the poll; see ${CLAUDE_PLUGIN_ROOT}/skills/ship/references/merge-queue-dequeue.md"; break ;;
      *)         qwait=0; qwait_expired=1
                 echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.queue_wait_expired] PR $PR has been BEHIND with auto-merge armed and no check pending for ${qidle} ticks and is not in the merge queue — the queue is not picking it up. Falling back to the BEHIND auto-sync for the rest of this poll." ;;
    esac
  fi
fi
if [[ "$qwait" -eq 1 ]]; then
  queue_waits=$((queue_waits+1))
  (( queue_waits == 1 )) && echo "$(date +%H:%M:%S) [${i}/${MAX_POLL_MIN}] [ship.phase7.queue_wait] PR $PR is BEHIND with auto-merge armed and the base branch has a merge queue: no sync (a push restarts CI and dequeues a queued PR); waiting for GitHub to enqueue it"
elif [[ "$s" == "OPEN BEHIND" && "$sync_ok" -eq 1 && "$behind_syncs" -lt "$MAX_BEHIND_SYNCS" ]]; then
  # ... the existing sync arm, byte-for-byte unchanged ...
```

The expiry latches `qwait_expired`, so the arm is never entered again in this poll; a PR the queue turns out to
hold resets `qidle` instead and keeps waiting. A new `soleur:ship` invocation re-arms the poll with fresh counters, which is deliberate:
a fresh poll gets a fresh chance to wait.

The existing sync `if [[ "$s" == "OPEN BEHIND" && "$sync_ok" -eq 1 ...` line becomes an `elif`; every other line of
that arm and of the `behind_no_sync` and `behind_exhausted` arms is unchanged.

**Why every other exit keeps working.** The required-check-failure scan, the dequeue read and the DIRTY block all run
BEFORE the wait arm in the same tick, so a failed required check, a dequeue or a real conflict still stops the poll
on that tick. The wait arm never touches `behind_syncs`, `behind_pushes`, `ci_cycles` or `behind_warned`, so the
budget and the hatch counter are exactly where today's code leaves them. Waiting does not consume
`MAX_BEHIND_SYNCS`; after expiry the budget applies in full.

**Failure direction of every added branch.**

| Branch | Fires when | If it is wrong | Direction |
|---|---|---|---|
| `QUEUE_RULE` fetch | rules API returns `>= 1` merge_queue rule | rules API error, empty, non-numeric, or a repo with no queue: is left at 0, today's code path runs untouched | toward syncing (today) |
| | a rule exists but the queue is not operating | armed BEHIND PR waits; leaves the wait on the idle grace below | bounded wait, then syncing |
| `real_behind` | GitHub itself reports `OPEN BEHIND` | a DIRTY-derived `OPEN BEHIND` is never a wait: it syncs as today | toward syncing |
| armed read | prints exactly `true` | `false` (disarmed), error, empty, anything else: arm not taken | toward syncing |
| wait arm | all of the above and not yet expired | checks pending forever (hung run): waits to `MAX_POLL_MIN` = 90 and the existing timeout line prints `Queue:` (today's code would have synced, which restarts a hung run to no better end) | bounded by the existing backstop |
| idle count | `pend` is not a positive integer | any read failure or zero pending: counts idle, walks to expiry | toward syncing |
| expiry | more than 5 consecutive idle ticks AND `--queue-state` does not read `queued` or `dequeued` | latches for the rest of this poll; today's arm, budget and hatch apply in full | toward syncing |
| | `--queue-state` read fails | not `queued`, so it expires and the sync arm runs; its own `--step` queue read still refuses to push to a queued PR (fail-closed `kind=gh`) | toward syncing, never a push to a queued PR |
| enqueue report | `$qs` starts with `queued` | cosmetic line only; no state is changed | none |

**Bounded wait.** Two bounds, both pre-existing or small: the 5-idle-tick grace (a PR whose every check is settled
and which GitHub still has not enqueued 5 minutes later leaves queue mode and syncs, which is outcome (b)'s
remedy at today's cost), and `MAX_POLL_MIN = 90` for a PR whose checks never settle.

**One consequence to accept, stated.** While queue mode waits, the BEHIND-tick `--step` read does not run, so a
dequeue is found by the existing every-5th-OPEN-tick `--queue-state` read (up to 5 minutes later) instead of on the
next BEHIND tick. ADR-270 already designs for exactly this ("reachable from every `mergeStateStatus` ... every 5th
OPEN tick"). The seen-queued marker is not written by `--queue-state`, so a dequeue in this mode is found through
the current `RemovedFromMergeQueueEvent` path, which GitHub emits for every removal measured so far (#9482).

## Implementation Phases

**Phase 1 - failing tests first (`cq-write-failing-tests-before`).** In
`plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`: add `QGH` (a copy of the existing `GQL_GH` mock with three
new arms: `api repos/{owner}/{repo}/rules/branches/main` serving `$MOCK_RULES` = `queue` (a `merge_queue` entry in the
MIDDLE of the array, behind an unrelated rule and ahead of a `required_status_checks` entry, so both a first-index and
a last-index reader fail) | `noqueue` | `error`, running the `--jq` it is handed through real `jq`; `pr view ...
autoMergeRequest` serving `$MOCK_ARMED` = `true | false | error`, discriminated on the `autoMergeRequest` argument so
the existing `pr view` arm keeps its answer; `pr checks` serving `$MOCK_CHECKS` = `pending | green | none | error` as a
JSON array of `{name,bucket}` and running whichever `--jq` it is handed, because the same arm also feeds the existing
required-check scan). Add the scenarios in the table below, each through `run_scenario_both`. Mock details the reviewers found missing: `QGH` defaults `MOCK_GQL_SEQ` to `not_queued` (the Q rows never set
it, and an empty sequence indexes a bad subscript); `MOCK_CHECKS=required_fail` for Q10 with the rules JSON naming that
context; `MOCK_NO_MERGE_ON_PUSH=1` for Q6b (the shared `pr view` arm flips to MERGED once `pushed` exists); Q11 carries a
`git()` override answering `rev-parse --is-inside-work-tree` false, as the existing scenario 11 does; Q7 sets
`MOCK_MSS=DIRTY`; Q9 sets `MOCK_MERGED_AT=8` (otherwise it runs all 90 ticks per fence). Q1 and Q6 also run once with
`SCENARIO_SET_E=1` (the errexit host shell) so the `set -e` analysis is pinned, not argued. Run it: Q1, Q6, Q6b, Q8, Q9
must be RED (no wait arm yet: Q8 today stops at `sync_failed exited 13`, Q9 prints no `[ship.phase7.queued]`); Q2 to Q5,
Q7, Q10, Q11 GREEN (they pin today's behaviour).

**Phase 2 - the fence, both mirrors, one commit.** Apply the insertions to `ship/SKILL.md` and the same to
`merge-pr/SKILL.md` section 5.2 (trimmed comments allowed, tokens and logic identical). Add to the mirror parity token
list the anchored call forms (not bare words, `cq-assert-anchor-not-bare-token`): `select(.type == "merge_queue")`,
`QUEUE_GRACE_TICKS=5`, `.autoMergeRequest != null`, `real_behind=0; [[ "$s" == "OPEN BEHIND" ]] && real_behind=1`,
`[ship.phase7.queue_wait]`, `[ship.phase7.queue_wait_expired]`, `[ship.phase7.queued]`. Run `bash -n` on both
extracted blocks (the suite does), then the full suite detached.

**Phase 3 - prose, ADR, learning.** `ship/SKILL.md`: the sentence that lists the unmergeable states, and a new
**Queue mode** paragraph after "Auto-sync on BEHIND". `merge-pr/SKILL.md`: section 5.2 intro and the trailing tag
paragraph (`queue_wait`, `queue_wait_expired`, `queued`). `settle-then-admin-merge.md`: reword the line-7 sentence.
`ADR-270`: amend Decision 5 and record the measurement under Canary measurements. The 2026-06-02 learning: append a
short dated `## Resolution under the merge queue (2026-10-07)` section. Do not rewrite any dated record.

**Phase 4 - verify and ship.** Mutation battery (Guard Contract), then the full suite, then
`bash plugins/soleur/test/c4-count-parity.test.sh` (expected green, no C4 file is edited), then `soleur:ship`.
PR body: `Ref #8683`, `Ref #9454`, `Ref #9670` (see the decision below), plus a comment on #8683.

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md` - fence insertions 1 to 4; sentence at the Phase 7 intro; new Queue mode paragraph.
- `plugins/soleur/skills/merge-pr/SKILL.md` - the same four insertions in the mirror (section 5.2); intro and trailing paragraph.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` - `QGH` mock, scenarios Q1 to Q11, anchored parity tokens, header index.
- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` - line 7 wording.
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` - Decision 5 amendment and canary record (status stays `adopting`).
- `knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md` - append only.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-merge-queue-aware-behind-sync/tasks.md`

Not edited, by design: `plugins/soleur/scripts/sync-pr-behind.sh`, `.claude/hooks/pre-merge-rebase.sh`,
`infra/github/ruleset-ci-required.tf`, `plugins/soleur/lib/*.ts`, any C4 file.

## Open Code-Review Overlap

None. The `code-review` open-issue query was run against every planned path (the two SKILL.md files, the fixture, the
settle reference, `sync-pr-behind.sh`, ADR-270, the learning) and matched no issue body.

## The #8683 decision

**`Ref #8683`, not `Closes`.** Three independent plan reviewers converged on this and the reasoning holds. The change
delivers option B of #8683 ("rely on the merge queue") at the ship layer for queue repos, which removes the livelock on
`main` (the repo both recurrences, #8474 and #8611, happened on). It does NOT make "an armed PR is never pushed to on
BEHIND" true everywhere: queue-less repos are unchanged, the idle-grace expiry falls back to syncing, and the pre-merge
hook still syncs once per `gh pr merge`. #8683 is already the scope-out tracker for option A (settle before sync, the
answer for a repo with no queue) with a re-evaluation date of 2026-10-24; closing it would drop that tracker and need a
successor issue carrying identical content.

**Option A is deferred, tracked by #8683 itself.** It changes the shared `sync_step` the three callers use and the
"behaviour exactly today's" requirement for queue-less repos; it stays a contested-design scope-out. At ship time post
one comment on #8683: queue mode shipped (link the PR), the livelock no longer reproduces on queue repos, and the
re-evaluation now concerns queue-less repos only. If the operator wants #8683 closed, that is a one-line follow-up and
is recorded in `decision-challenges.md` as a taste item.

## User-Brand Impact

- **If this lands broken, the user experiences:** a PR that never merges (an armed PR parked behind a queue that never
  picks it up) or one that livelocks exactly as today, visible as a Monitor stream with `[ship.phase7.queue_wait]`
  and no `MERGED`, or `[ship.phase7.queue_wait_expired]` followed by repeated syncs.
- **If this leaks, the user's workflow is exposed via:** no new data surface. The change adds two read-only `gh` calls per
  BEHIND tick on queue repos and one `gh api` read at loop entry; nothing is written, logged off-host or sent to a
  Soleur sink.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident`: the merge queue still runs the 23 required contexts
  on `merge_group`, so a wrong wait can delay a merge but cannot land unreviewed code; a repeated stall across many PRs is
  the brand risk, which is the aggregate tier.

## Observability

Layer: 7 (self-hosted CLI synchronous consumer, `cli-stdout-artifact`). This fence runs in the operator's Monitor shell
from the Soleur plugin; it has no Soleur-side sink and must not gain one. The same fence text is also read by the hosted
agent only as instructions; it executes in the shell the harness provides, so layer 7 is the whole execution surface.
Durable artifact paired with the stdout markers: the PR's own timeline (`added_to_merge_queue`, `merged`, and the head
commit list show whether any push happened) and the `ci_cycles` Pipeline-Tally rendered into the PR body, which does not
move while queue mode waits (no push, no `incr ci_cycles`).

```yaml
liveness_signal:
  what: "Monitor stdout: the poll's state line every 3rd tick plus [ship.phase7.queue_wait] once on entry and [ship.phase7.queued] once on enqueue"
  cadence: "one state line per state change or every 3 ticks (~3 min); 60 s tick"
  alert_target: "the Monitor notification stream the invoking session already reads; no paging path (interactive CLI)"
  configured_in: "plugins/soleur/skills/ship/SKILL.md (Phase 7 fence) and plugins/soleur/skills/merge-pr/SKILL.md (section 5.2 mirror)"
error_reporting:
  destination: "stdout of the Monitor shell (a Monitor streams stdout only); no Sentry, by layer 7 design"
  fail_loud: "[ship.phase7.queue_wait_expired] when queue mode gives up; the existing timeout line plus Queue: <state> at MAX_POLL_MIN"
failure_modes:
  - mode: "armed PR in queue mode is never enqueued although every check is settled"
    detection: "[ship.phase7.queue_wait_expired] on stdout after 5 idle ticks, then today's BEHIND sync lines"
    alert_route: "Monitor notification to the invoking session, which reads the line and surfaces the strict-policy question to the operator"
  - mode: "queue mode waits while checks never settle (hung run)"
    detection: "no queue_wait_expired; the poll runs to MAX_POLL_MIN and prints Merge poll timed out with Queue: <state>"
    alert_route: "Monitor notification of the timeout line; recovery text in ship/references/merge-queue-dequeue.md"
  - mode: "rules API or armed read fails, queue mode silently off"
    detection: "no queue_wait line and the sync arm runs: BEHIND detected - auto-sync attempt lines (today's behaviour, visible)"
    alert_route: "Monitor notification; the heartbeat state line shows OPEN BEHIND while the sync lines show the push"
  - mode: "PR dequeued while queue mode is waiting"
    detection: "[ship.phase7.dequeued] from the every-5th-OPEN-tick --queue-state read (at most 5 ticks later)"
    alert_route: "Monitor notification, poll stops with recovery on the line"
logs:
  where: "the Monitor output file for the session; PR timeline on GitHub for the head-commit and queue events"
  retention: "session lifetime for the Monitor output; GitHub timeline indefinitely"
discoverability_test:
  command: "curl -s https://api.github.com/repos/jikig-ai/soleur/rules/branches/main | jq -r '[.[] | select(.type == \"merge_queue\")] | length'"
  expected_output: "1"
```

The probe reads the exact precondition the fence keys on (a `merge_queue` entry from the same rules endpoint), needs no
credentials (the repo is public) and no SSH, and finishes well inside the 15 s cap; it tells an operator in one line
whether a Phase 7 poll on this repo will run in queue mode.

## Guard Contract

### Guard 1 - queue-mode wait arm never syncs outside its window

**Property.** While GitHub reports a PR `OPEN BEHIND`, auto-merge is armed, the base branch has a `merge_queue` rule and
the PR has not been idle for more than 5 consecutive ticks, the poll issues no `sync-pr-behind.sh --step`; in every other
state the arm is inert and the poll behaves exactly as before this change.

**Assembly.** Every place a Phase 7 poll can push into the PR branch: (1) the `--step` sync arm in the ship fence, (2) the
same arm in the merge-pr mirror, (3) the DIRTY-derived paths (clean local merge-tree, and regen-resolved local commit) that
rewrite `s` to `OPEN BEHIND` and reach the same arm, (4) the `sync_ok == 0` stop arm (`behind_no_sync`), which sits in the
same `if/elif` chain. The chokepoint is that single chain keyed on `$s == "OPEN BEHIND"`; the wait arm is its new first
member. Out-of-fence pushers are named and deliberately not covered: the `pre-merge-rebase.sh` hook (once per `gh pr
merge`, not a poll) and the standalone `sync-pr-behind.sh <n>` loop used by the review recovery path.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | neutralise the wait arm in the ship fence only (`if false && [[ "$qwait" -eq 1 ]]`; deleting the branch leaves a dangling `elif` that fails `bash -n`, which would redden for the wrong reason) | RED (Q1:ship sees `BEHIND detected`) |
| 2 | neutralise it in the merge-pr mirror only (a SECOND member after a compliant first) | RED (Q1:merge-pr, plus the mirror token rows) |
| 3 | break the rules selector (`.type == "merge_queue"` to `"merge_queue_x"`): the guard's OWN dispatch silently never fires | RED (Q1 requires `queue_wait` exactly once, so zero waits cannot pass) |
| 4 | drop the `real_behind` guard so a DIRTY-derived BEHIND waits | RED (Q7 expects `auto-sync 1 pushed`) |
| 5 | drop the armed read (treat every queue-rule PR as armed) | RED (Q4 disarmed expects the sync) |
| 6 | force `QUEUE_RULE=1` regardless of the API | RED (Q2 no-queue and Q3 API-error expect the sync) |
| 7 | REORDER: reset `qidle=0` at the top of every tick instead of only on a positive pending read, so the grace window can never close | RED (Q6 expects `queue_wait_expired` then the sync; a delete-only battery would not see a window property) |
| 8 | remove the expiry latch (`qwait_expired=1`) so a later tick re-enters the arm | RED (Q6b, where every sync leaves BEHIND, expects exactly one `queue_wait_expired` line; Q6 merges on the expiry tick and cannot see it) |
| 9 | drop the `--queue-state` read at the grace crossing (expire unconditionally) | RED (Q9 expects no expiry for a PR the queue holds) |
| 10 | gate `QUEUE_RULE` on the rules read only, dropping the `sync_ok` / `SYNC_SNAP` condition | RED (Q11 expects `behind_no_sync` with auto-sync disabled) |
| 11 | drop the `(( real_behind == 1 )) \|\| qidle=0` reset so the idle count stops being consecutive | RED (Q6c: BEHIND on ticks 1 to 3 and 5 to 7 with a BLOCKED tick 4 must not expire before tick 10) |

**Harness rows (edits to the SUITE that must also redden).** H1: make the `QGH` rules arm always answer `noqueue` while Q1
still expects a wait: Q1 must go RED, proving Q1 can see the arm. H2: a must-PASS row that is NOT the canonical shape: Q1's
rules array carries `merge_queue` in the middle behind an unrelated rule type (a first-index or last-index reader fails).
Anti-vacuity floor: Q1 requires `queue_wait\]` on EXACTLY one line (`ONCE`), so a suite whose wait arm never dispatches
cannot pass with "0 checked"; the parity token rows are the second pin on the mirror.

**Anchor.** The guard compares no stored value (no hash, count or manifest); it is behavioural, and both fences are
executed by the same rows through `run_scenario_both`. Nothing outside the commit has to move for a weakening to pass.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-270, Decision 5 (no new ordinal, so no ordinal-collision exposure): add the bullet "the Phase 7 fences do not
sync an armed PR that reads BEHIND when the base branch has a `merge_queue` rule: queue mode waits for GitHub to enqueue
it, bounded by a 5-idle-tick grace and `MAX_POLL_MIN`, and falls back to today's sync on any unreadable answer (#9710)",
and add the measurement (five single-enqueue PRs enqueued 1 to 14 commits behind under the strict policy) to the Canary
measurements section. Status stays `adopting`. This is a task in Phase 3, not a follow-up.

### C4 views

No C4 impact. All three model files were checked (`model.c4` 921 lines, `views.c4` 118, `spec.c4` 54): external actors
(`founder`, `contributor`; the CLI session is the already-modeled `ship` component at `model.c4:211` inside `plugin`),
external systems (`github` at `model.c4:343` is the only system this fence talks to, through `gh`), data stores (none
touched), and actor-to-surface relationships (`founder -> github` approvals, unchanged). No element or edge is added or
falsified, and `grep -i "merge.queue\|phase 7\|sync-pr-behind"` over the three files returns nothing to correct.
`bash plugins/soleur/test/c4-count-parity.test.sh` ran green at plan time (0 failed) and is re-run in Phase 4.

### Sequencing

The decision is true as soon as the fence ships; nothing is soak-gated.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected - infrastructure/tooling change confined to the plugin's merge-poll fence, its
tests and its documentation. The CTO lens (merge-gating blast radius) is covered by the failure-direction table and the
Guard Contract; no product, legal, marketing, finance, sales or support surface is touched, and no UI file is in either
Files list.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Make the ship workflow merge-queue-aware so BEHIND syncs stop restarting CI." | Proposed Solution 1 to 4; Phase 2 | mapped |
| 2 | "read it and decide whether this change genuinely resolves it (note it also proposes a "settle before sync" option A; say whether this plan covers or defers it)" | The #8683 decision (`Ref`, not `Closes`: option B delivered for queue repos, option A deferred and still tracked by #8683) | mapped |
| 3 | "OPEN QUESTION TO SETTLE FIRST (evidence, do not assume)" | Premise Validation and the Open Question (outcome a, measured; #9697 recorded as not yet discriminating) | mapped |
| 4 | "Queue detected = base branch rules ... has a `merge_queue` entry ... AND auto-merge armed. When both hold: no sync push on BEHIND; keep polling checks and queue state; report when it enqueues." | Insertions 1 (rule), 4 (armed + wait), 2 (report enqueue) | mapped |
| 5 | "No merge_queue rule ... or rules API failure => behavior EXACTLY today's. Fail toward current behavior, never toward silently not syncing." | Failure-direction table; scenarios Q2, Q3, Q4, Q5 | mapped |
| 6 | "MAX_BEHIND_SYNCS budget, DIRTY exit, required-check-failure exit, dequeue exit keep working." | "Why every other exit keeps working"; scenarios Q6b, Q7, Q10, Q8 | mapped |
| 7 | "edit both mirrors in one commit, run `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`; plan must include mutation tests (delete the new branch -> a test reddens; fixture where queue rule absent; fixture where rules API errors)" | Phase 2; Guard Contract rows 1 to 8; Q2 (rule absent), Q3 (API error) | mapped |
| 8 | "Plan must state the failure direction of every added branch, and a bounded-wait/escape" | Failure-direction table; Bounded wait; expiry arm | mapped |
| 9 | "Smallest change." | Cut List (script, hook, TS, ruleset all untouched) | mapped |
| 10 | "HARD BOUNDARY: ... Do NOT push to its branch, sync it, enqueue it, or merge it; read-only gh calls only." | Sharp Edges (read-only on #9697; no phase writes to it) | mapped |
| 11 | "never touch infra/github/ruleset-ci-required.tf" | Files to Edit (not listed); Cut List | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| fence insertions 1 to 4 | "no sync push on BEHIND; keep polling checks and queue state; report when it enqueues" | asked |
| expiry arm (5 idle ticks) | "a bounded-wait/escape so a queue-mode PR that never enqueues ... does not wait forever" | asked |
| `real_behind` guard | "DIRTY exit ... keep working" | asked |
| `[ship.phase7.queued]` enqueue report | "report when it enqueues" | asked |
| ADR-270 amendment and canary record | - | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable`; the change extends an existing ADR's Decision 5 and the measurement closes a recorded unknown |
| learning append and settle-reference rewording | "Prose assuming the livelock" | asked |
| comment on #8683 recording that queue mode shipped | "say whether this plan covers or defers it" | asked |

### Split Assessment

- Subsystems touched: 2 - `plugins/soleur/skills` (ship, merge-pr, references), `plugins/soleur/test`; plus 2 knowledge-base docs (ADR, learning)
- Planned files: 7 | Estimated changed lines: ~330 (fence 2 x ~35, fixture ~190, prose ~50, ADR ~20, learning ~15)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The sync arm is textually unchanged except `if` becoming `elif` (`git diff` of that line only).
- [ ] On a fixture with a `merge_queue` rule (in the middle of the rules array), auto-merge armed and a pending check, a poll that reads `OPEN BEHIND` for 12 ticks makes no `--step` call, no push and no `BEHIND detected` line, prints `[ship.phase7.queue_wait]` exactly once, and ends `MERGED CLEAN` (Q1, both fences).
- [ ] With no `merge_queue` rule (Q2), with the rules API erroring (Q3), with auto-merge disarmed or the armed read erroring (Q4) and with auto-sync disabled (Q11), the poll behaves exactly as before: `BEHIND detected - auto-sync attempt 1/6`, or `behind_no_sync` for Q11.
- [ ] With the rule, armed, every check settled (green, none reported, or unreadable) and the PR not in the queue (Q6), `[ship.phase7.queue_wait_expired]` prints once on the first tick whose idle count exceeds 5 and that same tick syncs; with the saturation fixture the budget still ends in `behind_exhausted` (Q6b). A PR the queue holds (`--queue-state` reads `queued`) is never expired (Q9).
- [ ] A DIRTY reading with a clean local merge-tree (Q7) and a required-check failure (Q10) behave as before under queue mode; a removal event under queue mode stops the poll with `[ship.phase7.dequeued]` within 5 ticks (Q8); `[ship.phase7.queued]` prints once on enqueue and never on a repo with no queue (Q9, Q2).
- [ ] `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` passes (baseline 636 pass, 0 fail; the new total is higher and 0 fail), run detached.
- [ ] Every mutation row of Guard 1 was applied and observed RED, then reverted (recorded in the PR body); `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] The merge-pr mirror carries the new anchored parity tokens (`select(.type == "merge_queue")`, `QUEUE_GRACE_TICKS=5`, `.autoMergeRequest != null`, the `real_behind` line, the three tags).
- [ ] `plugins/soleur/scripts/sync-pr-behind.sh`, `.claude/hooks/pre-merge-rebase.sh` and `infra/github/ruleset-ci-required.tf` are byte-identical to `origin/main` (`git diff --stat origin/main -- <paths>` empty).
- [ ] ADR-270 Decision 5 carries the amendment and the canary record; the 2026-06-02 learning has the appended section and no pre-existing line changed (`git diff` shows additions only); `settle-then-admin-merge.md` line 7 no longer implies a pre-enqueue sync for an armed PR on a queue repo.
- [ ] PR body: `Ref #8683`, `Ref #9454`, `Ref #9670`; `## Changelog` present; semver label `semver:patch`. No `Closes` line.

### Post-merge (agent-run)

- [ ] Comment on #8683: queue mode shipped (PR link), the livelock no longer reproduces on queue repos, the re-evaluation now concerns queue-less repos only (option A).
- [ ] On the next real PR through Phase 7 that reads BEHIND, confirm from its Monitor output and timeline that no push followed the first `queue_wait` line and that `added_to_merge_queue` preceded `merged`; record the result, including the last-green-to-enqueue latency (one sample so far: about 90 s on #9697), as a one-line comment on #9454.

## Test Scenarios

All run through `run_scenario_both` (ship fence and merge-pr mirror), with `QGH` and `PR_QUEUE_RETRY_SLEEP=0`.

| Row | Rules | Armed | Checks | Other | Must match | Must not match |
|---|---|---|---|---|---|---|
| Q1 | queue (middle of array) | true | pending | `MOCK_MERGED_AT=13`, BEHIND | `queue_wait\]` exactly once (`ONCE`), `MERGED CLEAN` | `BEHIND detected`, `auto-sync`, `MOCK: git merge`, `UNEXPECTED gh call` |
| Q2 | no queue entry | true | pending | BEHIND | `BEHIND detected - auto-sync attempt 1/6` | `queue_wait`, `ship.phase7.queued` |
| Q3 | API error | true | pending | BEHIND | `BEHIND detected - auto-sync attempt 1/6` | `queue_wait` |
| Q4 | queue | loop over `false` and `error` | pending | BEHIND | `BEHIND detected - auto-sync attempt 1/6` | `queue_wait\]` |
| Q6 | queue | true | loop over `green`, `none`, `error` | BEHIND, `--queue-state` reads not queued | `queue_wait_expired` exactly once (tick 6), then `auto-sync 1 pushed` on that tick | a second `queue_wait_expired` |
| Q6b | queue | true | green | saturation fixture (every sync leaves BEHIND, `MOCK_NO_MERGE_ON_PUSH=1`) | `behind_exhausted ... after 6 auto-syncs`; `queue_wait_expired\]` exactly once (`ONCE`) | `UNEXPECTED gh call` |
| Q6c | queue | true | pending, but BLOCKED on tick 4 (the BEHIND ticks are 1-3 and 5-7), then green BEHIND | no expiry before tick 10: the idle count is consecutive | `queue_wait_expired` at tick 10 or later | `queue_wait_expired` before tick 10 |
| Q7 | queue | true | pending | DIRTY with clean merge-tree | `auto-sync 1 pushed` | `queue_wait\]`, `ship.phase7.dirty\] PR is DIRTY` |
| Q8 | queue | true | pending | `MOCK_GQL_SEQ=queued,removed`, BEHIND | `[10/90] [ship.phase7.dequeued]` | `[11/90]`, `auto-sync` |
| Q9 | queue | true (conservative: a real queued PR reads `disarmed` and CLEAN) | green | `MOCK_GQL_SEQ=queued`, BEHIND, 12 ticks | `[ship.phase7.queued]` exactly once, no expiry | `queue_wait_expired`, `auto-sync` |
| Q10 | queue | true | a required context in `fail` | BEHIND | `[ship.phase7.required_failed]` | `queue_wait\]` after the failure tick |
| Q11 | queue | true | pending | not inside a worktree (`sync_ok=0`) | `behind_no_sync` | `queue_wait` |

Regression anchors: every pre-existing scenario stays unchanged and green because the default `gh api` mock answers
nothing, so `QUEUE_RULE` is left at 0 for all of them.

## Risks and Sharp Edges

- **A plan whose `## User-Brand Impact` is empty or placeholder fails deepen-plan Phase 4.6.** It is filled above (`aggregate pattern`).
- **Hard boundary.** PR #9697 belongs to another session. Every `gh` call against it is read-only; none of the work, tests
  or mutation rows may name its branch in a write. The fixtures are synthesized (`cq-test-fixtures-synthesized-only`).
- **Do not "harden" the rules fetch to fail closed.** A repo with no ruleset, no permission to read it, or an API
  outage must run today's code. Failing toward "do not sync" is the defect this plan exists to avoid.
- **A positional rules reader is a bug.** The `merge_queue` entry can sit first, last or between other rules; the selector
  is `.type == "merge_queue"`, and Q1 serves the entry in the middle of the array so a first-index or last-index reader fails.
- **`QUEUE_GRACE_TICKS` is a tick count, not minutes.** A tick is one `sleep 60` plus the `gh` calls; if the tick length
  ever changes, the grace moves with it. 5 is a margin over one measured latency (about 90 s, see the grace note above); re-derive
  once the post-merge check has recorded more samples.
- **The base branch is `main`, hard-coded**, as in the rest of the fence (both the required-check read and the sync target
  `origin/main`); a PR with another base reads the `main` rules. Out of scope; unchanged from today.
- **The 5-tick grace is a margin over a measured latency.** Last-green-to-enqueue was about 90 s on #9697 (one observation);
  armed-to-enqueue was 9 to 47 min, CI-dominated. Five minutes is roughly 3x the one measured latency; the post-merge check
  records more samples. If a dequeue ever lacks a `RemovedFromMergeQueueEvent`,
  queue mode waits to `MAX_POLL_MIN`; the `--queue-state` read at the grace crossing reports a marker-or-event dequeue first.
- **Latching expiry is deliberate.** After one expiry the poll behaves as today for its remaining life, so a flapping
  read cannot oscillate between waiting and pushing.
- **The fixture suite is slow here (2m33s).** Run it with `setsid nohup`, write the rc to a file last, and have the
  Monitor only read that file; never host the run in the Monitor (`2026-09-17-the-watcher-and-the-watched-shared-a-lifetime.md`).
  After adding rows, check the suite against `scripts/suite-durations.tsv` / `scripts-shard-runtime-coverage.test.sh`.
- **Edit both fences in one commit and cross-grep both** (`plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/merge-pr/SKILL.md`);
  the mirror trims comments but not logic. The only `${CLAUDE_PLUGIN_ROOT}` reference in the new lines is the dequeued echo copied
  verbatim from the existing every-5th-tick line (same recovery pointer, same loader substitution); the other new echo lines carry none.
- **If the idle grace ever fires in production** that is outcome (b) or a stalled queue: the line says so. Surface the
  `strict_required_status_checks_policy` question to the operator; this plan does not change the ruleset.

## Review-round amendments (2026-10-07, appended; the plan above records the design at plan time)

The panel review and one fix round changed the design in these ways. The code, fixtures and ADR amendment are authoritative.

- **No `--queue-state` read at the grace crossing.** Expiry is `qwait=0; qwait_expired=1`: the fallback `--step` runs `sync-pr-behind.sh`'s own queue gate, which skips a queued PR (exit 11), stops on a dequeue (exit 13) and fails closed on an unreadable read (exit 4). A queued reading on the every-5th-tick `--queue-state` read restarts the idle count instead, so while each 5th-tick read answers queued the PR does not expire. Mutation row 9 and the `dequeued*` arm are gone; Q9 pins the queued case, Q9b the unreadable-read expiry.
- **The idle count counts only pending REQUIRED checks** (names intersected with `REQUIRED_CHECKS`) and is exactly consecutive: `(( qwait == 1 )) || qidle=0` after the wait block restarts it on any non-wait tick, including a disarmed armed-read.
- **Queue mode needs a non-empty required-check set** (`(( ${#REQUIRED_CHECKS[@]} > 0 )) || QUEUE_RULE=0`): with none, or a failed read of it, the poll syncs as today (Q1n).
- **Guard 1 wording:** after the first expiry the fallback holds for the rest of the poll, so "has not been idle for more than 5 consecutive ticks" applies only until an expiry has occurred.
- **Agent-instruction sites** (`pr-merge-poll.ts`, `harness.ts`, codex and devin `INSTRUCTIONS.md`, ship rule 6, `drain-prs`, the dequeue reference) carry the queue-mode exception with pins for every harness; `monitor-pr-checks.sh`, the standalone `sync-pr-behind.sh <n>` loop and the pre-merge hook are deferred (tracked on #8683).
- **Fixtures:** the verdict floor is ratcheted and the Q row set is pinned (`RANQ`/`WANTQ`); the armed read runs its jq; added rows Q1m, Q1n, Q2e, Q3b, Q6d, Q6e, Q6f, Q6g, Q6h, Q9b.
