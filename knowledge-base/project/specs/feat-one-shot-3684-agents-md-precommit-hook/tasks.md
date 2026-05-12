---
title: "Tasks: pre-commit hook for AGENTS.md rule-budget + skill-enforced-anchor parity"
issue: 3684
branch: feat-one-shot-3684-agents-md-precommit-hook
plan: knowledge-base/project/plans/2026-05-12-chore-agents-md-precommit-hook-rule-budget-anchor-parity-plan.md
lane: single-domain
---

# Tasks: pre-commit hook for AGENTS.md rule-budget + skill-enforced-anchor parity

## Phase 1: Setup + RED tests (TDD scaffold)

- [ ] 1.1 Re-Read `scripts/lint-rule-ids.py`, `scripts/lint-agents-enforcement-tags.py`, `lefthook.yml`, `plugins/soleur/skills/compound/SKILL.md` (lines 196-250), `.github/workflows/scheduled-compound-promote.yml` (lines 145-205) per `hr-always-read-a-file-before-editing-it`.
- [ ] 1.2 Run `bash scripts/test-all.sh` and capture baseline-green output. Verify the test runner's `find` glob covers `scripts/**/*.test.sh`.
- [ ] 1.3 Re-run open-PR / open-issue overlap check from plan §Open Code-Review Overlap.
- [ ] 1.4 Write `scripts/lint-agents-rule-budget.test.sh` (RED). Three branches: 19,500 B silent / 21,000 B warn / 22,500 B error.
- [ ] 1.5 Write `scripts/lint-agents-enforcement-tags.test.sh` (RED). Four branches: single-skill resolved / multi-skill resolved / one dangling segment / dangling segment in allowlist.
- [ ] 1.6 Confirm both new tests fail with the expected RED reason.

## Phase 2: Shared library

- [ ] 2.1 Create `scripts/lib/agents-payload-bytes.sh` with `compute_b_always()` (env-var-overridable paths).
- [ ] 2.2 Update `plugins/soleur/skills/compound/SKILL.md` step 8 to source the library; update warn threshold 18 k → 20 k in the advisory block (lines 220, 226).
- [ ] 2.3 Update `.github/workflows/scheduled-compound-promote.yml` lines 148-160 and 198-203 to source the library.
- [ ] 2.4 Verify all three callers produce identical byte counts for the live AGENTS payload.

## Phase 3: Rule-budget hook (GREEN)

- [ ] 3.1 Implement `scripts/lint-agents-rule-budget.sh` per plan AC2.
- [ ] 3.2 Iterate until 1.4 is GREEN.
- [ ] 3.3 Add `agents-rule-budget` command to `lefthook.yml` priority 5 (path-array glob).
- [ ] 3.4 Manual repro: empty commit succeeds (no AGENTS file staged).
- [ ] 3.5 Manual repro: synthetic AGENTS.core.md edit at 22,500 B → commit rejected with `::error::` annotation naming byte delta.

## Phase 4: Anchor-parity check (GREEN)

- [ ] 4.1 Extend `scripts/lint-agents-enforcement-tags.py` with `--check-anchors` flag, multi-skill segment parser (split `<rest>` on `,`), allowlist consultation per plan AC3.
- [ ] 4.2 Create `scripts/agents-anchor-ignore.txt` with header comment matching `scripts/retired-rule-ids.txt` style.
- [ ] 4.3 Add allowlist self-validation per plan AC5 (every `<skill>` in allowlist resolves to a real `plugins/soleur/skills/<skill>/SKILL.md`).
- [ ] 4.4 Iterate until 1.5 is GREEN.
- [ ] 4.5 Add `agents-skill-enforced-anchor` command to `lefthook.yml` priority 5 with the multi-glob from plan AC4.
- [ ] 4.6 Run `python3 scripts/lint-agents-enforcement-tags.py --check-anchors AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` against live repo. If any segment fails, fix in-skill OR update tag OR allowlist with rationale comment.

## Phase 5: Verification + manual reproductions

- [ ] 5.1 Run `bash scripts/test-all.sh` end-to-end; assert all linters + 38 plugin test suites green.
- [ ] 5.2 Stage `[skill-enforced: nonexistent-skill Phase 99]` edit → commit rejected. Capture output for PR body.
- [ ] 5.3 Stage AGENTS.core.md addition pushing payload past 22 k → commit rejected. Capture output for PR body.
- [ ] 5.4 Verify `git commit --allow-empty` succeeds (no false-fire).

## Phase 6: Plan-prescribed skills + ship

- [ ] 6.1 `/soleur:compound` — capture any session learnings.
- [ ] 6.2 `/soleur:review` — multi-agent review on PR diff.
- [ ] 6.3 Resolve any review findings inline per `rf-review-finding-default-fix-inline`.
- [ ] 6.4 `/soleur:qa` — functional QA before merge.
- [ ] 6.5 `/soleur:ship` — Phase 5.5 review-findings exit gate, Phase 5.5 retroactive-gate-application check, Phase 7 release-workflow verification.
