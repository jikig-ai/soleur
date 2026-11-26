# Tasks: feat-one-shot-12780-single-row-reprice-docs

Plan: `knowledge-base/project/plans/2026-11-26-docs-single-row-reprice-recipe-plan.md`.
Docs half of #12780 only. Use `Ref #12780` everywhere; never a closing verb next to the number.

## Phase 1: Setup

- [ ] 1.1 Re-read the four target files on the branch tip; confirm the anchors the plan names
  still exist (the runbook's "Merge conflict on the TSV → regenerate, never hand-merge" paragraph,
  the "To re-price by hand:" sentence, ADR-242's last amendment, the `scripts/test-all.sh` comment
  above `run_suite "scripts/check-web-host-escrow-config"`).
- [ ] 1.2 Run the AC8 positive control on `origin/main` (three lines expected).

## Phase 2: Core Implementation

- [ ] 2.1 Runbook: insert `### Re-price one row from merge_group medians (#12780)` (plan Phase 1.1).
- [ ] 2.2 Runbook: replace the "To re-price by hand:" sentence in the drift-watch section (plan Phase 1.2).
- [ ] 2.3 ADR-242: prepend the `amended_by:` entry (plan Phase 2.1).
- [ ] 2.4 ADR-242: append `## Amendment — 2026-11-26 (#12780)` (plan Phase 2.2); edit nothing above it.
- [ ] 2.5 `scripts/test-all.sh`: replace the two comment lines (plan Phase 3); comment lines only.
- [ ] 2.6 Learning `workflow-patterns/2026-10-31-shard-reprice-checkpoint-mechanics.md`: add the
  dated pointer under step 3 of `## Solution` (plan Phase 4).

## Phase 3: Testing

- [ ] 3.1 AC1-AC6 and AC8 greps and diffs.
- [ ] 3.2 AC7 scratch drill (downward edit exits 0 with `0 moved`; 3x upward edit exits 2 with
  `weight drift refusal`; the 3x edit with `--allow-growth` exits 0 and writes `# growth-acked=`;
  a heavy row past the thresholds refuses only with `--group heavy`; `git status --short` shows no
  tracked table change).
- [ ] 3.3 AC9: `bun test plugins/soleur/test/components.test.ts`; `bash scripts/markdown-lint.sh` on the runbook and ADR-242; `bash -n scripts/test-all.sh`.
- [ ] 3.4 AC11: `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 3.5 AC10 at ship time: PR body and commit messages carry `Ref #12780` and no closing reference.
