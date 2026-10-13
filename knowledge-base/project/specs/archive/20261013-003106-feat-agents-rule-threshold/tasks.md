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

- [x] 1.1 Capture baseline: rules=106, bytes=36566, longest=582.
- [x] 1.2 Verify aggregator: last scheduled run 2026-04-19 01:16 UTC succeeded (run 24617976419). No follow-up issue needed.
- [x] 1.3 Confirm migration targets still carry enforcement tags on main.

## 2. Threshold Raise (100 → 115)

- [x] 2.1 Edit `AGENTS.md` (`cq-agents-md-why-single-line`): `>100 rules` → `>115 rules` with tight `**Why:** #2686` one-liner.
- [x] 2.2 Edit `plugins/soleur/skills/compound/SKILL.md` step 8: `A > 100` → `A > 115`; `(A/100)` → `(A/115)`.
- [x] 2.3 Read-back confirmed — only the two new `115` references in threshold context.

## 3. Skill-Migration Pattern Proof (3 rules, pointer-preservation)

- [x] 3.1 Migrated `cq-after-completing-a-playwright-task-call` → `plugins/soleur/hooks/browser-cleanup-hook.sh` header; AGENTS.md now a pointer.
- [x] 3.2 Migrated `cq-before-calling-mcp-pencil-open-document` → `.claude/hooks/pencil-open-guard.sh` header + `plugins/soleur/skills/pencil-setup/SKILL.md` §"Untracked .pen safety"; AGENTS.md now a pointer.
- [x] 3.3 Migrated `wg-when-a-research-sprint-produces` → `plugins/soleur/skills/work/SKILL.md` §Phase 2.5; AGENTS.md now a pointer.
- [x] 3.4 Sanity-check diff of `[id: ...]` tags HEAD vs working copy — empty (no IDs removed).

## 4. Verification, Sync Guard, Follow-up

- [x] 4.1 Post-migration (after review-pass): rules=106 (flat), bytes=36587 (+21 vs baseline — plan's 800-byte target was aspirational; see learning), longest=582 (≤600). Spec FR4 relaxed accordingly.
- [x] 4.2 Markdown lint passed on all 6 changed files (0 errors).
- [x] 4.3 `python3 scripts/lint-rule-ids.py AGENTS.md` exits 0 (pointer-preservation honored).
- [x] 4.4 `lefthook run pre-commit` passes (rule-id-lint, markdown-lint, agents-compound-sync, plugin-component-test 1135 pass, generate-kb-index — 12.6s).
- [x] 4.5 Created `scripts/lint-agents-compound-sync.sh` (executable), wired into `lefthook.yml` with glob on both files; OK-state verified, fail-state simulated and reverted.
- [x] 4.6 Filed Issue #2762 — `chore(agents-md): amend lint-rule-ids.py to support retired-ids allowlist`, milestone "Post-MVP / Later", label `type/chore`.
- [x] 4.7 Wrote `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`.
- [x] 4.8 Updated spec: FR4 strikethrough + relaxed replacement; FR5 marked satisfied by research.
- [x] 4.9 Updated PR #2754 body (summary, migrated-rule table, baseline/after counts, `Closes #2686`, link to Issue #2762).

## 5. Ship

- [ ] 5.1 `soleur:review` (spawn reviewers on final branch state).
- [ ] 5.2 `soleur:ship` — semver label `patch` (bug-free maintenance PR).
- [ ] 5.3 Post-merge: verify Sunday 2026-04-26 scheduled aggregator run succeeds and the resulting `rule-metrics.json` PR has no orphan warnings for the 3 migrated IDs.
