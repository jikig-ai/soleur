---
title: "chore(registry): correct the restore job's operator strings in the apply workflow (#11667 item 2b)"
date: 2026-11-02
slug: workflow-exit-arm-strings-11667
branch: feat-one-shot-11667-workflow-exit-arm-strings
issue: 11667
type: chore
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-11-02
**Gates run inline (all pass):** 4.6 user-brand (threshold `none` plus the sensitive-path scope-out bullet, because `.github/workflows/apply-web-platform-infra.yml` matches the canonical regex), 4.7 observability (probe rewritten, see below), 4.8 PAT sweep (no hit), 4.11 guard contract (`lint-guard-contract.py` green, assembly structural), 4.12 scope check (one unfenced section, no `BLOCKED` marker). Not triggered: 4.4 precedent-diff (no pattern-bound behaviour), 4.45 grep passes (the negative claims were verified by script in the census), 4.5 network outage, 4.55 downtime (no downtime-inducing operation; the push apply run is a no-op on infrastructure), 4.9 UI, 4.10 encryption (no store or connection added; the plan only names the registry store), 4.13 task design (no new autonomous task).
**Research agents used:** `soleur:engineering:cto` (binding rulings, twice), `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer` (plan-review panel), `soleur:engineering:review:test-design-reviewer`, `soleur:engineering:research:learnings-researcher`. The full "run every discovered agent" fan-out was NOT run: the change is eight strings and one pin, so the panel was scoped to the agents whose lens can change the diff.

