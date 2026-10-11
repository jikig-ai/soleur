---
title: A status-ledger line that cites an approval must record whether the approval preceded the action and who gave it
date: 2026-10-11
category: workflow-patterns
tags: [adr, status-ledger, provenance, review]
---

# Learning: a status-ledger line that cites an approval must record the order and the approver

## Problem

ADR-276's Stage status ledger needed one dated line recording Decision 4 (draft-PR light
checks) as adopting, on the strength of a CTO review comment. The first draft was built from
the handoff brief and the plan, and said only "condition 1 of the CTO review comment".
Two review seats (security, history) found that this reads as a human CTO approval that
gated activation, when the sequence was: operator's go (`S3-CONFIRMED`, which recorded the
CTO confirmation as still owed) -> `CI_DRAFT_LIGHT` on at 09:43:31Z -> an agent-run CTO
review comment at 09:46:49Z, posted from the operator's account. A third seat (pattern)
found "adopting" was a new stage-state word in a ledger whose preamble defines the current
state as the last dated line naming the stage, and that the line never said it superseded
"CTO confirmation still owed" and "S3 live waits for activation".

## Solution

Lead the line with the stage state (`S3 activated, Decision 4 adopting`), name the comment as
agent-run with its timestamp, state the order (activation preceded it by about three minutes),
say what it answers, link the activation evidence, point at the conditions still open, and
leave the question whether an agent-run review stands in for the human confirmation to the
operator instead of settling it silently.

## Key Insight

An approval cited in an append-only record is a claim about ORDER and APPROVER as much as
about content. Read the comments the line cites (not only the brief that summarises them)
before writing the provenance sentence, and compare the new line against every earlier line
that states the opposite condition ("owed", "waits for").

## Session Errors

1. **First draft omitted activation order and approver identity.** Recovery: review panel, fixed in `d33cf919b7`. Prevention: before writing a provenance sentence, `gh api` the cited comments and put the timestamps next to the action they are claimed to gate.
2. **Queued `test-all.sh --affected` (position 3 behind two sibling worktrees) was made stale by the review fixes.** Recovery: stopped it with `proc.sh kill_mine` before editing so the repo-boundary check would not report a false suite write; ship Phase 4 re-runs it. Prevention: edits during a queued gate invalidate it; stop it first.
3. **Closing text twice named a future action and tripped the unkept-promise stop hook.** Recovery: restated as an explicit BLOCKED fact. Prevention: when only waiting on background agents, say what is blocking, not what comes next.
4. **A stray no-op `sed -i` on `/dev/null` in a commit command.** One-off; no effect.
