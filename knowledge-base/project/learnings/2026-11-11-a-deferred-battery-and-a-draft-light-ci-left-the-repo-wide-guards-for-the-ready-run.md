---
title: A deferred battery and a draft-light CI left the repo-wide guards for the ready run
date: 2026-11-11
category: workflow-issues
module: soleur-ship
tags: [ship, ci, merge-queue, review-seats, repo-wide-guards]
related_pr: 12518
---

# Learning: a deferred battery and a draft-light CI left the repo-wide guards for the ready run

## Problem

PR #12518 added a new test-path file family: a bash suite, shell libs, a python helper, a Node stub and a policy test, all under `apps/web-platform/test/infra/egress-injector-spike/`. No full battery ran over those files before ready:

- the local affected battery was budget-deferred (rc 6, `AFFECTED_GATE reason=budget-deferred`);
- CI was draft-light, so the heavy jobs (test-webplat, test-scripts) ran only on the ready run.

Eight repo-wide guards fired on the new files. Each walks every tracked file rather than the diff:

- web-platform `tsc` (test-webplat): a test header type was too narrow for a repeated header;
- the Supabase-endpoint lint (`lint-bot-statuses`): `UNPINNED-HOST` on a suite whose only mention of the token is an `env -u` that strips it;
- the orphan-suite lint (`lint-bot-statuses`): it did not recognise a `run: exec bash <suite>` registration;
- the fixture-relative ratchet: 129 new rows for the spike shell libs;
- fixture-env adoption: the stub's `git http-backend` spawn;
- the ruff ratchet: S112 on a silent `continue` in `iron-audit.py`'s parse loop;
- repo-wide containment: it read URL-path `../` fixture strings as the suite escaping the app;
- the grep-q pipe guard: three `| grep -q` sites.

Two of them were not left for ready. `lint-bot-statuses` runs on draft pushes too, and the orphan-suite lint was already red on the draft runs (42875067859 at 18:25Z, 42886706497 at 19:34Z). Nobody read it, because a draft's `test` check is red by design and the red check-set looked normal.

After ready (20:18:39Z) four heads were red, each failing one to three jobs (runs 42894023716, 42894985148 and 42899478000 cancelled, 42903539566 completed red), and four fix commits followed before the head went green on 1af1ec063d (run 42912205390). CodeQL was also red with five test-only alerts that no review round had triaged.

Two further process failures followed:

- **A review seat hung.** A fix-round seat briefed to "verify with the battery" sat about 3 hours inside a mutation run and delivered nothing. A respawn with a read-only brief capped at 25 tool calls reported in under 2 minutes.
- **The PR entered the merge queue past its evidence head.** It was enqueued at 22:54Z with the four CI-guard fix commits unreviewed. The queue builds one entry at a time (`max_entries_to_build = 1`) and it merged at 04:26Z, about 5.5 h later. Leaving and re-entering would have put it at the back, so evidence for 1af1ec063d was posted while it was queued (00:04Z) and the P3 findings were fixed forward in #12633. The same gap had already let #12619 merge 7d20e7c1a6, a P1 review-fix commit pushed after its only evidence comment (`head=0127b5dc45`): ship's arm check counted `Review-Evidence:` comments and never compared heads.

## Solution

- Each guard was fixed at its cause: a type widening, a dated non-caller allowlist entry, an `exec` prefix accepted on both workflow surfaces, a baseline regen, a classifier-boundary DEFERRED entry, a counted skip instead of a silent `continue`, built-not-written traversal fixtures, and `grep ... >/dev/null`. Every fix was verified with its own suite locally, and the spike re-ran GO on run 42912205717.
- A correction to the record: the message of `de0624d3d4` says the 129 baseline rows are "all rooted at SPIKE_WORK". 118 are (`lib/arms.sh` 89, `lib/bringup.sh` 13, `lib/harness.sh` 16); the 11 in `probes/session-up.sh` are rooted at `$S`, the session directory passed as its first argument.
- Guidance went to the references the failures route to: `ship/references/ready-run-wait.md` (run the repo-wide guards before `gh pr ready`), `review/references/risk-tier-and-fix-rounds.md` (bounded fix-round seats), and `review/references/review-evidence-comment.md` (a new arm check that ship's arm and CI-fix re-arm and merge-pr's merge gate run: the latest full, zero-P1/P2 evidence comment must be an ancestor of the PR head with no non-merge commit on the first-parent line between them). The same gap had already merged #12619 with an unreviewed P1 review-fix commit after its evidence head.