### Key improvements from review and deepen
1. R4 (Doppler abort) no longer claims the store is "EMPTY or only partly refilled": the step fires before any engine call, so it now says only that nothing was written (CTO re-ruling).
2. R6 (exit-4 runbook pointer) and the job-rationale runbook sentence were cut; the W9 pin shrank to the exit-6 arm with one permanent control. Net is now -63 bytes with a 383-byte margin (was -35 / 355).
3. The observability probe was rewritten from a `bun test` suite command (suite-shaped, rejected by the Check 10 rules) to a one-grep literal check.
4. Cited push runs resolved live: the push apply runs for `e0af599081` (#11787), `32b7ee7d78` (#11785) and `b9deac6de5` (#11815) all concluded `success`; `gh run list --workflow apply-web-platform-infra.yml --branch main --event push`.

## Overview

Item 2b of tracker #11667: the operator-facing strings of the chained restore job in `.github/workflows/apply-web-platform-infra.yml` still describe an engine that no longer exists. The engine (PR #11813, merge `508922e7bcec3ae321852acb51e40200b58810cb`) now exits 6 for an unclassified read fault that used to exit 4, and the job retries only exit 3. Six workflow strings say otherwise, one code comment makes a claim that is false for exit 6, and the exit-5 arm lacks the "unchanged" qualifier the engine header and runbook already carry.

The operator lifted the standing workflow-edit constraint for this one item on 2026-11-02 ("go ahead on 2b") and with it authorized the production push-apply run the edit triggers. The edit is net-negative in bytes (**-63**, 489,680 to 489,617 of 490,000) and ships as ONE PR with `Ref #11667` and `Ref #9757` only. Nothing in this plan closes #11667; the operator closes it.

**Does merging this alone mutate production?** It fires the push-triggered `apply` run (the workflow file is in its own `paths:` filter). No `.tf` file changes, so the expected plan is empty or pre-existing drift only; `registry_luks_recut`, `registry_pull_path_gate` and `registry_store_restore` are all skipped on push. Details under "Apply-trigger plan". The PR body's first line states this.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality on this branch | Plan response |
|---|---|---|
| File is 489,680 of 490,000 bytes | Confirmed: `wc -c` on the worktree and on `git show origin/main:` both give **489,680** (origin/main `3035aee068`; the branch adds only a `chore: initialize` commit). The archived plan's 488,896 is stale. | All deltas below are measured against 489,680; re-measure at implementation start and end. |
| Anchors R1-R8 sit at the archived plan's line numbers (3471, 3490, 3492, 3588, 3634, 3639...) | Drifted by about +9 (the file gained lines from #11815 and #11785): the same strings now sit at 3480, 3499, 3501, 3597, 3643, 3648. | Every anchor is cited by its exact content; lines in parentheses are orientation only (`cq-cite-content-anchor-not-line-number`). |
| Comment near 3605 reads "Every other code is a fault that a retry cannot clear" | The comment is at 3614-3615 and reads "Only exit 3 retries. Every other code is a source, correctness, authorisation or invocation fault that a retry cannot clear — retrying them would only burn the window." False for exit 6 (unclassified) and doubtful for exit 2 (a GHCR read fault). | Rewritten (anchor CMT). |
| Exit-5 arm's "retrying will not clear it" is stale | Confirmed at line 3646; the arm itself says a local login failure points at tooling, so the unqualified claim is wrong. Engine header row 5 and runbook row 5 already say "not retryable as-is" / "unchanged". | Anchor E5 (+10). |
| R8: exit-6 arm should say "store UNVERIFIED; the job does not retry 6; re-run by hand" | Matches the engine header (exit 6 row), runbook row 6 and the ADR-169 Amendment 2026-11-01. | Anchor R8, CTO-ruled wording. |
| "There is a byte-budget guard; find it" | `plugins/soleur/test/workflow-file-size.test.ts`, constant `WORKFLOW_FILE_GATE_BYTES = 490_000`, test `no workflow file exceeds the gate` inside `describe("live .github/workflows")` (ADR-231). It enforces `size <= 490000`, NOT net-negative. | Net-negative is this plan's own acceptance criterion, checked against `origin/main`, not by that test. |
| Three other open PRs touch the workflow (#10928 draft, #10678, #7390) | Confirmed, read-only via `gh api .../pulls/N/files`: #10928 net -132 B (hunks near 857, 984, 4195, 6075), #10678 +62 B (near 518), #7390 +604 B (near 5944). None touches the 3440-3650 region. | Merge-order note below; nothing on those PRs is edited or commented. |
| "registry_store_restore / registry_luks_recut jobs do not run on push" | Verified in the file: `registry_luks_recut` (`if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'registry-luks-recut'`) and `registry_pull_path_gate` (same dispatch-only guard); `registry_store_restore` is `if: ${{ !cancelled() && needs.registry_luks_recut.outputs.store_refill_needed == 'true' }}`, and a skipped job's output is empty. | Apply-trigger plan. |
| Collision pre-check; the untracked `scripts/inngest-gate-witness-classify.sh`, the Better Stack incident `soleur-egress-gw-probe-silent-prd`, issues #11312 #11379 #10924 #11694 | Only this branch's own draft PR #11841 names #11667; the rest are unrelated. | Not touched. |

## Research Insights

### Premise Validation

Checked: #11667 OPEN, #9757 CLOSED (plain `Ref` only), PR #11813 MERGED at `508922e7bc`, PR #11841 is this branch's draft with no files, #11818 (7-day pins retention) and #11819 (NETWORK widening) still OPEN and untouched. Every anchor occurs exactly once in the file (checked by script). The runbook (`registry-luks-recut-6929.md`, rows 1-6 and "If the restore job fails") and ADR-169 Amendment 2026-11-01 already carry the corrected policy; only the workflow lags. Stale: the byte count and every workflow line number from the archived plan.

### Property List

1. A string in the restore job never claims a retry or re-run outcome the engine contract contradicts: exit 3 is the only code the job retries; exit 6 is not retried but is safe to re-run by hand once the stderr is read.
2. No string claims the store's state beyond what the code knows: a recut's refill flag is set before the apply, and the chain can run against a store that was never emptied.
3. Exit 6 and exit 4 read as different verdicts: 6 is "unverified" (the engine could not name the fault), 4 is "not trustworthy" (a copy landed wrong).
4. No string tells the operator to re-run with an input the job does not have ("a wider set").
5. The change is net-negative in bytes and the file stays under the 490,000 gate.
6. The W9 wiring suite keeps passing, and the exit-6 arm, whose safety claim ("UNVERIFIED, do not deploy") changed because the engine moved, is pinned so neither word can be dropped silently.

### Cut List

| Mechanism considered | Property | Disposition |
|---|---|---|
| R7: append "Do not deploy until a re-run exits 0." to the exit-3 arm (+38) | 3 | Cut (CTO): new behaviour rather than a correction, and cutting it preserves the byte margin. Stays on #11667 as a remaining optional item. |
| R6: exit-4 arm pointer `then runbook row 4` (+20; the unambiguous `registry-luks-recut-6929.md row 4` form is +40) | 3 | Cut (CTO, reversed after review): the bare form is ambiguous (two runbooks), the file-named form is too dear, and R2 plus the `*)` summary line already send the operator to "the runbook row for its exit code". Stays on #11667. |
| Pointer from the exit-6 arm to row 6's `crane validate --remote` discriminator (about +30) | 3 | Cut (CTO): the arm already blocks deploy ("UNVERIFIED") and R2 sends the operator to row 6. Stays on #11667. |
| Job-rationale runbook sentence (dated note beside "Why exit 1 has its own restore-step arm") | 2 | Cut (CTO, DHH and simplicity reviewers agree): that section already carries the reasoning R4 and R5 reuse; it adds a third subsystem for no requirement. |
| W9 pin for arm 4, a needle on `does not retry 6`, and `retry6`/`row4`/`reword6` permanent controls | 6 | Cut (review, CTO): arm 4 no longer changes; `does not retry 6` is wording, and W9 already asserts the behaviour (exactly one engine call for exit 6); an unmutated needle is dead weight. AC5 still greps the phrase. |
| R1 variant (a) "was rebuilt empty" (+9) | 2 | Cut (CTO): asserts a destroy that may not have happened. Replaced by "may be EMPTY" (+4). |
| Long R8 wording (+167) and short R8 wording (+51) | 3 | Cut (CTO): the long form is over budget, the short form drops "do not deploy until a re-run exits 0". |
| Rewrite "The fresh volume is luksFormatted and empty" (recut summary body) | 2 | Cut (CTO): same overclaim as the heading but costs bytes; accurate at emit time because the restore has not run. |
| Edit the exit-2 arm, the `cancelled` summary line, the `recovered by re-running` comment above `timeout-minutes` | 1 | Cut (CTO): each is accurate for its subject (see the census). |
| New lint that pins workflow wording repo-wide | 6 | Cut: W9 already machine-extracts the restore step; two extra per-code checks cover the two arms that changed. |
| A pin for the recut-summary heading and for the absence of `wider set` | 4 | Cut: W9 is scoped to the restore step; a second extraction harness for two strings is a new mechanism. |
| Relocate comment prose from the workflow to a runbook for extra byte headroom | 5 | Cut: not needed (margin 383 B); would touch test-anchored lines. |
| C4 edit to the restore edge ("resumable, so a partial pass is recovered by re-running") | 1 | Cut: narrowly true (the engine is resumable), ruled no C4 touch on 2026-11-01. |

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-11-01-not-retryable-is-a-label-not-a-determinism-claim.md`: quote the engine header's label, not the consequence inferred from it; deleting a "re-run" orphans neighbouring sentences; grep the claim's SUBJECT. Applied: R2 keeps the re-run sentence and qualifies it instead of deleting it; no string says "fails identically" for exit 4, 5 or 6.
- `knowledge-base/project/learnings/2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`: measure deltas against the merge base; a sibling merge can cross the gate.
- Plan sharp edge (`plan-sharp-edges.md`, "does merging THIS alone mutate production?"): answered in the Overview and the apply-trigger plan.
- Deepen check of R2's "re-running is safe": the engine header's preamble for codes 2-6 says "a re-run never redoes them and is safe" and row 1 wrote nothing, so the word is quoted from the contract, not inferred from a label; the sentence does not claim a re-run clears any exit.
- `knowledge-base/project/learnings/2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit-and-nothing-in-repo-said-so.md`: a file over GitHub's real limit gives `startup_failure` with zero jobs and no email; the post-merge check reads that conclusion explicitly.
- Plan sharp edge (inventory what exact-matches a line before rewriting it): the pin census below.

### Subject census (grep the claim, not the phrasing)

Searched repo-wide (`grep -rn` over the worktree, excluding `node_modules`, `.git`) for each subject's several phrasings, with the four named corpora called out.

| Subject (claim) | Workflow (this file) | Runbook `registry-luks-recut-6929.md` | ADR-169 | Tests / other | Disposition |
|---|---|---|---|---|---|
| S1 "only exit 3 retries; the others cannot be cleared by a retry" (`retry`, `retries`, `cannot clear`, `burn the window`) | comment at ~3614-3615 (CMT); exit-5 arm `retrying will not clear it` (E5); exit-1 arm "re-running this job re-downloads the SAME ... artifact and fails identically" (accurate); exit-4 arm `NOT retryable` (accurate, unchanged); `notice` line "attempt N/6 hit exit 3" (accurate) | lines ~478, ~607-610: job retries only exit 3, exits 1/4 not retryable, exit 5 only after measure-first, exit 6 not retried but safe by hand (already correct) | Amendment 2026-11-01 first bullet (already correct) | engine header `scripts/registry-restore-from-ghcr.sh` exit 3/5/6 rows (already correct); `apply-sentry-infra.yml` lines 314/828 "a retry cannot clear it" is a different subject (a curl transport) and is left alone | CMT and E5 edited; everything else already true |
| S2 "a partial pass is recovered by re-running" (`recovered by re-running`, `resumable`) | recut summary ~3499 (R2, edited); comment above `timeout-minutes` ~3516-3517 (timeouts only, accurate, left); `cancelled` summary line ~3674 (accurate for a cancellation, left, pinned by W9); R4 Doppler abort ~3597 (edited) | rows 2/3/6 and "If the restore job fails" (already qualified) | Consequences bullet amended | `model.c4` restore edge "resumable, so a partial pass is recovered by re-running" (left, ruled 2026-11-01) | R2, R4 edited |
| S3 "the store is EMPTY" (`EMPTY`, `empty`, `still EMPTY`) | heading ~3480 (R1); Doppler abort ~3597 (R4); exit-78 arm ~3648 `still EMPTY` (R5); exit-2/3 arms "EMPTY or only partly refilled" (accurate, left); line 2645 (different job, `registry_region_migrate`, accurate for a first boot, left) | "The empty-store window" section (accurate: describes the window) | amended | job-rationale runbook "Why exit 1 has its own restore-step arm" already explains why "unchanged by this step" beats "empty" | R1, R4, R5 edited |
| S4 "re-run the restore with a wider set" (`wider set`) | recut summary ~3501 (R3) | "The restore job has no wider-set input" (accurate) | Amendment bullet 3 (accurate) | `plugins/soleur/test/net-issue-flow.test.sh` line 175 matches the words but is unrelated | R3 edited |
| S5 "exit 6" (`exit 6`, `COULD NOT CLASSIFY`, `UNVERIFIED`, `does not retry`) | arm 6 ~3647 (R8); the `*)` arm text "Every exit code the restore engine emits is enumerated above" (accurate); lines 4153/4229/6024/6098 use UNVERIFIED for a different subject (host replace/birth poll) | row 6 (already correct) | Amendment (already correct) | `scripts/registry-pull-path-health.sh` line 581 A2 exit-6 arm "pass condition is unproven" (accurate, left); W9 `tests/scripts/test-registry-d10-workflow-wiring.sh` | R8 edited |
| S6 "exit 4 is NOT retryable; read the per-entry lines" | arm 4 ~3643 (accurate; the pointer to row 4 was cut, see Cut List) | row 4 (carries the two-situation discriminator) | Amendment bullet 2 | engine header exit 4 row | left |

### Tests that pin workflow strings (pin census)

- `tests/scripts/test-registry-d10-workflow-wiring.sh` (W9, 91 assertions, `EXPECTED_ASSERTIONS=91` pinned exactly). It runs the restore step's real `run:` body and the `Restore summary` body. Constraints on this edit: each case arm stays ONE line shaped `N) echo "::error::restore FAILED exit N (...)`; annotation must match `exit N([^0-9]|$)`; arms 2 and 5 must contain `failed locally`; arm 1 must contain `manifest`; arm 78 must contain `traced invocation`; an enumerated code whose annotation contains `unenumerated` (it fell to the `*)` arm) fails; the Doppler abort must contain `registry-store-restore ABORT`; the retry loop must print `::notice::restore attempt 1/`; the three summary echo lines must say `closed`/`cancelled`/`failed` as pinned; controls mutate by literal anchors (`rc=$?`, `max=6`, `case "$rc" in`, `exit "$rc"`, `78) echo`, `1) echo`, `} >> "$GITHUB_STEP_SUMMARY"`). None of the eight edits touches any of these. Verified by a feasibility probe: all eight edits applied to a scratch copy of the tree, W9 ran **91 passed, 0 failed**.
- `plugins/soleur/test/workflow-file-size.test.ts` (the byte gate; also a `# Rationale:` pointer-parity test over the same file; untouched by the edit, 9 pass at plan time).
- Structural readers of the workflow that do not pin any edited string (re-run anyway): `plugins/soleur/test/terraform-target-parity.test.ts` (job blocks for `registry_luks_recut`), `plugins/soleur/test/stock-preflight-coverage.test.ts`, `tests/scripts/test-argv-bearer-sweep.sh` (job bodies, step `Best-effort registry disk heartbeat status`), `tests/scripts/test-registry-luks-recut-gate.sh`.
- No test pins the recut-summary heading, R2, R3, R4 or R5 strings (greps for each phrase outside the workflow come back empty).

