---
title: "chore(registry): runbook sentence now states the engine header table lists exit 1"
type: chore
date: 2026-10-29
slug: runbook-exit1-sentence-header-table
branch: feat-one-shot-10932-runbook-exit1-sentence
issue: 10932
closes: none
lane: cross-domain
priority: p3
domain: engineering
brand_survival_threshold: none
---

# chore(registry): runbook sentence now states the engine header table lists exit 1

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-29
**Method:** proportionate to a one-sentence docs edit. The mechanical halts 4.6-4.13 were run
against the plan; cited identifiers were re-verified live; no broad agent fan-out (the brief asks
for minimal depth, and no framework, SDK or external surface applies).

### Key Improvements

1. Acceptance Criteria hardened by the plan-stage review: the diff-scope check now names the exact
   expected file set and runs after commit (before commit it lists nothing and passes vacuously),
   the one-hunk check is a command (`git diff -U0 origin/main...HEAD -- <runbook> | grep -c '^@@'`),
   and `lint-infra-no-human-steps.py --changed --base origin/main` replaces the three registry
   suites as the check that actually reads the edited file (the suites stay as a no-regression run).
2. Line numbers are now secondary to content anchors throughout.
3. Wording ruled by the CTO agent (see `decision-challenges.md`; the ruling gate passes, 4 rows).

### Verification results

- 4.6 pass (threshold `none`; the only edited file is under `knowledge-base/`, outside the sensitive
  path regex). 4.7 skipped (pure docs). 4.8 pass (no PAT shapes). 4.9 not triggered (no UI file).
  4.10, 4.11 not triggered (no store/connection, no guard). 4.12 pass (one unfenced
  `## Scope Check`, `Recommendation:` present, no `unmapped` row). 4.13 not triggered (no workflow
  or autonomous task). 4.5 and 4.55 not triggered.
- Live checks: #10932 OPEN, #9757 OPEN, #11518 MERGED (commit `45ff719b0a` is an ancestor of
  `origin/main` and touched `scripts/registry-restore-from-ghcr.sh` +7 lines), #11557 OPEN draft.
  The stale sentence is still present on `origin/main` (1 match). No AGENTS.md rule id is cited.
- Markdownlint on the plan: 0 issues.

## Overview

Residual 1 of #10932 (Ref #9757), one residual per PR. The engine header in
`scripts/registry-restore-from-ghcr.sh` gained its exit 1 row in #11518 (commit `45ff719b0a`), but
the runbook `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` still says,
in "Restore exit codes — one operator action each" (currently lines 495-498, anchored on the text `Its own header table does not`),
that the header table
"does not yet list exit 1 (input faults, tracked on #10932)". That sentence is now false and points
at an obligation that has been met. This PR rewrites that one sentence and touches nothing else.

Draft PR: #11557. PR body uses `Ref #10932` and `Ref #9757` only.

## Research Insights

**Premise Validation.** Checked before planning; everything held except the runbook wording, which
is the thing being fixed.

- `git grep` on `origin/main` (fetched this session): the stale text is still present at
  `registry-luks-recut-6929.md:495-496` and nowhere else outside plan/spec artifacts.
- The engine header on the branch (which equals `origin/main` for that file, last touched by
  `45ff719b0a`) has the row `#   1  INPUT or MANIFEST fault` in its EXIT CODES table — the sentence is stale.
- The restore step annotation exists: `.github/workflows/apply-web-platform-infra.yml` has, in the restore step's exit-code `case`, a
  `1) echo "::error::restore FAILED exit 1 (INPUT/MANIFEST fault) ..."` arm, so the "restore step
  annotates it" half of the sentence stays true.
- The table row for `1` (the `| \`1\` |` row) agrees with the header: both say input or manifest
  fault, before any network call, this attempt wrote nothing, not retryable, not an engine defect.
  No contradiction, so the row stays unchanged.
- Runbook line 477 "except exit 1, which re-runs identically — see its row" is consistent with both
  header and row and stays as is.
- No test pins the stale sentence (`git grep` for `tracked on #10932`, `own header table`,
  `yet list exit 1` over tests/, scripts/, plugins/, .github/, apps/ returns only the runbook).
- Cited issues: #10932 OPEN, #9757 OPEN. Collision pre-check: the only open PR naming #10932 is
  this branch's own draft #11557. No open code-review issue names the runbook.
