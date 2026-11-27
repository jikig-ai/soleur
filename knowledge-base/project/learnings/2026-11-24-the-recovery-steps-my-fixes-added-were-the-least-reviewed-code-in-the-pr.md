---
title: The recovery steps my fixes added were the least-reviewed code in the PR
date: 2026-11-24
category: integration-issues
module: apps/web-platform/infra (cf-account migration)
tags: [cloudflare, migration, runbook, fail-closed, review, fix-round, parallel-agents]
issue: 12931
pr: 13019
---

# Learning: the recovery steps my fixes added were the least-reviewed code in the PR

## Problem

PR #13019 widens the Cloudflare migration's DNS gate so 26 same-value record writes can run. The 13-seat panel found
no input that admits a wrong DNS value. Its one P1 was in **recovery**: a failed re-read told the operator a record might
hold a wrong value and sent them to the wrong emergency steps.

The fixes for that class then produced the next round's findings, all in new recovery text and commands:

- The owner's first-write decision check treated a failed GitHub read as "this comment does not count". It fell through
  to an older comment, so a withdrawn `accept-unobserved` could read as current after one 503.
- A refusal named the correct Halt bullet and then ended with a fixed sentence telling the operator to re-dispatch, which
  the bullet forbids.
- The new restore command sent a one-field PATCH. Cloudflare's published schema marks `name`, `ttl` and `type` required, so
  the command written for the worst moment might have returned 400 at that moment. Live behavior is still unverified.
- An empty DNS snapshot compared equal to an empty baseline and would have posted `dns-answers=ok` having checked nothing.

## Solution

- One helper, `halt_pointer`, builds the Halt pointer for every post-write refusal, and the fix-forward sentence prints only
  when the re-read found nothing wrong.
- Decision reads hold on any failure except a 404. `accept-unobserved` is the only passing value; `unreadable`, `edited`,
  `observe-first` and empty all hold.
- The restore block reads the pinned record first, sends the schema-required fields plus the one changed field, and compares
  all eight fields with a separate GET.
- Snapshots are complete only at exactly 19 rows with no `NO-VERDICT`, and the baseline is saved once.
- The runbook's executable blocks are now extracted verbatim and run against stub `doppler`, `curl` and `gh` in
  `tests/scripts/test-cf-account-migration-runbook.sh`, with one mutation per guard.

## Key Insight

A runbook command is production code that runs only during an incident, so nothing exercises it before the moment it
matters. Three questions find most of these defects:

1. **What does this step do when its own read fails?** "Could not read" must never collapse into "nothing there", because
   a loop then moves on to an older answer.
2. **Does the message's last sentence still hold in every branch that reaches it?** A correct pointer followed by a fixed
   tail gives the operator two instructions.
3. **What does a zero-row input compare as?** Two empty files are identical.

## Session Errors

1. **The planner's 280 s timeout read as 19 job-suite failures.** Recovery: reran uncapped, 172 passed. **Prevention:** read the suite's registered timeout before capping it.
2. **`technical-ruling-gate` rejected a class spelling.** Recovery: used `operator (production-mutating)`. **Prevention:** copy the class from an existing row.
3. **markdownlint reported two MD038 issues in the plan.** Recovery: fixed inline. **Prevention:** none needed; the hook caught it.
4. **`lint-encryption-posture.py` takes no plan path, so the plan's section was not linted.** Recovery: recorded the gap. **Prevention:** do not cite that lint as covering a plan.
5. **The first PATCH could not be observed, because the brief forbids the provider write.** Recovery: the decision is an owner token on #12931. **Prevention:** state an unobservable first write as an owner decision in the plan.
6. **The collision pre-check exited 10 on draft PR #12958.** Recovery: confirmed no shared files. **Prevention:** none needed; the check is meant to surface this for a read.
7. **`mcp__playwright` failed because Chrome is missing at `/opt/google/chrome/chrome`.** Recovery: used `mcp__plugin_soleur_playwright__*`. **Prevention:** prefer the plugin registration on this host.
8. **The bootstrap hook refused `prev-0a` under `bypassPermissions` and `auto`.** Recovery: the owner switched to default mode. **Prevention:** state the required permission mode before a production bootstrap stage.
9. **Rehearsal 45081671772 refused all 26 DNS imports.** Recovery: this PR. **Prevention:** a provider Read that fills an attribute only when already set breaks a pure-no-op import rule, so check the provider's Read before ratifying one.
10. **The `zone-rest --staged` probe was inconclusive (deny control got 400 err 6007).** Recovery: CTO ruling for a later PR. **Prevention:** a probe's deny control must be shown to deny on that exact endpoint.
11. **`lint-bot-statuses` failed on the decision ledger in CI.** Recovery: reworded the row. **Prevention:** none needed; CI caught it.
12. **Fix commits introduced the defects above.** Recovery: a targeted re-review and a verification seat. **Prevention:** grade new recovery steps with the three questions above before the re-review.
13. **Fix agents could not run `grep` in their worktrees, so `grep-q-pipe-guard` went red after combining patches, twice.** Recovery: the lead ran the repo-wide ratchets on the combined tree and added exempt rows. **Prevention:** a fix brief names each repo-wide ratchet, and the lead runs them before committing.
14. **A ruling's snippet was pasted into the runbook with its failure path unexamined.** Recovery: replaced with a block that holds on any read failure. **Prevention:** a ruling settles the decision; its example code still gets the failed-read question.
15. **A session summary said the PR body was written, but it was still the placeholder.** Recovery: the QA acceptance read caught it. **Prevention:** read remote state back rather than trusting a summary across a compaction.
16. **`gh run view --log-failed` returned an error while the run was in progress.** Recovery: read it after completion. **Prevention:** check the run's status first.
17. **Review seats cannot save report files.** Recovery: the lead extracted each final message to `/var/tmp`. **Prevention:** do not rely on a seat-written file; persist the report from its returned message.
18. **The new `workflow_run` alert had no row in the merge-effect classifier, and only the full CI run on the ready head showed it.** Recovery: added a `ci-only` row with its reason. **Prevention:** when a PR adds a workflow file, run `plugins/soleur/test/merge-effect-class-parity.test.sh` before marking it ready.

## Tags

category: integration-issues
module: apps/web-platform/infra