### Feasibility probe (done at plan time, scratch copy only)

A scratch ROOT was built under the session scratchpad (copies of `scripts/`, `tests/scripts/`, `.github/workflows/`, `.github/actions/`), the eight edits below applied by exact-string replace (each `old` found exactly once), and `tests/scripts/test-registry-d10-workflow-wiring.sh` run there: file 489,680 to **489,617** (-63), YAML still parses (21 jobs), W9 **91 passed, 0 failed**; the old strings (`wider set`, `recovered by re-running rather`, `still EMPTY`, `retry cannot clear`, `cannot refill it`) are gone. The worktree was not modified.

## Technical Rulings (summary)

Full rows are in `knowledge-base/project/specs/feat-one-shot-11667-workflow-exit-arm-strings/decision-challenges.md`. Spawned `soleur:engineering:cto` before drafting and again after the plan-review panel (no operator technical question was asked).

- Ruled by CTO agent, 2026-11-02: R1 variant "may be EMPTY" (+4) - true whether or not the apply destroyed anything.
- Ruled by CTO agent, 2026-11-02: cut R7 and (after review) R6 - R7 is new behaviour; R6's bare "runbook row 4" is ambiguous and the file-named form is too dear.
- Ruled by CTO agent, 2026-11-02: R8 wording keeps "do not deploy until a re-run exits 0" (+89), no extra discriminator pointer - exit 6 means unverified.
- Ruled by CTO agent, 2026-11-02: R4 becomes `Nothing was written; the store is unchanged by this step. ...` (-26) - the Doppler abort fires before any engine call, so the step only knows it wrote nothing.
- Ruled by CTO agent, 2026-11-02: CMT in its second variant (-25) and E5 (+10) included; exit-2 arm, `cancelled` line and timeout comment untouched.
- Ruled by CTO agent, 2026-11-02: no kill switch, never cancel an in-flight apply, whoever merges second carries the byte burden, no ADR/C4/runbook changes (the job-rationale sentence is cut), W9 pins shrunk to arm 6.