- ADR corpus / mechanism check: no mechanism is proposed (a one-sentence wording fix), so there is
  nothing for an ADR to have rejected.
- Out of scope, noted so it is not mistaken for a gap: `tests/scripts/test-registry-d10-workflow-wiring.sh`
  line ~493 still says the header table is "both without 1" in its W9 failure wording (residual 2),
  and the Restore summary step / computed die sites / W9 verdict swap are residual 3. Separate PRs.

**Property List.**

1. The runbook no longer claims the engine header table lacks exit 1.
2. The runbook no longer carries a pointer to #10932 as pending work.
3. The surrounding sentences, the `1` table row and line 477 are byte-identical to before.
4. The engine script and the apply workflow are byte-identical to before (an engine edit arms the
   ~860 s mutation battery; a workflow edit fires the production apply).

**Cut List.** No mechanism is proposed by the ask beyond the wording edit itself, so nothing is cut.
Considered and not adopted: adding a runbook-vs-header parity test. It would buy property 1 durably,
but the existing W9 check already compares the header table to the codes the engine emits (residual
2 reworks its wording), and a second guard for one sentence is more machinery than the sentence.

**Learnings applied.** None of the plan's sharp edges bear on a prose-only change beyond the
diff-scope AC below; no institutional learning is specific to this sentence.

## Implementation

Single edit to `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`,
replacing the sentence that currently wraps lines 495-497 (anchor on content; re-read the file first; line numbers
move). Anchor on the content `Its own header table does not`, not on the line number.

Before (as on `origin/main`):

```text
`scripts/registry-restore-from-ghcr.sh` exits with the codes below. Its own header table does not
yet list exit 1 (input faults, tracked on #10932), but the restore step annotates it and it has a
row here. Codes consumed
as a single boolean would be a contract nobody can act on, so each maps to exactly one action.
```

After:

```text
`scripts/registry-restore-from-ghcr.sh` exits with the codes below. Its own header table lists
exit 1 (input or manifest faults), as do the restore step's annotation and the row below. Codes
consumed as a single boolean would be a contract nobody can act on, so each maps to exactly one
action.
```

Notes on the wording:

