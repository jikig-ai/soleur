# Session State

## Plan Phase

- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-oracle-bound-row/knowledge-base/project/plans/2026-11-17-fix-oracle-review-required-bound-row-plan.md
- Status: complete

### Errors

- `gh pr view 12329 --json merged` field unsupported; corrected to `mergedAt` — PR confirmed MERGED 2026-11-08.
- markdownlint MD038 on a code span in AC-4 — fixed; all artifacts lint clean.
- `technical-ruling-gate.sh --branch` exits 1 on 3 `unruled-technical` rows — expected; the parent pipeline's batched CTO spawn rewrites them before `work`.
- No Agent/Task spawn capability in this harness — deepen-plan fan-outs ran as inline verification passes (disclosed in plan).

### Decisions

- Seed `oracle-review-required` at bound 180s (pull_request) / 120s (merge_group), margin 0.30 — the TSV header's method applied to measured p90s (139s n=30 / 100s n=29).
- Row placed between `vendor-pin-required` and `cla-check`, mirroring `required-checks.txt` ordering; seed provenance in TSV header note + runbook bullet.
- No `Closes #12755` — standing tracker is the watch's report home (pending-CTO-rewrite row).
- TSV-vs-population parity-test gap deferred to an `action-required` follow-up (pending-CTO-rewrite row).

### Components Invoked

- `soleur:plan`, `soleur:deepen-plan` (read from plugin root and run in-process)
- `gh issue/pr view`, `markdownlint-cli2`, `technical-ruling-gate.sh --branch`
- Artifacts: plan file, `tasks.md`, `decision-challenges.md`

## Operator Constraints

- constraint: `watch-wallclock-p90-11774.sh --dry-run` flagged set must not list `unbound: oracle-review-required`
- constraint: row format matches sibling rows (tab-separated, 4 columns)
- constraint: only the TSV plus knowledge-base artifacts change
- cto_spawns=1 (batched; 3 unruled-technical rows ruled, all defaults affirmed)
