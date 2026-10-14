---
lane: "procedural"
issue: "#3667"
plan: "../../plans/2026-05-12-feat-route-to-definition-plan-review-skills-plan.md"
---

# Tasks: Route-to-definition for plan + review skills (#3667)

Derived from `2026-05-12-feat-route-to-definition-plan-review-skills-plan.md`. Atomic, single-PR markdown-only edit.

## 1. Setup

- [ ] 1.1. Verify working tree is on branch `feat-one-shot-3667-route-to-definition` and inside the worktree at `.worktrees/feat-one-shot-3667-route-to-definition/`.
- [ ] 1.2. `git pull --rebase origin main` to ensure no drift behind main.
- [ ] 1.3. Confirm source files are at expected line ranges:
  - [ ] 1.3.1. `awk 'NR==686 || NR==758' plugins/soleur/skills/plan/SKILL.md` — line 686 should be `## Sharp Edges`, line 758 should be the current last bullet (hyphenated-Python-module entry citing PR #2723).
  - [ ] 1.3.2. `awk 'NR==764 || NR==777 || NR==779' plugins/soleur/skills/review/SKILL.md` — line 764 should be `### Defect Classes This Review Reliably Catches`, line 777 should be the last current bullet (PR #3521 vendor-pipeline), line 779 should start with `See knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`.
  - [ ] 1.3.3. If any of the above line numbers have drifted, recompute the insertion targets by anchoring to the surrounding text (last `**Why:** PR #2723` for plan/SKILL.md; last `multi-agent-review-vendor-pipeline-trust-model.md` for review/SKILL.md) before editing.

## 2. Core Implementation

### 2.1. `plan/SKILL.md` — three Sharp Edges bullets

- [ ] 2.1.1. Append **Bullet 1 (FR1 — Precondition grep)** at the end of `## Sharp Edges`, mirroring the existing `- When a plan …` paragraph format. Verbatim text per plan Phase 1 / Bullet 1.
- [ ] 2.1.2. Append **Bullet 2 (FR2 — Parametrized test list ↔ component prop boundary)** immediately after Bullet 1. Verbatim text per plan Phase 1 / Bullet 2.
- [ ] 2.1.3. Append **Bullet 3 (FR3 — Enum-gate enumeration)** immediately after Bullet 2. Verbatim text per plan Phase 1 / Bullet 3.

### 2.2. `review/SKILL.md` — one Defect Classes bullet

- [ ] 2.2.1. Append **Bullet 4 (FR4 — Single-literal gate over multi-member union/enum)** to the end of `### Defect Classes This Review Reliably Catches`, BEFORE the closing `See knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md ...` line. Verbatim text per plan Phase 2 / Bullet 4.
- [ ] 2.2.2. Verify the bullet mirrors the **bold lead clause** + em-dash + body + `Reviewer takeaway:` + `**Why:** PR #N — … See <path>.` shape used by sibling entries.

## 3. Testing & Verification

- [ ] 3.1. **AC1.** `grep -c "PR #3653" plugins/soleur/skills/plan/SKILL.md` returns ≥ 3.
- [ ] 3.2. **AC2.** `grep -c "PR #3653" plugins/soleur/skills/review/SKILL.md` returns ≥ 1.
- [ ] 3.3. **AC3.** `grep -h "2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md" plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/review/SKILL.md | wc -l` returns ≥ 4. (Use `-h` to suppress filename prefixes and `| wc -l` to produce a single summed integer; bare `grep -c` returns per-file `file:count` rows, not a sum.)
- [ ] 3.4. **AC4.** `grep -nE "precondition.*grep|grep.*precondition|producing-scope|producing scope" plugins/soleur/skills/plan/SKILL.md` returns ≥ 1 match at line ≥ 686.
- [ ] 3.5. **AC5.** `grep -nE "test\.each|parametrized test|test list" plugins/soleur/skills/plan/SKILL.md | grep -iE "prop boundary|component"` returns ≥ 1 match.
- [ ] 3.6. **AC6.** `grep -nE "enum-gate|enum gate|every union member|every member of the union|classify every" plugins/soleur/skills/plan/SKILL.md` returns ≥ 1 match.
- [ ] 3.7. **AC7.** `grep -nE "every union member|enumerate every|classify every|multi-member union" plugins/soleur/skills/review/SKILL.md` returns ≥ 1 match between lines 764 and ~785.
- [ ] 3.8. **AC8.** `bun test plugins/soleur/test/components.test.ts` passes.
- [ ] 3.9. **AC9.** `git diff origin/main...HEAD --name-only` lists exactly two paths.
- [ ] 3.10. **Markdown lint** — if a project-wide markdown linter is configured, run it against the two edited files. If none is configured, skip silently.

## 4. Ship

- [ ] 4.1. Stage both files: `git add plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/review/SKILL.md`.
- [ ] 4.2. Commit with body referencing #3667, #3653, and the source learning file path.
- [ ] 4.3. Push branch.
- [ ] 4.4. Open PR with `Closes #3667` in the body; reference `Ref #3653` and link the source learning.
- [ ] 4.5. Run plan-review trio + (per the verbatim-prose-plan deviation in `review/SKILL.md`) the 3-agent slice `pattern-recognition-specialist`, `security-sentinel`, `code-simplicity-reviewer` instead of the full 8 — documented deviation rationale in the classification announcement.
- [ ] 4.6. Address P1 findings inline; merge once green.
- [ ] 4.7. Post-merge: confirm #3667 auto-closed and #3653 references are intact.
