# Tasks — feat: `drain-prs` skill

lane: cross-domain (no spec.md present — defaulted, fail-closed)
Plan: `knowledge-base/project/plans/2026-06-30-feat-drain-prs-skill-plan.md`

## Phase 0 — Preconditions

- [ ] 0.1 Verify `gh` authenticated, `jq` on PATH, CWD is a git worktree (not bare root).
- [ ] 0.2 Confirm PR #5808 is merged to main (learnings + ADR-033 §Registration checklist). Treat as a merge-order dependency for THIS PR.
- [ ] 0.3 Re-measure budget: `bun test plugins/soleur/test/components.test.ts` — confirm `SKILL_DESCRIPTION_WORD_BUDGET` baseline (2292/2292).

## Phase 1 — SKILL.md

- [ ] 1.1 Create `plugins/soleur/skills/drain-prs/SKILL.md` mirroring `drain-labeled-backlog/SKILL.md`.
- [ ] 1.2 Frontmatter: `name: drain-prs` + third-person `description` (~30–34 words, ≤1024 chars, no `<example>`). Record exact word count for the budget bump.
- [ ] 1.3 When-to-use section; disambiguate from `merge-pr` (single PR) and `drain-labeled-backlog` (issues).
- [ ] 1.4 `<decision_gate>` block: gates all merges; per-PR opt-out within a tier; copy stating "confirm = merges to main"; API-budget note (BSL-1.1 runtime-cost framing, paren-safe).
- [ ] 1.5 Prerequisites + Arguments (`--tiers`, `--dry-run`, `--pr`).
- [ ] 1.6 Workflow: enumerate (`gh pr list --json …`) → 6-tier triage → decision gate → per-PR ensure-green + `gh pr merge --squash` (queue-active) / update-branch → Monitor-wait → merge (queue-inactive) → review delegation → `cleanup-merged` → drain delta.
- [ ] 1.7 Fix-recipes section linking the two #5808 learnings by path: (a) lockfile drift (bun.lock / npm@11 package-lock); (b) generated-file regen via `scripts/rule-metrics-aggregate.sh`; (c) stale bot/cron PR — rebase, `tsc`, ADR-033 §Registration checklist.
- [ ] 1.8 Pipeline detection (headless on RETURN CONTRACT); Sharp edges; Test link.

## Phase 2 — Helper + test

- [ ] 2.1 Create `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh` — `gh pr list --json …` → pure-`jq` 6-tier classifier → tier-grouped JSON. Two-stage `gh --json | jq` (no `gh --jq --arg`). Fail-fast on missing `gh`/worktree.
- [ ] 2.2 Create `plugins/soleur/test/drain-prs.test.sh` mirroring `drain-labeled-backlog.test.sh` — synthetic fixtures (one PR per tier + empty-list), output-shape + sort assertions, no live `gh` call.

## Phase 3 — Wiring

- [ ] 3.1 `bash scripts/sync-readme-counts.sh` → README skills count 92→93 (do not hand-edit). Optional curated `drain-prs` row near `merge-pr`.
- [ ] 3.2 Add `drain-prs` router row to `plugins/soleur/commands/go.md` table — distinct from the issue `drain` row.
- [ ] 3.3 Bump `SKILL_DESCRIPTION_WORD_BUDGET` in `components.test.ts:15` by exactly the new description word count; append bump-note in the existing format.
- [ ] 3.4 PR body: `## Changelog` section; apply `semver:minor` label.

## Phase 4 — Validation

- [ ] 4.1 `bash scripts/sync-readme-counts.sh --check` → 93, exit 0.
- [ ] 4.2 `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] 4.3 `bash plugins/soleur/test/drain-prs.test.sh` passes.
- [ ] 4.4 Eleventy docs build (`soleur:deploy-docs`) passes.
- [ ] 4.5 Skill compliance: third-person description, markdown `scripts/` links, `name` matches dir.
- [ ] 4.6 Ship-time: Glob-verify the two #5808 learnings + ADR-033 §Registration checklist resolve on main.
