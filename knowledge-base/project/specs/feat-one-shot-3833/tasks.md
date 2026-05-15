---
title: "tasks: shrink B_ALWAYS below 22,000-byte critical threshold"
issue: "#3833"
plan: knowledge-base/project/plans/2026-05-15-chore-agents-shrink-b-always-below-22000-plan.md
branch: feat-one-shot-3833
lane: cross-domain
---

# Tasks — chore(AGENTS): shrink B_ALWAYS below 22,000

## 1. Setup / preconditions

- 1.1 Confirm CWD is the worktree (`pwd` ends in `.worktrees/feat-one-shot-3833`).
- 1.2 Re-run `python3 scripts/lint-agents-rule-budget.py`; record baseline `B_ALWAYS` (expected 22,687).
- 1.3 Read `scripts/retired-rule-ids.txt` header (lines 1-22) to confirm entry format.
- 1.4 Cross-reference sweep: `grep -rln "hr-no-dashboard-eyeball-pull-data-yourself" --include='*.md' --include='*.sh' --include='*.py' --include='*.ts' .` excluding `knowledge-base/project/{plans,specs,brainstorms,learnings}`. Expected matches: `AGENTS.md`, `AGENTS.core.md` only.

## 2. Core implementation (single atomic commit)

- 2.1 **Retire** `hr-no-dashboard-eyeball-pull-data-yourself`:
  - 2.1.1 Delete the index pointer line at `AGENTS.md:25` (`- [id: hr-no-dashboard-eyeball-pull-data-yourself] → core`).
  - 2.1.2 Delete the rule body line at `AGENTS.core.md:34`.
  - 2.1.3 Append to `scripts/retired-rule-ids.txt`: `hr-no-dashboard-eyeball-pull-data-yourself | 2026-05-15 | PR #<this-PR-N> | knowledge-base/project/learnings/2026-05-13-no-dashboard-eyeball-pull-data-yourself.md`. Use the actual draft PR number (#3837 or its successor).
- 2.2 **Trim 1** — `hr-ssh-diagnosis-verify-firewall` at `AGENTS.core.md:26`:
  - Replace the Why tail `**Why:** #2681 — #2654 plan had sshd hypotheses; cause was admin-IP drift.` with `**Why:** #2681.`
- 2.3 **Trim 2** — `hr-when-triaging-a-batch-of-issues-never` at `AGENTS.core.md:14`:
  - Replace the Why tail `**Why:** #2075 deferred OG image gen despite \`gemini-imagegen\` being available.` with `**Why:** #2075.`

## 3. Verify (BEFORE commit)

- 3.1 `python3 scripts/lint-agents-rule-budget.py` exits 0 with `B_ALWAYS ≤ 22,000`. Record the exact byte total.
- 3.2 `python3 scripts/lint-rule-ids.py` exits 0 (retired ID allowed via `retired-rule-ids.txt`).
- 3.3 `bash scripts/lint-agents-rule-budget.test.sh` passes.
- 3.4 `bash .claude/hooks/session-rules-loader.test.sh` passes.
- 3.5 `bash .claude/hooks/session-rules-loader-headless.test.sh` passes.
- 3.6 Citation greps:
  - `grep -F "**Why:** #2681." AGENTS.core.md` returns 1 match.
  - `grep -F "**Why:** #2075." AGENTS.core.md` returns 1 match.
  - `grep -F "hr-no-dashboard-eyeball-pull-data-yourself" AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` returns 0 matches.
  - `grep -F "hr-no-dashboard-eyeball-pull-data-yourself" scripts/retired-rule-ids.txt` returns 1 match.
- 3.7 If `B_ALWAYS > 22,000` after the planned trims, add a spare Why-trim from the plan's spare candidates (`hr-gdpr-gate-on-regulated-data-surfaces` Why or `wg-when-a-workflow-gap-causes-a-mistake-fix` Why) BEFORE committing. Do NOT use `LEFTHOOK=0`.

## 4. Commit (atomic)

- 4.1 `git add AGENTS.md AGENTS.core.md scripts/retired-rule-ids.txt` (and `knowledge-base/project/plans/` + `knowledge-base/project/specs/` for the plan artifacts if not already committed).
- 4.2 Single commit with the message body documenting the retirement + trims and `Closes #3833`.
- 4.3 `git push`.
- 4.4 Atomic-commit invariant: `git log --oneline origin/main..HEAD -- AGENTS.md AGENTS.core.md scripts/retired-rule-ids.txt | wc -l` returns exactly `1`.

## 5. Ship

- 5.1 Convert draft PR #3837 (or successor) to ready: `gh pr ready <N>`.
- 5.2 Apply semver labels per `/ship` skill.
- 5.3 Auto-merge: `gh pr merge <N> --squash --auto`.
- 5.4 Poll until MERGED; then `cleanup-merged`.
- 5.5 Post-merge: none (no infra/deploy).