## Edits to `.github/workflows/apply-web-platform-infra.yml`

Anchors are exact current text, each occurring once. "Bytes" is `len(new.encode()) - len(old.encode())` measured by script on the real file. Lines in parentheses are orientation only.

| # | Anchor (old, exact) | New | Bytes |
|---|---|---|---|
| R1 (3480) | `echo "### The store is EMPTY — the chained restore runs next"` | `echo "### The store may be EMPTY — the chained restore runs next"` | +4 |
| R2 (3499) | `If the restore job fails, re-run it: the restore engine is resumable, so a partial pass is recovered by re-running rather than by repairing state. Its per-exit-code \`::error::\` maps to one operator action each in the runbook.` | `If the restore job fails, follow the runbook row for its exit code: re-running is safe (the engine is resumable) but only some exits can be cleared by it.` | -73 |
| R3 (3501) | `...no older image in the store to roll back to; re-run the restore with a wider set if you need one._` | `...no older image in the store to roll back to._` (old substring `; re-run the restore with a wider set if you need one._` becomes `._`) | -53 |
| R4 (3597) | `The store is EMPTY and this job cannot refill it. Fix the credential and re-run this job — the restore engine is resumable.` | `Nothing was written; the store is unchanged by this step. Fix the credential, then re-run this job.` | -26 |
| CMT (3614-3615) | two lines: `          # Only exit 3 retries. Every other code is a source, correctness, authorisation or invocation fault that a` / `          # retry cannot clear — retrying them would only burn the window.` | two lines: `          # Only exit 3 retries (policy); the loop does not retry the other codes.` / `          # Exit 6 is unclassified: re-run it by hand after reading the crane stderr.` | -25 |
| E5 (3646) | exit-5 arm `and retrying will not clear it.` | `and retrying unchanged will not clear it.` | +10 |
| R8 (3647) | exit-6 arm tail `the engine hit a failure it could not name. Read the crane stderr in the per-entry line above before acting; do not assume the images are absent."` | `the engine hit a failure it could not name; store UNVERIFIED, do not deploy until a re-run exits 0. Read the crane stderr in the per-entry line above, do not assume the images are absent, then re-run by hand: the job does not retry 6."` | +89 |
| R5 (3648) | exit-78 arm `so this attempt wrote nothing and the store is still EMPTY.` | `so this attempt wrote nothing and the store is unchanged by this step.` | +11 |
| R6, R7 | exit-4 arm pointer; exit-3 arm "Do not deploy until..." | NOT APPLIED (cut, see Cut List) | 0 |

