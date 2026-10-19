# Tasks: feat-one-shot-fix-ux-audit-thinking-api

Derived from `knowledge-base/project/plans/2026-04-18-fix-ux-audit-thinking-api-plan.md` (fix #2540).

## Phase 1 — Pre-flight (5 min)

- [x] 1.1 Confirm `v1.0.101` resolves to SHA `ab8b1e6471c519c585ba17e8ecaccc9d83043541` via `gh api repos/anthropics/claude-code-action/git/refs/tags/v1.0.101 --jq '.object.sha'`.
- [x] 1.2 Confirm release notes for v1.0.100 cite Agent SDK 0.2.113 bump (`gh api repos/anthropics/claude-code-action/releases --jq '.[] | select(.tag_name=="v1.0.100") | .body'`).
- [x] 1.3 Enumerate the 14 workflow files pinned at the old SHA: `grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6" .github/workflows/`.
- [x] 1.4 Check for conflicting open PRs: `gh pr list --state open --search "claude-code-action"`.

## Phase 2 — Apply pin bump (10 min)

- [x] 2.1 Dry-run the replacement pattern against one file first. Verify diff.
- [x] 2.2 Apply in-place sed sweep:

  ```bash
  sed -i 's|anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75|anthropics/claude-code-action@ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101|g' .github/workflows/*.yml
  ```

- [x] 2.3 Verify the old SHA is gone: `grep -rn "df37d2f0760a4b5683a6e617c9325bc1a36443f6" .github/workflows/` — expect empty.
- [x] 2.4 Verify 14 files now have the new SHA: `grep -rn "ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101" .github/workflows/ | wc -l` — expect 14.
- [x] 2.5 Confirm `scheduled-roadmap-review.yml` is untouched (`grep "v1" .github/workflows/scheduled-roadmap-review.yml` → still `ff9acae...` on `v1` float).

## Phase 3 — Add context comment (2 min)

- [x] 3.1 In `.github/workflows/scheduled-ux-audit.yml`, add 4-line comment block above the `uses:` line on the `Run ux-audit skill` step referencing issue #2540 and the `thinking.type.adaptive` requirement.
- [x] 3.2 Re-lint with `npx markdownlint-cli2 --fix` if any Markdown was touched (none in this phase — YAML only).

## Phase 4 — Commit and push (3 min)

- [ ] 4.1 Stage changes: `git add .github/workflows/ knowledge-base/project/plans/2026-04-18-fix-ux-audit-thinking-api-plan.md knowledge-base/project/specs/feat-one-shot-fix-ux-audit-thinking-api/tasks.md`.
- [ ] 4.2 Run `skill: soleur:compound` per AGENTS.md `wg-before-every-commit-run-compound-skill`.
- [ ] 4.3 Commit with conventional message: `fix(ci): bump claude-code-action v1.0.75 → v1.0.101 for thinking.type.adaptive (#2540)`.
- [ ] 4.4 Push to remote with `-u origin <branch>` per AGENTS.md `rf-before-spawning-review-agents-push-the`.

## Phase 5 — Review & ship (handled by soleur:one-shot pipeline)

- [ ] 5.1 Spawn review agents on the pushed branch.
- [ ] 5.2 Address review findings (fix-inline for P1/P2/P3 per AGENTS.md `rf-review-finding-default-fix-inline`).
- [ ] 5.3 Create PR with body `Closes #2540` (body, not title).
- [ ] 5.4 `gh pr merge <n> --squash --auto`.
- [ ] 5.5 Poll until merged.

## Phase 6 — Post-merge verification (15 min)

- [ ] 6.1 Trigger `gh workflow run scheduled-ux-audit.yml`. Poll with `gh run list --workflow=scheduled-ux-audit.yml --limit 1 --json databaseId,status,conclusion`.
- [ ] 6.2 Verify run reaches the `Run ux-audit skill` step without emitting `thinking.type.enabled` error.
- [ ] 6.3 Trigger `gh workflow run scheduled-competitive-analysis.yml`. Poll. If it fails on a *different* error, file a follow-up issue.
- [ ] 6.4 Trigger `gh workflow run scheduled-growth-audit.yml`. Poll. Same as above.
- [ ] 6.5 Append the pin-freshness note to `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` (learning capture — may be handled by soleur:compound).
- [ ] 6.6 Run `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.

## Acceptance checklist

- [ ] All 14 workflow files pinned to `ab8b1e6...` (v1.0.101).
- [ ] `scheduled-roadmap-review.yml` untouched.
- [ ] Post-merge dispatch of `scheduled-ux-audit.yml` completes without `thinking.type.enabled` error.
- [ ] PR body contains `Closes #2540`.
- [ ] Pin-freshness learning captured.
