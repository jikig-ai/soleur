---
date: 2026-05-09
issue: "#3489"
plan: ../../plans/2026-05-09-fix-retired-rule-id-sweep-cq-gh-issue-label-verify-name-plan.md
---

# Tasks: Retired-rule-id sweep for `cq-gh-issue-label-verify-name`

## Phase 1 — Edits

- [ ] 1.1 Edit `plugins/soleur/commands/go.md:40` — drop `(rule cq-gh-issue-label-verify-name)` parenthetical; inline rationale ("verified via `gh label list`"). Preserve surrounding prose.
- [ ] 1.2 Edit `plugins/soleur/skills/drain-labeled-backlog/SKILL.md:30` — drop `(rule cq-gh-issue-label-verify-name)`; the skill itself owns the convention now, so the inline rationale ("Validated against `gh label list` before querying") is sufficient.
- [ ] 1.3 Edit `plugins/soleur/skills/drain-labeled-backlog/SKILL.md:64` — same pattern as 1.2.
- [ ] 1.4 Edit `plugins/soleur/skills/plan/SKILL.md:721` — rewrite the `Cited rule:` parenthetical to drop the retired ID. Add a brief note that the convention now lives in `deepen-plan/SKILL.md:556` AC. Preserve `**Why:** PR #3378` verbatim.
- [ ] 1.5 Edit `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md:375` — remove all 5 retired rule IDs from the `AGENTS.md rules:` enumeration. Replace each with a pointer to its canonical owner (`plugins/soleur/skills/ship/references/ci-workflow-authoring.md` for the 4 GitHub Actions rules; planning skills for the label-verify rule).

## Phase 2 — Verification

- [ ] 2.1 Run `grep -rEn "cq-gh-issue-label-verify-name" --include="*.md" plugins/ knowledge-base/engineering/` and confirm zero hits.
- [ ] 2.2 Run `grep -E "(cq-ci-steps-polling-json-endpoints-under|cq-workflow-pattern-duplication-bug-propagation|hr-in-github-actions-run-blocks-never-use|hr-github-actions-workflow-notifications)" knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` and confirm zero hits.
- [ ] 2.3 Run `lefthook run pre-commit` and confirm pass.
- [ ] 2.4 Verify `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` still exists (the canonical replacement for the 4 GitHub Actions rules in 1.5).

## Phase 3 — Commit and PR

- [ ] 3.1 Run `skill: soleur:compound` to capture any session learnings.
- [ ] 3.2 Stage and commit edits with a `docs:` prefix message that names the issue.
- [ ] 3.3 Push the branch and open the PR. Body must use `Closes #3489` on its own line; nowhere else may auto-close keywords appear (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] 3.4 Assign `semver:patch` label (docs cleanup).

## Phase 4 — Review and Ship

- [ ] 4.1 Run `skill: soleur:review` (multi-agent review, including `code-quality-analyst` which catches retired/fabricated rule IDs).
- [ ] 4.2 Apply review fixes inline.
- [ ] 4.3 Run `skill: soleur:ship` and merge via auto-merge.
