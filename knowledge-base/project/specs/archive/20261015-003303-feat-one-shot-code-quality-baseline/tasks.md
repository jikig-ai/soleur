# Tasks: docs(audit): GitHub Code Quality baseline on main 30407a8597

Plan: `knowledge-base/project/plans/2026-10-15-docs-github-code-quality-baseline-audit-plan.md`
Tracker: Ref #10331 (no close keywords)

## Phase 1: Copy

- 1.1 Copy `/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/5700a7b9-0481-4b66-9a10-d0eae1ea9155/scratchpad/cq-baseline.md` to `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md`
- 1.2 `diff` source and target; expect no output

## Phase 2: Lint

- 2.1 Run `scripts/markdown-lint.sh` on the new file
- 2.2 Check frontmatter keys against sibling audits
- 2.3 If a check objects, fix formatting only and record what changed; never edit findings

## Phase 3: Verify and ship

- 3.1 Confirm the diff is one new audit file plus plan/spec artifacts
- 3.2 PR title `docs(audit): GitHub Code Quality baseline on main 30407a8597`, body `Ref #10331` only, label `semver:patch`
- 3.3 Do not hand-sync a BEHIND PR in the merge queue