- Based on the CTO-ruled wording from the prior plan ("Its own header table lists exit 1 (input
  faults), as does the restore step annotation and the row below"), with two mechanical
  refinements: "as do" (the subject is plural) and "input or manifest faults" (the header's own
  name for the code, and the table row's). Recorded in `decision-challenges.md`.
- The "Codes consumed" line break was an artefact of the original edit; the paragraph is reflowed
  so the sentence is not left ragged. This changes only whitespace inside the same paragraph.
- Do not rewrite the `1` row or line 477.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` — the one sentence.

## Files to Create

- `knowledge-base/project/plans/2026-10-29-chore-runbook-exit1-sentence-header-table-plan.md` (this plan)
- `knowledge-base/project/specs/feat-one-shot-10932-runbook-exit1-sentence/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10932-runbook-exit1-sentence/decision-challenges.md`

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) has no body naming
`registry-luks-recut-6929.md`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Rewrite it so it states that the header table now lists exit 1 and drops the \"tracked on #10932\" pointer" [brief] | Implementation; Files to Edit entry 1 | mapped |
| 2 | "keep the surrounding text and the table row for `1` unchanged unless it also contradicts the header" [brief] | Premise Validation (row `1` agrees with header); Acceptance Criteria 2 | mapped |
| 3 | "confirm with git grep on current origin/main that the sentence is still stale" [brief] | Premise Validation, first bullet | mapped |
| 4 | "do NOT edit scripts/registry-restore-from-ghcr.sh or .github/workflows/apply-web-platform-infra.yml" [brief] | Acceptance Criteria 3 | mapped |
| 5 | "Run tests/scripts/test-registry-d10-workflow-wiring.sh, test-registry-pull-path-health.sh and test-registry-restore-from-ghcr.sh" [brief] | Test Scenarios; Acceptance Criteria 5 | mapped |
| 6 | "PR body uses `Ref #10932` and `Ref #9757` only, never Closes/Fixes/Resolves" [brief] | Overview; Acceptance Criteria 6 | mapped |
| 7 | "Residual 2 ... and residual 3 ... are separate PRs, out of scope here." [brief] | Premise Validation (out of scope note) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit to the runbook sentence | "Rewrite it so it states that the header table now lists exit 1" | asked |
| Reflow of the "Codes consumed" fragment | — | inferred — justification: the original edit left a one-word line fragment inside the same paragraph; rewriting the sentence without reflowing would leave visibly ragged markdown, and the reflow changes whitespace only |
| `decision-challenges.md` row for the wording | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table" | asked |
| `tasks.md` | — | inferred — justification: the plan skill's Save Tasks step derives it for `soleur:work`; it carries no content beyond the plan |

### Split Assessment

- Subsystems touched: 1 — knowledge-base/engineering/operations
- Planned files: 1 edited (plus 4 plan/spec artifacts) | Estimated changed lines: ~4
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; at worst an operator reads
  a runbook sentence that is still stale or slightly mis-worded during a registry recut.
- **If this leaks, the user's data is exposed via:** no vector — a prose edit to an internal
  runbook, no secrets, hosts or identifiers added.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`, because a one-sentence
  documentation correction carries no user-visible behaviour and no data path.

## Acceptance Criteria

1. `grep -c "tracked on #10932" <runbook>` and `grep -c "yet list exit 1" <runbook>` both print
   `0`; `grep -c "Its own header table lists" <runbook>` prints `1`; and
   ``grep -c '^| `1` |' <runbook>`` prints `2` on `origin/main` and on this branch alike (the D10
   gate's "Over cap" row and the restore-exit-codes row the new sentence points at; the count must
   not change).
2. The diff is one hunk inside the intended paragraph, and the `1` table row and the
   `except exit 1` phrase are untouched:
   `git diff -U0 origin/main...HEAD -- <runbook> | grep -c '^@@'` prints `1`, and that hunk's
   removed lines all belong to the paragraph beginning `scripts/registry-restore-from-ghcr.sh` exits.
3. The changed-file set is exactly the runbook plus the four planning artifacts:
   `git diff --name-only origin/main...HEAD` equals the runbook path, the plan file,
   `specs/feat-one-shot-10932-runbook-exit1-sentence/tasks.md`, `.../decision-challenges.md` and
   `.../session-state.md` (the pipeline's own state file).
   No path under `scripts/`, and not `.github/workflows/apply-web-platform-infra.yml`. (Run it after
   committing: before commit the command lists nothing and passes vacuously.)
4. The statement is true: `grep -c '^#   1  INPUT' scripts/registry-restore-from-ghcr.sh` prints
   `1`, and `grep -c '1) echo "::error::restore FAILED exit 1' .github/workflows/apply-web-platform-infra.yml`
   prints at least `1`.
5. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes (the lint
   that actually reads this file). The three registry suites
   (`tests/scripts/test-registry-d10-workflow-wiring.sh` baseline 47/0,
   `test-registry-pull-path-health.sh` 63/0, `test-registry-restore-from-ghcr.sh` 98/0) are a
   no-regression run, expected unchanged. If the local battery queues behind a sibling worktree,
   CI's required `test` context is the accepted gate. Launch any long local gate in its own Bash
   call and read `gate.log` before reporting it as running.
6. PR body carries `Ref #10932` and `Ref #9757` and no `Closes`/`Fixes`/`Resolves`; #9757 and
   #10932 stay open; #11312, #11379 and #10924 are untouched.
7. Secret scan is clean before every push.

## Test Scenarios

- Docs-only: no new tests. The three registry suites above run as a no-regression check; none of
  them reads this sentence (verified by `git grep`), and the runbook is not in
  `REGISTRY_BATTERY_PATHS` (`scripts/lib/test-relevance-paths.sh`), so this PR does not arm the
  ~860 s mutation battery.
- Known unrelated red, do not chase: advisory `affected-index-ratchet` (stale-line on
  `scripts/ci-pr-affected-audit.baseline.tsv`).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — documentation wording fix in an engineering runbook.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`
  Phase 4.6. This one declares `none` with a one-sentence reason.
- Anchor the edit on the sentence content, not on line numbers 495-497: the runbook moves.
- Do not "fix" `tests/scripts/test-registry-d10-workflow-wiring.sh` line ~493 here; it is
  residual 2.