**Net: +4 -73 -53 -26 -25 +10 +89 +11 = -63 bytes.** File: 489,680 to **489,617** of 490,000 (headroom 383). The implementer re-measures with `wc -c` before and after; if the real figure exceeds 489,650, drop E5 first (CTO).

## Byte-budget guard

- Enforcer: `plugins/soleur/test/workflow-file-size.test.ts`, `describe("live .github/workflows")` > `test("no workflow file exceeds the gate")`, constant `WORKFLOW_FILE_GATE_BYTES = 490_000` (GitHub's own limit is 512,000, `GATE_HEADROOM_BYTES = 20_000`). Run: `bun test plugins/soleur/test/workflow-file-size.test.ts` (9 pass at plan time). Rationale: ADR-231; the workflow's file header also names it.
- That test passes at any size up to 490,000, so it cannot enforce "net-negative". Net-negative is this plan's acceptance criterion AC1, measured as `wc -c` of the branch file strictly below `git show origin/main:.github/workflows/apply-web-platform-infra.yml | wc -c`.

## Apply-trigger plan

**What the push apply run does.** The workflow's `on.push` (branches `[main]`, `paths` includes the workflow file itself) fires on the squash merge. Jobs that run on push: `preflight` (kill-switch check) and `apply` (init, allow-listed plan, pre-apply entrypoint gate, terraform apply of the non-SSH set, tunnel/origin checks, Doppler CI-token sync, then the CF-tunnel-bridged SSH apply of the SSH-provisioned resources and the heartbeat-arm steps), plus the failure-notification step that only acts when `apply` fails. No `.tf` file changes, so the expected plan is empty (or shows only drift that already existed). Same precedent, resolved live with `gh run list --workflow apply-web-platform-infra.yml --branch main --event push`: the push runs for `e0af599081` (#11787), `32b7ee7d78` (#11785) and `b9deac6de5` (#11815) all concluded `success`.

**Why the restore and recut do not run on push.** Verified in the file: `registry_luks_recut` is `if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'registry-luks-recut'`; `registry_pull_path_gate` has the same dispatch-only guard; `registry_store_restore` is `if: ${{ !cancelled() && needs.registry_luks_recut.outputs.store_refill_needed == 'true' }}` and a skipped job's output is empty, so the comparison is false. No recut, pull-path gate or restore is dispatched by this PR or by any step of this plan; the strings it edits only render on a real recut.

**Other workflows.** A YAML parse of every `.github/workflows/*.yml` shows only `apply-web-platform-infra.yml` (push to main) and `infra-validation.yml` (pull_request) list this file in their `paths:`. No second apply workflow fires.

**Before merging.**
1. `gh run list --workflow apply-web-platform-infra.yml --status in_progress` and `--status queued`: if an apply or a recut is running, wait. Never cancel it (`cancel-in-progress: false` is deliberate: a half-applied lockless-R2 run is the worst split state).
2. The PR title, body and squash message must not contain a line that is exactly `[skip-web-platform-apply]`. The kill switch is NOT used: the operator authorized the push run, and the run proves the file still starts and the apply is clean.
3. CI on the PR green, including `workflow-file-size`, the W9 suite and `infra-validation`.

**How to verify the push run succeeded post-merge** (template: the #11787 tracker verification):
1. `gh run list --workflow apply-web-platform-infra.yml --branch main --limit 5`, find the run for the merge commit (a `startup_failure` conclusion with zero jobs means GitHub refused the file, e.g. over its real 512,000-byte limit; it sends no failure email), then `gh run view <id> --json jobs --jq '.jobs[]|[.name,.conclusion]'`: `preflight` and `apply` are `success`; `registry_luks_recut`, `registry_pull_path_gate` and `registry_store_restore` are `skipped`; the failure-notification job is `skipped` or `success`.
2. Read the apply plan summary: no destroy HALT and no unexpected diff. A pre-existing drift failure is not ours; handle it by the workflow's own unwedge route, not as a regression.
3. `git show origin/main:.github/workflows/apply-web-platform-infra.yml | wc -c` is 489,617 (strictly below 489,680 and below 490,000); each new string appears exactly once and each old string zero times (`wider set`, `recovered by re-running rather than`, `still EMPTY`, `retry cannot clear`, `cannot refill it`).
4. CI on main green; `/health` ok; no new `ci/` issue since the merge (the older Better Stack incident `soleur-egress-gw-probe-silent-prd` is unrelated and is left alone).
5. Comment the evidence on #11667 (the tracker stays open; the PR uses `Ref`, never a closing keyword). No recut or restore dispatch.

## Merge-order and byte-budget risk (read-only awareness)

- #10928 (draft, net -132 B against its base), #10678 (+62 B), #7390 (+604 B) all edit the same file; none edits lines 3440-3650, so textual conflicts are unlikely. CI runs on each PR head, not on the merge result, so a cumulative overage would first show up as a red `main`.
- Whoever merges second updates to `main`, re-measures with `wc -c` and the size test, and re-checks anchors for exactly-once. If this PR merges first, #7390 alone would take the file to about 490,221 (over the gate), so it must offset about 220 bytes itself. This PR does not trim extra bytes to reserve room and does not touch the gate constants (two constants would have to change anyway).
- No action on those PRs (no edit, no comment).

## Implementation Phases

Order follows `cq-write-failing-tests-before`: the pin first (RED), the workflow edit second (GREEN).

### Phase 0: re-measure

`git fetch origin main`; confirm `git show origin/main:.github/workflows/apply-web-platform-infra.yml | wc -c` and the worktree file are still 489,680; if main moved, re-count each anchor (`grep -c`, must be 1) and recompute the byte table before editing. Record the starting figure.

### Phase 1: RED pin in the W9 suite

File: `tests/scripts/test-registry-d10-workflow-wiring.sh`. Inside the per-code `case "$code" in` block of `w9_check` (beside the `2|5`, `1`, `78` checks) add a `6)` check on the annotation line (`$line`, already the exit-6 `::error::restore FAILED` line, so it cannot be satisfied by exit 4's "Do not deploy"): `grep -qiF 'unverified'` and `grep -qF 'do not deploy'` (the second case-sensitive, lowercase, matching the arm text), each with its own `w9_add` message carrying the literal lowercase needle (`... does not say unverified`, `... does not say do not deploy`). Add two permanent refusal controls to the `for w9_c in ...` list, `unv6|unverified` and `nodeploy|do not deploy`, with matching `elif k == ...` branches in `W9_PY` that find the arm with `re.search(r'\n( *6\) echo [^\n]*)', seg)` (template: the `manifest` branch) and remove the phrase with `re.sub` (`(?i)unverified` replaced by `unchecked`, so no `unverified` remains in the arm; `do not deploy` replaced by `proceed`), each guarded by `once(...)` so a mutation that did not land cannot slip through. Raise `EXPECTED_ASSERTIONS` from 91 to **93** (two controls, one report each). Run the suite against the UNCHANGED workflow: the main W9 row and the `unv6` control (the "mutation landed" report) fail because the arm lacks `UNVERIFIED` and `do not deploy` is absent from the old arm text; record the run as RED evidence. W9 runs as one shell suite that stubs the engine and runs the real step body, so it is a single layer (no unit/integration labels).

### Phase 2: workflow edit (GREEN)

File: `.github/workflows/apply-web-platform-infra.yml`. Apply the eight edits in the table with the Edit tool, one per anchor (each `old_string` unique). Do not touch the three Restore-summary echo lines, the exit-1/2/3/4 arms, the `*)` arm, or any `# Rationale:` pointer line. Re-measure: `wc -c` must read 489,617 (at most 489,650), strictly below the Phase 0 figure.

### Phase 3: verification

1. `bash tests/scripts/test-registry-d10-workflow-wiring.sh` (93 passed, 0 failed).
2. One-off scratch mutations on a copy, not permanent controls (record the output): the `6)` label neutered in the suite (`66)`) must make the `unv6` and `nodeploy` controls report `expected a refusal naming '...', got: <nothing>`; arm 6 reworded in a different order and case, same facts, must be accepted; arm 6 without `the job does not retry 6` is NOT caught by W9 (by design, see Cut List) and is covered by AC5's grep.
3. `bun test plugins/soleur/test/workflow-file-size.test.ts`.
4. `python3 -I -c "import yaml;yaml.safe_load(open('.github/workflows/apply-web-platform-infra.yml'))"`.
5. `bun test plugins/soleur/test/terraform-target-parity.test.ts plugins/soleur/test/stock-preflight-coverage.test.ts`; `bash tests/scripts/test-argv-bearer-sweep.sh`; `bash tests/scripts/test-registry-luks-recut-gate.sh`.
6. `git diff origin/main --stat` shows only the two planned files plus planning artifacts.

### Phase 4: ship

One PR (#11841). PR body first line: "Merging fires the push-triggered apply run (no `.tf` change; recut/restore jobs are skipped on push)". Body uses `Ref #11667` and `Ref #9757` only, no closing-keyword wording in any form, no `[skip-web-platform-apply]` line. `semver:patch`. Post-merge: run the verification checklist above and comment on #11667.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` (eight edits, net -63 B)
- `tests/scripts/test-registry-d10-workflow-wiring.sh` (one `6)` check with two needles, `unv6` and `nodeploy` controls, assertion floor 91 to 93)

## Files to Create

- None in the product tree. Planning artifacts only: `knowledge-base/project/specs/feat-one-shot-11667-workflow-exit-arm-strings/{tasks.md,decision-challenges.md}`.

## Open Code-Review Overlap

None. Queried open `code-review` issues for the files in Files to Edit (and the job-rationale runbook that was considered and cut); no body names any of them.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: operator-facing wording in an infrastructure workflow, no UI surface, no regulated-data surface, no new infrastructure, no architectural decision (the policy these strings now match is already recorded in ADR-169 Amendment 2026-11-01, so no ADR or C4 change; nothing is added or moved, and the restore-edge text "resumable, so a partial pass is recovered by re-running" is narrowly true and was ruled left on 2026-11-01).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The strings render only to an operator on a post-destroy restore failure; a wrong string could send the operator to deploy against an unverified registry store or to re-run a job that cannot clear the fault.
- **If this leaks, the user's data is exposed via:** no exposure vector; the strings contain no secrets and no new data path.
- **Brand-survival threshold:** none
- **Threshold decision (challengeable):** none, because no end-user-facing artifact changes and the production push-apply run is a no-op on infrastructure (no `.tf` change); a mistake costs operator time during an incident, not user data.

`threshold: none, reason: the touched path is a workflow whose edited text is operator-only console output; the push apply run applies no infrastructure change and the destructive jobs are dispatch-only.`

## Guard Contract

### Guard 1 — W9 pin for the exit-6 arm

**Property.** The restore step's exit-6 annotation says the store is UNVERIFIED and says not to deploy, so a future engine change cannot leave the arm that carries the "do not deploy" safety claim contradicting the contract unnoticed.

**Assembly.** The arm is extracted from the real `run:` body of the `Restore production's pinned image set from GHCR` step in job `registry_store_restore` (PyYAML extraction W9 already uses) and observed by running that body with the engine stubbed to exit 6; the chokepoint is the per-code loop in `w9_check`, and the needles are matched against the exit-6 annotation line only (`$line`), never against the whole output, so exit 4's own "Do not deploy" cannot satisfy them. The new check sits in the same `case "$code"` as the `2|5`, `1` and `78` checks, so a seventh code added to the engine header still falls to the existing "fell to the `*)` arm" check; the wording needles cover code 6 only, by design.

**Mutation matrix.** Rows 1-2 are permanent controls; rows 3-5 are one-off scratch-mutation checks run at work time (Phase 3, step 2) and are not counted in the assertion floor.

| # | Mutation (must turn the suite RED unless marked must-PASS) | Expected result |
|---|---|---|
| 1 | Arm 6 loses the word `UNVERIFIED` (permanent control `unv6`) | refused, message names `unverified` |
| 2 | Arm 6 loses `do not deploy` while arm 4 still says "Do not deploy" (permanent control `nodeploy`) | refused, message names `do not deploy` |
| 3 | Arm 1 loses `manifest` while arm 6 stays compliant (existing control `manifest`; proves the loop does not stop at the first compliant member) | refused, `does not name the manifest fault` |
| 4 | Own dispatch: the `6)` case label is neutered in the suite (`66)`), so no check runs for code 6 | both controls report `expected a refusal naming '...', got: <nothing>` and the suite reds (harness row) |
| 5 | Arm 6 reworded in a different order and case with the same facts (must-PASS, not the canonical) | accepted |

**Harness rows.** Row 4 edits the suite, not the guard; row 5 is a must-PASS input differing from the canonical in a way the contract permits, so a check that rejects everything is also caught. `EXPECTED_ASSERTIONS` is pinned exactly (91 to 93), so silencing a control also reds.

**Anchor.** The pinned needles and the arm text live in the same repository, so one diff can weaken both; this guard proves consistency, not integrity. The independent anchors are the engine header (`restore_header_codes` against the die/exit sites, already compared by W9), runbook row 6 and ADR-169 Amendment 2026-11-01, which a reviewer reads alongside the diff, and the exact assertion count that moves in the same diff.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Item 2b of #11667 (workflow strings in .github/workflows/apply-web-platform-infra.yml)" [brief] | Edits R1-R5, R8, CMT, E5 | mapped |
| 2 | "the exit-6 arm must say \"store UNVERIFIED; the job does not retry 6; re-run by hand\"" [brief] | R8 | mapped |
| 3 | "The comment near line ~3605 (\"Every other code is a fault that a retry cannot clear\") is false for exit 6, and the exit-5 arm's \"retrying will not clear it\" is stale." [brief] | CMT, E5 | mapped |
| 4 | "Grep each claim's SUBJECT repo-wide, not its phrasing." [brief] | Subject census | mapped |
| 5 | "Spawn soleur:engineering:cto first for any technical fork, plus an apply-trigger plan" [brief] | Technical Rulings, Apply-trigger plan | mapped |
| 6 | "The edit must be NET-NEGATIVE in bytes." and "Re-measure before and after." [brief] | Edit table (-63), Phase 0, Phase 3 | mapped |
| 7 | "name the exact test that enforces it" [brief] | Byte-budget guard | mapped |
| 8 | "Ship as ONE PR. PR body uses \"Ref #11667\" and \"Ref #9757\" only" [brief] | Phase 4 | mapped |
| 9 | "Three other open PRs touch this workflow file (#10928 draft, #10678, #7390): read-only awareness only" [brief] | Merge-order risk | mapped |
| 10 | "every R1-R8 anchor re-located by CONTENT in the current workflow ... exact before/after string per anchor with byte delta" [brief] | Edit table (R6 and R7 recorded as cut) | mapped |
| 11 | "list them [tests that pin these strings]" [brief] | Pin census | mapped |
| 12 | "Do NOT edit the workflow file or any source code - plan-only" [brief] | This phase writes only plans/specs files | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/apply-web-platform-infra.yml` edits (eight) | "Item 2b of #11667 (workflow strings in .github/workflows/apply-web-platform-infra.yml)" | asked |
| W9 pin for arm 6 (`tests/scripts/test-registry-d10-workflow-wiring.sh`) | — | inferred — justification: the arm changed because the engine moved and the workflow lagged unnoticed; W9 compares exit codes but not arm claims, so without a pin the "UNVERIFIED, do not deploy" claim can drift again (CTO recommended it; shrunk to the one arm that carries the safety claim, two needles, two controls) |
| Phase 0 re-measure | "Re-measure before and after." | asked |
| Apply-trigger plan | "plus an apply-trigger plan" | asked |

### Split Assessment

- Subsystems touched: 2 (`.github/workflows`, `tests/scripts`)
- Planned files: 2 | Estimated changed lines: about 30
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the brief requires one PR)

## Acceptance Criteria

- [ ] AC1: `wc -c` of the workflow in the branch is at most 489,650 and strictly below `git show origin/main:.github/workflows/apply-web-platform-infra.yml | wc -c` (expected 489,617, delta -63).
- [ ] AC2: `bun test plugins/soleur/test/workflow-file-size.test.ts` passes (`no workflow file exceeds the gate`).
- [ ] AC3: each of the eight new strings occurs exactly once in the file; `wider set`, `recovered by re-running rather than`, `still EMPTY`, `retry cannot clear` and `cannot refill it` occur zero times in the workflow (`grep -c`).
- [ ] AC4: `bash tests/scripts/test-registry-d10-workflow-wiring.sh` passes with `EXPECTED_ASSERTIONS=93`; RED evidence for the `6)` check and the `unv6`/`nodeploy` controls (run against the unchanged workflow) is recorded.
- [ ] AC5: the exit-6 arm contains `UNVERIFIED`, `do not deploy until a re-run exits 0`, `then re-run by hand` and `the job does not retry 6`; the exit-5 arm contains `retrying unchanged will not clear it`; the exit-78 arm contains `unchanged by this step`; the Doppler abort still contains `registry-store-restore ABORT`.
- [ ] AC6: the Restore-summary echo lines, the exit-1/2/3/4 arms, the `*)` arm and all `# Rationale:` pointer lines are byte-identical to `origin/main`.
- [ ] AC7: YAML parses; `terraform-target-parity`, `stock-preflight-coverage`, `test-argv-bearer-sweep` and `test-registry-luks-recut-gate` suites pass.
- [ ] AC8: `git diff origin/main --stat` shows only the two Files-to-Edit plus planning artifacts; no ADR, C4, runbook, engine or other workflow file changed; the other three open PRs and issues #11312, #11379, #10924, #11694 are untouched.
- [ ] AC9: the PR body uses `Ref #11667` and `Ref #9757` only, with no closing-keyword wording in any form, and contains no `[skip-web-platform-apply]` line; its first line states that merging fires the push apply run.
- [ ] AC10 (post-merge): the apply-trigger verification checklist is run and its evidence commented on #11667 (preflight and apply `success`; recut, pull-path gate and restore `skipped`; file 489,617 on main).

## Test Scenarios

- Given the unchanged workflow, when the new `6)` check runs, then it fails (RED).
- Given the edited workflow, when W9 runs the step body with the engine stubbed to exit 6, then the annotation names exit 6, contains `UNVERIFIED` and `do not deploy`, and the step exits 6 after exactly one engine call (existing harness).
- Given the engine stubbed to exit 3 three times then 0, then the retry loop still recovers (existing scenario; the comment edit must not move `rc=$?`, `max=6`, `case "$rc" in`, `exit "$rc"`).
- Given a Doppler read failure, then `registry-store-restore ABORT` is printed and the step exits 1 with zero engine calls (existing scenario; the new text keeps the `ABORT` anchor).
- Given the file at 489,617 bytes, then `no workflow file exceeds the gate` passes.

## Observability

Not triggered as a new surface: the change edits operator-facing annotation text in an existing workflow and adds no code path, log call or failure mode. The strings are themselves the discoverable signal for the restore failure modes, and the post-merge check (`gh run view` job conclusions) needs no SSH.

```yaml
liveness_signal:
  what: the corrected exit-6 annotation is present in the workflow on main, and the push-triggered apply run for the merge commit concluded success
  cadence: once per merge touching the workflow
  alert_target: the workflow's own ops email on a non-green apply and the ci/ issue sweep
  configured_in: .github/workflows/apply-web-platform-infra.yml (job apply, final steps)
error_reporting:
  destination: GitHub Actions job conclusion plus ops email on a non-green apply
  fail_loud: true
failure_modes:
  - mode: file crosses the 490,000-byte gate after another PR merges first
    detection: workflow-file-size test on the later PR and on main
    alert_route: red CI on the PR or on main
  - mode: push apply run fails or shows unexpected drift
    detection: gh run view job conclusions and the apply plan summary
    alert_route: ops email from the apply workflow
logs:
  where: GitHub Actions run logs of the push apply run
  retention: GitHub default run-log retention
discoverability_test:
  command: grep -c "store UNVERIFIED, do not deploy until a re-run exits 0" .github/workflows/apply-web-platform-infra.yml
  expected_output: 1
```

The probe is a one-grep literal check that finishes instantly (preflight Check 10 allowlists `grep`; no shell-active characters). It is deliberately not the size-gate suite: a `bun test` command is suite-shaped and Check 10's 15-second cap and probe rules are written for a signal, not a suite. The push-run conclusion is read with `gh run view` in the post-merge checklist, which is not a Check 10 probe.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it (threshold `none` with the scope-out bullet).
- Each anchor must match exactly once; R2 and the exit-5 string contain escaped backticks (`\``) inside a double-quoted `echo` in a YAML block scalar. Copy the old string from `sed -n` output, not from this table's rendering.
- `rc=$?`, `max=6`, `case "$rc" in` and `exit "$rc"` are W9 mutation anchors: the comment rewrite (CMT) sits above the loop and must not move or wrap them.
- Do not use `[skip-web-platform-apply]` and do not cancel any in-flight apply.
- A recut, restore or `registry_pull_path_gate` dispatch is never part of this work.
- R4 now reads "Nothing was written; the store is unchanged by this step" for the Doppler abort: it is a statement about the attempt, matching the exit-1 and exit-78 arms. The summary-level "empty or partial" line of the restore summary step is unchanged and still accurate.
