# Learning: a status-flip PR that PERFORMS the verification falsifies a negative claim its own sweep never looked for

PR #10337 (Ref #10018): flip ADR-282 from adopting to accepted after a read-only read-back of the sole-copy volume's
delete-protection flag returned `protected`.

## Problem

The plan swept the repo for the flip's vocabulary (`adopting`, "in force only once", "takes effect on the merge of PR
#9925") and found ten records. A 7-seat panel then found two more stale sentences, both missed by that sweep and both
made false BY the act of running the read-back:

1. The runbook paragraph under the read-back command still said "it has not been run against the real API". The PR
   ran it against the real API and recorded the result two paragraphs away. Two seats (security, user-impact) found it
   independently; the second-order effect is an incident responder discounting the one command the whole protection
   claim rests on.
2. Article 30 PA-13 cell (e) carried a 2026-10-10 bracket ending "The protections take effect on the merge of PR #9925
   and its apply, not at merge alone". It contains neither literal the sweep grepped, and it sits in a different cell
   of the same row as the cell that got the CLO marker. The CLO, reviewing the legal edits, first said the sentence
   referred to a different PR (#9877) because it had read the wrong cell.

## Solution

- Rewrote the runbook sentence to say it ran once against the real API on 2026-10-15 and printed `protected`.
- Asked the CLO for verbatim wording for cell (e) (the first proposal was BLOCKED: it implied `prevent_destroy` had
  been "applied" and dropped the failed-job caveat), applied that text exactly.
- Recorded the read-back's provenance in the ADR addendum (who ran it, from which one-liner, the exact word), because
  a record that asserts a result with no artifact is unverifiable by every later reader.

## Key Insight

A sweep indexed by the flip's VOCABULARY finds the sentences that said the thing was pending. It cannot find the
sentences that say the verification was never done, because those never use the flip's words. When a PR performs the
action a document describes as not-yet-done, enumerate the NEGATIVE claims the action falsifies ("has not been run",
"not yet exercised", "target state", "takes effect on") and grep their paraphrases across the record set. The same
applies to reviewers: hand the legal reviewer the grep hits, not the file list you remember, because it reads the
cell it is shown.

## Session Errors

1. **Planning subagent lost to a session restart** (nothing on disk) — Recovery: re-ran once per the recovery rule.
   **Prevention:** one-off; the on-disk-artifact check in one-shot Step 1 already covers it.
2. **`decision-challenges.md` failed the technical-ruling gate on shape** (a "technical (legal)" class, a non-ruling
   row) — Recovery: rewrote classes to the gate's closed set. **Prevention:** the plan skill's decision-table
   template should list the closed class set (`technical`, `taste`, `operator (<category>)`).
3. **The finished planner kept re-sending its hand-back five times** — Recovery: `TaskStop`. **Prevention:** stop a
   subagent as soon as its first hand-back arrives; a "waiting on its own background work" status is not a reason to
   keep it alive.
4. **Article 30 row conflicted with a sibling's new item (14)** — Recovery: took main's row, re-applied the two edits,
   placed the marker at the end of item (13). **Prevention:** none beyond merge-before-review (already done).
5. **Sweep keyed on vocabulary missed two stale disclaimers** — see Key Insight. **Prevention:** the plan sweep
   table gains a second column "negative claims this action falsifies" (added to plan sharp edges).
6. **CLO reviewed the wrong cell** — Recovery: pattern seat's quote, then the CLO re-ruled. **Prevention:** pass the
   reviewer the exact sweep hits with row and cell anchors.
7. **Dropped the space the CLO's verbatim text required, producing `]****]`** — Recovery: caught by the `]****]`
   check, one-line fix. **Prevention:** diff the applied text against the quoted ruling before running the lints.

## Tags
category: workflow-issues
module: knowledge-base/engineering/architecture/decisions