## Key Insight

"CI is the gate" is true only from the run that executes the full battery. On a draft-light pipeline with a deferred local battery, that run is the ready run, and a new file family pays for each repo-wide guard it trips there. The cheap lints do run on drafts, but their red hides behind a `test` that is red on purpose. Both halves are enumerable: read every red job other than `test` on the draft run, and run the heavy guards by name before ready.

## Session Errors

1. **A commit ran in the same Bash call as an `export`, so the staging guard blocked it.** Recovery: ran `git add` and `git commit` as separate calls. **Prevention:** already hook-enforced.
2. **The orphan-suite lint was red on the draft runs and nobody read it; the heavy guards first fired at ready.** Recovery: fixed each at its cause. **Prevention:** the `ready-run-wait.md` section.
3. **CodeQL's five alerts went untriaged.** Recovery: dismissed all five as "used in tests", each with a reason. **Prevention:** the same section reads the open alerts before ready.
4. **A fix-round seat hung about 3 h in a mutation battery.** Recovery: stopped it and respawned with a read-only brief. **Prevention:** the `risk-tier-and-fix-rounds.md` bullet.
5. **The PR entered the queue past its evidence head.** Recovery: posted fresh evidence while queued and fixed the P3s forward in #12633. **Prevention:** the arm check in `review-evidence-comment.md` refuses any non-merge commit after the evidence head; a main-sync merge still passes.
6. **A `run_in_background` poll was blocked by a hook.** Recovery: used Monitor. **Prevention:** already hook-enforced (`hr-monitor-not-run-in-background-for-polling`).
7. **`cat` on a seat's output file dumped 800 KB.** Recovery: read the transcript with `jq`. **Prevention:** already in `review/SKILL.md` (read a seat's last assistant text with `jq`, never `Read` or `tail` the JSONL).
8. **A CTO brief said two devDependencies; there are three.** Recovery: the CTO's ruling corrected it. **Prevention:** already covered by the "brief facts must cite where they were read" paragraph #12518 added to `technical-ruling-delegation.md`.
9. **(#12633 review) A scripted cut-to-end-of-file removed a reference's trailing "See also" section.** Recovery: the diff showed five deletions where one bullet was expected; restored from the merge base and re-applied. **Prevention:** already in `risk-tier-and-fix-rounds.md` (read the DELETED lines of the lead's own splice).
10. **(#12633 review) The arm-check text pushed ship SKILL.md 216 bytes over its body ceiling.** Recovery: kept the command in the reference and trimmed the pointers. **Prevention:** already lint-enforced (`scripts/lint-skill-body-budget.py`).
11. **(#12633 review) The new CodeQL alert read tripped the #8593 unbounded-enumeration gate.** Recovery: `--paginate` with `per_page=100`. **Prevention:** already test-enforced (`components.test.ts`).
12. **(#12633 review) A follow-up `gh issue create` lacked a milestone and filing exit.** Recovery: re-filed as #12656 with both. **Prevention:** already hook-enforced.
13. **(#12633 review) This learning's first draft claimed the arm-check fix before it existed.** Recovery: the CTO ruled, and the check was written, dry-run against #12619 and #12518, and wired into ship and merge-pr. **Prevention:** the fix itself; the review skill's "check every claim the diff's prose asserts" paragraph already names the class.
14. **(#12633 ship) The first arm check filtered for passing comments before taking the latest, and pinned no head at arm time.** A newer failing review would have been skipped in favour of an older passing one. Found by the ship Phase 5.5 advisor consult, not by the five-seat review or the CTO ruling. Recovery: the check now takes the latest `Review-Evidence:` comment first, then tests its fields, and arms with `--match-head-commit "$H"`; jq cases (newer failing, degraded latest, none) all leave `EV` empty. **Prevention:** a gate that selects "the latest X that passes" answers "did a pass ever exist"; select the latest X, then test it.
15. **(#12633 ship) "Run the check without its last line, then the lock block" armed with no evidence.** Dropping the last line left a trailing `\`, so the lock block's first line joined the check's last test, and nothing gated the lock block on the check's exit code. Found by the fix-round seat with a stubbed gh/git. Recovery: the check is now its own statement ending `|| { echo "ARM_CHECK refused…"; exit 1; }`, and the lock blocks use `${H:?…}`; a stub test of the composed call refuses in all six refusal cases and arms in the passing one. **Prevention:** never tell an agent to edit a gate by deleting part of it; publish a check that exits on refusal so concatenation is safe.
