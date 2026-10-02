# Tasks: docs — drain-prs SKILL.md merge-queue claim

Plan: `knowledge-base/project/plans/2026-10-02-docs-drain-prs-stale-merge-queue-claim-plan.md`
Issue: #9418 (OPEN) — closes on merge via `Closes #9418` in the PR body.

## Phase 1 — Doc correction

- [x] 1.1 Edit `plugins/soleur/skills/drain-prs/SKILL.md` §"4. Per in-scope PR":
      replace the "Merge queue active / Queue inactive (fallback)" bullet pair
      per the plan's reference shape — direct merge under strict up-to-date
      protection as the documented default; revert anchored to ADR-032
      amendment / #5811; re-adoption pointer #5840 / #4856. Preserve the
      `gh pr update-branch` handling, the `knowledge-base/` file-count /
      `kb-index` carve-out, the `merge-pr` cross-reference, and the
      Monitor/AwaitShell CI-wait clause essentially verbatim.
- [x] 1.2 (optional) Reword the Sharp Edges "queue-inactive CI wait" phrase in
      the same file (e.g., "post-`update-branch` CI wait").
- [x] 1.3 (optional) Tidy `.github/workflows/scheduled-terraform-drift.yml`
      comment (~line 44) that references "the new merge_queue rule".

## Phase 2 — Verification

- [x] 2.1 Run the plan's AC greps: stale-phrase count `0`; `kb-index` carve-out
      still present; `ADR-032` / `codeql-action` citation present; repo-wide
      queue-active sweep clean.
- [x] 2.2 `bash plugins/soleur/test/drain-prs.test.sh` passes.
- [ ] 2.3 PR body carries `Closes #9418` and a `## Changelog` section
      (docs fix → `semver:patch`).
