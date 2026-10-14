---
module: System
date: 2026-10-11
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "A one-integer merge-queue timeout change (60 to 75) drew a 13-seat review because the plan's frontmatter said `aggregate pattern` while its body said `none`"
  - "Review found stale restatements of the old value that the plan's residual sweep missed: a line-wrapped `60\\nminute`, and `about 50 minutes` (the old basis figure) in a runtime issue-body string"
  - "The ADR addendum carried two claims lifted from my own issue comment: a `green-path PR` label and a run-level maximum read as satisfying item 5's slowest-check trigger"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: low
tags: [review-panel, sweep, stale-restatement, risk-tier, merge-queue, stop-hook, affected-gate, lock-queue]
---

# Learning: a one-integer queue change, and what a phrase-keyed sweep missed

## Problem

PR #10000 raised the merge queue `check_response_timeout_minutes` from 60 to 75 (evidence on the
queue-adoption tracker: 240 `merge_group` runs, p95 44.1, longest success 60.5, one
`checks_timed_out` ejection). The edit itself was one integer in three parity-gated places. Everything
that went wrong was around it.

## Key Insight

Three independent defects, all in the periphery:

1. **A sweep keyed on PHRASING certifies the miss.** The plan's residual sweep grepped
   `60-minute|(60, #9454)|(60)`. It missed `60\nminute` (wrapped across a comment line) and the old
   BASIS figure `about 50 minutes` (a runtime string in the filed-issue body). Panel seats found both,
   plus `ADR-270:292`. A residual-zero count is evidence about a string, never about the claim. Index
   by the claim's SUBJECT (the figure and what it measures) and read every hit. This is the documented
   "correction sweep keyed on phrasing" class; it recurred one day after being written down.
2. **A claim lifted from an issue comment is a precondition, not a source.** The addendum said the
   ejected PR was "green-path" and that a "real candidate exceeded the trigger". The tracker comment
   recorded a RUN-LEVEL failure with the slowest single check unmeasured, and nothing established the
   ejected candidate was green. Item 5's literal trigger (a required check over 30 minutes) was not
   demonstrated; the change rests on run-level evidence. Fixed in the addendum.
3. **Frontmatter and body must agree on `brand_survival_threshold`.** Review scales its seat count
   from the plan frontmatter. `aggregate pattern` on a one-integer change cost 13 seats plus a 5-seat
   fix round. The body carried a reasoned `none` scope-out. Over-declaration is reported, never
   down-tiered mid-review, so the fix belongs at plan time: assert the two fields equal.

## Session Errors

1. **A chained `sleep 60 && gh run list` was blocked by the Bash hook.** Recovery: Monitor with an
   until-loop. **Prevention:** reach for Monitor first when waiting on a condition.
2. **`pgrep -f` was blocked as self-matching.** Recovery: read the capacity listing
   (`test-all.sh --capacity`) and `/proc/<pid>/cmdline`. **Prevention:** none needed, the hook worked.
3. **I launched a second `test-all.sh` (a selection preview) that queued behind the advisory lock for
   30 minutes, then killed it; the wrapper then wrote `rc=143`, which I first read as the gate's own
   verdict.** Recovery: identified the live process by its open log fd. **Prevention:** never start two
   `test-all.sh` runs from one worktree; read the rc file only for the wrapper you launched, and
   confirm the writer's pid before trusting it.
4. **The affected gate never got the lock in over 70 minutes, held by another worktree.** Recovery:
   committed with `LEFTHOOK_EXCLUDE=bun-test`, ran the focused suites directly, let ship's own gate
   own the full run. **Prevention:** a queued gate is a wait, not a blocker; do not hold the pipeline
   on it.
5. **A Monitor expired at its 30-minute cap.** Recovery: re-armed. **Prevention:** none needed.
6. **The stop hook fired four times on closing text that named a future action ("I'll apply the fixes
   once ...").** Recovery: end a legitimate wait with a `<stop>BLOCKED:` tag and put no first-person
   future verb in the closing text. **Prevention:** phrase waits as facts plus a stop tag.
7. **The plan's residual sweep was keyed on phrasing** (see Key Insight 1). **Prevention:** sweep by
   the claim's subject; for a value change, also grep the figure's BASIS (the measurement it came
   from), not only the value.
8. **The addendum carried two unverified claims from my own issue comment** (Key Insight 2).
   **Prevention:** before a dated addendum states a trigger was met, quote the trigger and the
   measurement side by side.
9. **Plan frontmatter and body disagreed on the risk tier** (Key Insight 3). **Prevention:** a plan
   lint or `soleur:plan` assertion that the frontmatter value equals the body's threshold line.
10. **`ensure-semgrep.sh` accepts a semgrep binary that cannot import its module** (the SAST seat
    needed shims). Already tracked as #9957, #9964 and #10012; no new issue filed.

## What was not done in this PR

`MAX_POLL_MIN=90` in `ship/SKILL.md` and `merge-pr/SKILL.md` stays: median healthy merge is about 57
minutes (32 PR CI plus 25 `merge_group`), p95 about 76, the longest observed success about 93, and the
backstop exits early. It is a different subsystem and was recorded on the tracker instead of widening
this PR.

## Tags

category: workflow-issues
module: System
