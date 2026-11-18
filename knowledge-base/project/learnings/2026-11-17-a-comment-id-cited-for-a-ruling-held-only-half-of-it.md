---
title: A comment id cited for a ruling held only half of it
date: 2026-11-17
category: workflow-issues
module: knowledge-base records (runbooks, legal audits)
tags: [provenance, citation, append-only, records, review]
pr: 12843
issues: [10479, 12441, 12850]
---

# Learning: a comment id cited for a ruling held only half of it

## Problem

PR #12843 recorded the CLO and CTO rulings of 2026-11-16 in the origin-TLS
strict-flip runbook and the counsel-review audit. The session brief said the
CLO ruling was "recorded on #10479 in comment 6946870123". The plan extended
that citation to the CTO ruling too, and four runbook lines then cited the
comment for every CTO sub-claim. `decision-challenges.md` said the rows were
"quoted from" it.

A `gh api` read of the comment showed it held only the p90 "provisionally
attributed" and p50 "unexplained" parts. The 500s line, the evidence bar, the
restart/Supabase candidates and the `coloCode`/host/end-time shape came from
the session brief's relay and are not in the comment. Two review seats
(pattern, code-quality) found this independently.

Same PR, a second twin: the runbook's own "Cleanup status (2026-11-13)" block
still said "Merge apply: pending" while the legal audit had been marked
Superseded for the same fact.

## Solution

- Kept the comment citation only for what it holds. Sourced the rest to the
  PR's `decision-challenges.md`, with a one-line provenance note above the
  four lines, and corrected the "quoted from" line.
- Appended a Superseded marker under the stale Cleanup status block, with the
  merge SHA, apply run, re-measure comment and the OPEN issue state, without
  editing the signed block.
- CLO ruled that precondition 1's "#10479 is closed" in `inngest-server.md`
  means the legal-record closure, not GitHub state, and that a ruled verbatim
  sentence must stay byte-identical; comment ids move to a second sentence.

## Key Insight

A citation is a claim about the cited text, and a relay brief is a different
source from the record it says it relays. Before citing comment N for a
ruling, fetch N and list which parts of the ruling it holds; cite the relay
for the rest. A residual grep for the comment id cannot catch this: every hit
looks correct.

## Session Errors

1. **`git stash list` blocked by hook (forwarded).** Recovery: re-ran without
   it. **Prevention:** already hook-enforced (`hr-never-git-stash-in-worktrees`).
2. **`lint-infra-no-human-steps.py` fails on base with 10 pre-existing hits
   (forwarded).** Recovery: judged by new hits only. **Prevention:** compare
   against `origin/main` before reading a red lint as this PR's.
3. **Plan review ran one seat; deepen-plan ran no fan-out (forwarded).**
   Recovery: disclosed in the Enhancement Summary. **Prevention:** none needed
   for a docs-only plan; disclosure is the control.
4. **CTO-ruling detail cited to a comment that does not hold it.** Recovery:
   re-cited per part. **Prevention:** plan sharp-edges bullet, filed as #12851 (this
   PR may not touch `plugins/`): fetch the cited comment and map each sub-claim before citing.
5. **Runbook "Cleanup status: pending" twin left unmarked.** Recovery:
   appended Superseded marker. **Prevention:** existing work-skill rule
   ("PROPAGATED is a measurement"): grep the claim's subject (`pending`,
   `closes #10479`) across every touched file, not only the legal file.
6. **Durable-path template retyped and doubled `analytics-`.** Recovery:
   replaced with a pointer to the Handoff step 2 loop. **Prevention:** point at
   the code that writes a path; never restate its naming.
7. **Comment ids inserted into a CLO-ruled verbatim sentence.** Recovery: CLO
   restored the sentence and moved the ids to a second sentence.
   **Prevention:** existing append-only rule; a ruled sentence is a verbatim
   record, so annotate beside it, never inside it.
8. **Stop hook flagged a first-person promise.** Recovery: end turns with a
   "Paused:" line. **Prevention:** already hook-enforced.
9. **`check-tc-document-sha.sh` invoked at the wrong path (rc=127).**
   Recovery: `git ls-files | grep` found `apps/web-platform/scripts/`.
   **Prevention:** resolve a script's path with `git ls-files` before calling
   it; rc=127 is not a lint result.
10. **Plan AC6/AC10 wording drifted from shipped counts.** Recovery: QA re-ran
    every AC by command and amended the two lines. **Prevention:** existing QA
    rule: tick an AC only by running its command.
11. **Pre-existing `cloud-init-user-data-size` failure with terraform
    installed.** Recovery: filed #12850 (CI skips the case). **Prevention:**
    `wg-when-tests-fail-and-are-confirmed-pre` filing, done.

## Tags

category: workflow-issues
module: knowledge-base records
