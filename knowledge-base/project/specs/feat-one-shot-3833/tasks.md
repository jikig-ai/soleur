---
title: "tasks: shrink B_ALWAYS below 22,000-byte critical threshold"
issue: "#3833"
plan: knowledge-base/project/plans/2026-05-15-chore-agents-shrink-b-always-below-22000-plan.md
branch: feat-one-shot-3833
lane: cross-domain
---

# Tasks — chore(AGENTS): shrink B_ALWAYS below 22,000 (v3: demote + 6 Why-trims)

## 1. Setup / preconditions

- 1.1 Confirm CWD is the worktree.
- 1.2 Re-run `python3 scripts/lint-agents-rule-budget.py`; baseline `B_ALWAYS = 22,687`.
- 1.3 Verify loader regex unchanged: `sed -n '99,126p' .claude/hooks/session-rules-loader.sh`.

## 2. Phase 1 — Demote `wg-after-merging-a-pr-that-adds-or-modifies`

- 2.1 `AGENTS.md:59`: change `→ core` to `→ rest` for the demoted rule. Zero byte delta.
- 2.2 `AGENTS.core.md:52`: delete the rule body line. −352 B.
- 2.3 `AGENTS.rest.md`: append the deleted line verbatim to `## Workflow Gates` after line 18.

## 3. Phase 2 — Why-trims (6 rules)

- 3.1 Trim 1 — `hr-no-dashboard-eyeball-pull-data-yourself` (AGENTS.core.md:34):
  - Replace `**Why:** #3356; see \`knowledge-base/project/learnings/2026-05-13-no-dashboard-eyeball-pull-data-yourself.md\`.` → `**Why:** #3356.` (−94 B)
- 3.2 Trim 2 — `hr-when-a-plan-specifies-relative-paths-e-g` (AGENTS.core.md:9):
  - Replace `(PR #2889 — \`infra/**\` matched zero paths; gate missed \`middleware.ts\` / \`app/api/**\`).` → `(PR #2889 — \`infra/**\` matched zero paths).` (−~57 B; preserves `infra/**` example per Kieran P2.1)
- 3.3 Trim 3 — `hr-when-triaging-a-batch-of-issues-never` (AGENTS.core.md:14):
  - Replace `**Why:** #2075 deferred OG image gen despite \`gemini-imagegen\` being available.` → `**Why:** #2075.` (−64 B)
- 3.4 Trim 4 — `hr-ssh-diagnosis-verify-firewall` (AGENTS.core.md:26):
  - Replace `**Why:** #2681 — #2654 plan had sshd hypotheses; cause was admin-IP drift.` → `**Why:** #2681.` (−61 B)
- 3.5 Trim 5 — `wg-when-a-workflow-gap-causes-a-mistake-fix` (AGENTS.core.md:51):
  - Replace `**Why:** #2430 committed a verbal promise instead of a skill edit.` → `**Why:** #2430.` (−51 B)
- 3.6 Trim 6 — `hr-gdpr-gate-on-regulated-data-surfaces` (AGENTS.core.md:31):
  - Replace `**Why:** EU \`single-user incident\` threshold; pre-generation catch beats post-hoc audit.` → `**Why:** EU single-user threshold.` (−~54 B)

## 4. Phase 3 — Verify BEFORE commit

- 4.1 `python3 scripts/lint-agents-rule-budget.py` exits 0 with `B_ALWAYS ≤ 22,000`. Record byte total.
- 4.2 `python3 scripts/lint-rule-ids.py` exits 0.
- 4.3 `bash scripts/lint-agents-rule-budget.test.sh` passes.
- 4.4 `bash .claude/hooks/session-rules-loader.test.sh` passes.
- 4.5 `bash .claude/hooks/session-rules-loader-headless.test.sh` passes.
- 4.6 Citation greps (each must return 1 match):
  - `grep -F "**Why:** #3356." AGENTS.core.md`
  - `` grep -F "(PR #2889 — \`infra/**\` matched zero paths)." AGENTS.core.md ``
  - `grep -F "**Why:** #2075." AGENTS.core.md`
  - `grep -F "**Why:** #2681." AGENTS.core.md`
  - `grep -F "**Why:** #2430." AGENTS.core.md`
  - `grep -F "**Why:** EU single-user threshold." AGENTS.core.md`
- 4.7 Index pointer: `grep -F "[id: wg-after-merging-a-pr-that-adds-or-modifies]" AGENTS.md` returns the `→ rest` line.
- 4.8 Body relocation: `grep -F "[id: wg-after-merging-a-pr-that-adds-or-modifies]" AGENTS.core.md` returns 0 matches; same grep on `AGENTS.rest.md` returns 1 match.
- 4.9 If `B_ALWAYS > 22,000`, add a 7th Why-trim from the spare candidates BEFORE committing. Do NOT use `LEFTHOOK=0`.

## 5. Atomic commit

- 5.1 `git add AGENTS.md AGENTS.core.md AGENTS.rest.md`
- 5.2 Single commit with the body documenting demote + trims + `Closes #3833`.
- 5.3 `git push`.
- 5.4 Atomic-commit invariant verify: `git log --oneline origin/main..HEAD -- AGENTS.md AGENTS.core.md AGENTS.rest.md | wc -l` returns `1` (demote+trims commit only; plan/tasks commits don't touch AGENTS).

## 6. Ship

- 6.1 `gh pr ready 3837` (or successor).
- 6.2 Apply semver labels.
- 6.3 `gh pr merge <N> --squash --auto`; poll; cleanup-merged.
- 6.4 Post-merge: none.
