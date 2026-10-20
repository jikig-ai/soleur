# Tasks: DPIA re-evaluation for the Compound Promotion Loop (#2720), tracker #6107

Plan: `knowledge-base/project/plans/2026-10-20-docs-dpia-reeval-compound-promote-2720-plan.md`
Branch: `worktree-agent-aa1d073f6314c9461` | Draft PR: #10674 | Body uses `Ref #6107`, never `Closes`.
Forbidden: editing `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`, touching #10552 or #8443.

## Phase 1: Gather evidence (read-only)

- 1.1 Count data rows in `knowledge-base/project/learnings/promotion-log.md` below the `ROWS BELOW` marker.
- 1.2 Search loop-opened PRs three ways (label, head-branch `self-healing/auto-`, title `compound-promote`); exclude PRs that change the loop; for any opened PR compute state/merged.
- 1.3 Read #10552 body and comments (no edits, no comments).
- 1.4 Better Stack marker query (read-only, Doppler `soleur/prd_terraform`), field-isolated, with `SOLEUR_CLAUDE_COST` positive control; bounded output; no SSH. Fallback: record "not derivable: credential".
- 1.5 Re-measure or cite Better Stack log retention (runbook, dated).
- 1.6 Read phase-1/phase-2 code and marker module; record symbol anchors (`draftAdditiveEdit`, `EDIT_TARGET_MAX_BYTES`, `WEEK_CAP_DEFAULT`, `emitOutcomeMarker`, `RefusalDetailEntry`).
- 1.7 Confirm `promotion-config.yml` `enabled: true`; read PA-31 content cell and the compound-promote lines of `anthropic.md`.
- 1.8 Write the facts bundle to the scratchpad; label each figure measured / not measurable / not derivable.

## Phase 2: Legal determination (CLO agent writes the artifact)

- 2.1 Spawn `soleur:legal:clo` with the facts bundle, template memo, sweeper script, plan Domain Review guidance and CPO conditions; it writes `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md`.
  - 2.1.1 Frontmatter `status: draft-requires-counsel-review` plus the AI-generated DRAFT banner.
  - 2.1.2 Wording: "determination at current scale, conditional, not an empirical finding"; never "passed"; state the actual date performed and the delay cause (4-week clock missed; phase-2 bug fixed by #10553).
  - 2.1.3 Triggers pinned (three required + CLO-added); CPO re-arm reference.
  - 2.1.4 Avoid breach-article strings and standalone unresolved-marker tokens.
- 2.2 Verify each factual sentence against Phase 1 evidence; report mismatches to the CLO.
- 2.3 If the CLO rules "full DPIA required", follow it.

## Phase 3: Register agreement

- 3.1 `knowledge-base/legal/compliance-posture.md`: rewrite #2720 row, add dated Superseded markers, add DPIA index row, add standing-trigger row, add dated top comment.
- 3.2 Conditional: PA-31 dated note in `article-30-register.md`; one-line pointer in `anthropic.md`; one comment line in `promotion-config.yml`.
- 3.3 (execute as step 1.9, before Phase 2) Create the plain re-arm tracking issue per CTO ruling D5 (no followthrough directive, no probe script, no "soak" wording); give its number to the CLO; reference it from the memo and the posture row.

## Phase 4: Local verification

- 4.1 `bash scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` is RED before the file exists, then PASS.
- 4.2 `bash scripts/lint-legal-registers.sh` and markdownlint clean.
- 4.3 Diff-scope check: no `.ts`/`.sh`/workflow files, no cron file.

## Phase 5: Counsel-Review gate

- 5.1 Fresh `soleur:legal:clo` review writes `knowledge-base/legal/audits/2026-10-counsel-review-6107.md` (SIGNED-OFF or BLOCKED).
- 5.2 Apply conditions; re-verify after any rebase.
- 5.3 PR body lists this plan path first among `knowledge-base/project/` paths.

## Phase 6: Ship and postmerge

- 6.1 `soleur:ship` (poll CI / merge queue with Monitor until-loop).
- 6.2 Postmerge: confirm the sweeper closes #6107 (`gh workflow run scheduled-followthrough-sweeper.yml` if needed); do not close by hand.
