---
title: Tasks — AGENTS.md rule threshold + migration
plan: knowledge-base/project/plans/2026-04-21-chore-agents-md-rule-threshold-migration-plan.md
issue: 2686
pr: 2754
branch: feat-agents-rule-threshold
status: todo
---

# Tasks — feat-agents-rule-threshold

## 1. Preflight & Measurement

- [ ] 1.1 Capture baseline: run `grep -c '^- ' AGENTS.md`, `wc -c < AGENTS.md`, `grep '^- ' AGENTS.md | awk '{print length}' | sort -n | tail -1`. Record in a scratch file for the PR body.
- [ ] 1.2 Verify aggregator: `gh run list --workflow rule-metrics-aggregate.yml --limit 5 --branch main` — confirm latest scheduled run succeeded. No follow-up issue needed.
- [ ] 1.3 Confirm migration targets still carry enforcement tags: `git show main:AGENTS.md | grep -E 'cq-after-completing-a-playwright-task-call|cq-before-calling-mcp-pencil-open-document|wg-when-a-research-sprint-produces'`.

## 2. Threshold Raise (100 → 115)

- [ ] 2.1 Edit `AGENTS.md` line 81 (`cq-agents-md-why-single-line`): change `>100 rules` → `>115 rules` and append `**Why:** #2686` one-liner per plan.
- [ ] 2.2 Edit `plugins/soleur/skills/compound/SKILL.md` line 205: `A > 100` → `A > 115`; `(A/100)` → `(A/115)`. Do NOT touch byte/per-rule thresholds.
- [ ] 2.3 Read-back: `grep -n '115' AGENTS.md plugins/soleur/skills/compound/SKILL.md` returns the two new references; no stale `100` remains in threshold context.

## 3. Skill-Migration Pattern Proof (3 rules, pointer-preservation)

- [ ] 3.1 Migrate `cq-after-completing-a-playwright-task-call`: move full rule body into `plugins/soleur/hooks/browser-cleanup-hook.sh` header comment block (above `set -euo pipefail`) with `# Rule source: AGENTS.md — migrated 2026-04-21 (PR #2754)` marker. Replace AGENTS.md L75 with one-line pointer preserving the `[id: ...]` tag.
- [ ] 3.2 Migrate `cq-before-calling-mcp-pencil-open-document`: move body into BOTH `.claude/hooks/pencil-open-guard.sh` header AND an "Untracked .pen safety" subsection in `plugins/soleur/skills/pencil-setup/SKILL.md`. Replace AGENTS.md L73 with pointer.
- [ ] 3.3 Migrate `wg-when-a-research-sprint-produces`: absorb body into `plugins/soleur/skills/work/SKILL.md` §Phase 2.5 cascade-validate-loop instructions. Replace AGENTS.md L40 with pointer.
- [ ] 3.4 Sanity-check: `diff <(git show HEAD:AGENTS.md | grep -oE '\[id: [a-z0-9-]+\]' | sort -u) <(grep -oE '\[id: [a-z0-9-]+\]' AGENTS.md | sort -u)` returns empty (no IDs removed).

## 4. Verification, Sync Guard, Follow-up

- [ ] 4.1 Re-measure: `grep -c '^- ' AGENTS.md` flat vs baseline; `wc -c < AGENTS.md` ≥ 800 bytes lower; `longest ≤ 600`.
- [ ] 4.2 Lint changed Markdown: `npx markdownlint-cli2 --fix AGENTS.md plugins/soleur/skills/compound/SKILL.md plugins/soleur/skills/work/SKILL.md plugins/soleur/skills/pencil-setup/SKILL.md knowledge-base/project/specs/feat-agents-rule-threshold/spec.md <learning-file>`.
- [ ] 4.3 Stage AGENTS.md and run `python3 scripts/lint-rule-ids.py AGENTS.md` — exits 0.
- [ ] 4.4 `lefthook run pre-commit --files <changed files>` — exits 0.
- [ ] 4.5 Create `scripts/lint-agents-compound-sync.sh` (5–8 bash lines): extract threshold literal from `AGENTS.md` L81 and compound SKILL.md L205; exit 1 if disagree. Make executable. Wire into `lefthook.yml` pre-commit with `glob: "{AGENTS.md,plugins/soleur/skills/compound/SKILL.md}"`. Verify OK-state, then temporarily edit one file to exit-1 state, confirm, revert.
- [ ] 4.6 File Issue A: `chore(agents-md): amend lint-rule-ids.py to support retired-ids allowlist` — milestone "Post-MVP / Later", label `type/chore`, body cites this PR + deprecation learning + proposes file-based allowlist format.
- [ ] 4.7 Write `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` with: the 3 migrated IDs + destinations, pointer-preservation pattern definition, rejected merged-tag alternative with rationale, why 115 was chosen (not 120), link to Issue A.
- [ ] 4.8 Update spec `knowledge-base/project/specs/feat-agents-rule-threshold/spec.md`: strikethrough original FR4, append relaxed replacement; mark FR5 as satisfied by research.
- [ ] 4.9 Update PR #2754 body: summary, migrated-rule table, baseline/after counts, `Closes #2686`, link to Issue A.

## 5. Ship

- [ ] 5.1 `soleur:review` (spawn reviewers on final branch state).
- [ ] 5.2 `soleur:ship` — semver label `patch` (bug-free maintenance PR).
- [ ] 5.3 Post-merge: verify Sunday 2026-04-26 scheduled aggregator run succeeds and the resulting `rule-metrics.json` PR has no orphan warnings for the 3 migrated IDs.
