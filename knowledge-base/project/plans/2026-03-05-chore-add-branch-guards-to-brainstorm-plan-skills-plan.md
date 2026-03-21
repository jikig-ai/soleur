---
title: "chore: add defense-in-depth branch guards to brainstorm and plan skills"
type: fix
date: 2026-03-05
---

# chore: add defense-in-depth branch guards to brainstorm and plan skills

## Enhancement Summary

**Deepened on:** 2026-03-05
**Sections enhanced:** 4 (Implementation, Acceptance Criteria, Test Scenarios, References)
**Research sources:** Institutional learnings (3 files), codebase pattern analysis (5 guard implementations)

### Key Improvements

1. Verified exact insertion line numbers against live file content (brainstorm line 35, plan line 31)
2. Added edge case analysis: `work` skill uses different phrasing ("FAIL" vs "defense-in-depth") -- out of scope but documented
3. Added verification checklist from guard-testing learning (`2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md`)
4. Confirmed guard must fire before Phase 0.5 (Domain Leader Assessment) in brainstorm and before Phase 0.5 (Idea Refinement) in plan -- both write files or spawn agents

### Institutional Knowledge Applied

- **Guard pattern evolution** (from `2026-02-26-worktree-enforcement-pretooluse-hook.md`): Hook-based enforcement beats documentation-based rules. This task adds a second enforcement layer (skill instructions) that fires when hooks are unavailable.
- **Chain-operator bypass** (from `2026-02-24-guardrails-chained-commit-bypass.md`): Guard grep patterns must match at command boundaries, not just `^`. The branch guard in skills uses `git branch --show-current` output comparison (not grep), so this bypass class does not apply -- but worth noting for future guard reviewers.
- **CI hook verification** (from `2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md`): This issue (#447) was filed directly from the CI hook verification audit. The learning confirms: "Always add skill-level branch guards alongside hook guards (defense-in-depth)."

## Overview

The `brainstorm` and `plan` skills lack inline branch safety guards that prevent execution on `main`/`master`. While PreToolUse hooks provide the primary enforcement layer, `ship`, `compound`, and `work` all include defense-in-depth guards that fire even when hooks are unavailable (e.g., in CI). The `brainstorm` and `plan` skills should follow the same pattern for consistency.

## Problem Statement

Discovered during review of #419 (verify PreToolUse hooks in CI). Three of the five core workflow skills (`ship`, `compound`, `work`) have inline branch guards. Two (`brainstorm`, `plan`) do not. This creates an inconsistency: if PreToolUse hooks are unavailable, brainstorm and plan could write files directly to main.

## Proposed Solution

Add a **Branch safety check (defense-in-depth)** paragraph to both `brainstorm/SKILL.md` and `plan/SKILL.md`, matching the phrasing and placement used in `compound/SKILL.md`.

### Implementation

#### 1. `brainstorm/SKILL.md` -- Phase 0 guard

Insert a branch safety check paragraph immediately after the "Load project conventions" bash block in Phase 0 (Setup and Assess Requirements Clarity), before the "Plugin loader constraint" paragraph. The guard should:

- Run `git branch --show-current`
- If result is `main` or `master`, abort with: "Error: brainstorm cannot run on main/master. Checkout a feature branch first."
- Include the canonical phrasing: "defense-in-depth alongside PreToolUse hooks"

**Reference pattern** (`plugins/soleur/skills/compound/SKILL.md:28`):

```markdown
**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort immediately with: "Error: brainstorm cannot run on main/master. Checkout a feature branch first." This check fires in all modes as defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI).
```

**Target file:** `plugins/soleur/skills/brainstorm/SKILL.md`
**Insert after:** line 35 (`Read CLAUDE.md if it exists - apply project conventions during brainstorming.`)
**Insert before:** line 37 (`**Plugin loader constraint:**...`)

### Research Insight: Placement Rationale

The guard must fire before any of these downstream phases that write files or spawn agents:

- Phase 0.5: Domain Leader Assessment (spawns Task agents)
- Phase 1.1: Research (spawns repo-research-analyst, learnings-researcher)
- Phase 3: Create Worktree (creates directories)
- Phase 3.5: Capture the Design (writes brainstorm .md file)
- Phase 3.6: Create Spec and Issue (writes spec.md, creates GitHub issue)

Placing the guard immediately after convention loading (line 35) and before any decision logic ensures no side effects occur on main.

#### 2. `plan/SKILL.md` -- Phase 0 guard

Insert a branch safety check paragraph in Phase 0 (Load Knowledge Base Context), immediately after the "Load project conventions" bash block. The guard should:

- Run `git branch --show-current`
- If result is `main` or `master`, abort with: "Error: plan cannot run on main/master. Checkout a feature branch first."
- Include the canonical phrasing: "defense-in-depth alongside PreToolUse hooks"

**Reference pattern:**

```markdown
**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort immediately with: "Error: plan cannot run on main/master. Checkout a feature branch first." This check fires in all modes as defense-in-depth alongside PreToolUse hooks -- it fires even if hooks are unavailable (e.g., in CI).
```

**Target file:** `plugins/soleur/skills/plan/SKILL.md`
**Insert after:** line 31 (the `fi` closing the CLAUDE.md bash block)
**Insert before:** line 33 (`**Check for knowledge-base directory and load context:**`)

### Research Insight: Placement Rationale

The guard must fire before any of these downstream phases that write files or spawn agents:

- Phase 0.5: Idea Refinement (uses AskUserQuestion but could spawn agents)
- Phase 1: Local Research (spawns repo-research-analyst, learnings-researcher)
- Phase 3: SpecFlow Analysis (spawns spec-flow-analyzer)
- Phase 5: Issue Creation (writes plan .md file)
- Save Tasks: writes tasks.md, commits, pushes

Placing the guard immediately after convention loading (line 31) and before knowledge-base context loading ensures no file I/O occurs on main.

## Acceptance Criteria

- [x] `brainstorm/SKILL.md` aborts on main/master before writing any files (`plugins/soleur/skills/brainstorm/SKILL.md`)
- [x] `plan/SKILL.md` aborts on main/master before writing any files (`plugins/soleur/skills/plan/SKILL.md`)
- [x] Guard phrasing matches compound/ship: "defense-in-depth alongside PreToolUse hooks"
- [x] Guard placement is before any file-writing or research phases
- [x] No other behavioral changes to either skill

## Test Scenarios

- Given the brainstorm skill is invoked on main, when Phase 0 runs, then it aborts with "Error: brainstorm cannot run on main/master. Checkout a feature branch first."
- Given the brainstorm skill is invoked on a feature branch (e.g., `feat/branch-guards`), when Phase 0 runs, then it proceeds normally to Phase 0.5
- Given the plan skill is invoked on main, when Phase 0 runs, then it aborts with "Error: plan cannot run on main/master. Checkout a feature branch first."
- Given the plan skill is invoked on a feature branch, when Phase 0 runs, then it proceeds normally to Phase 0.5
- Given the brainstorm skill is invoked on `master` (alternate default branch name), when Phase 0 runs, then it aborts (both `main` and `master` are checked)

### Edge Cases

- **Detached HEAD:** Not covered by this guard (the `work` skill handles detached HEAD separately). The guard only checks for `main`/`master` specifically.
- **Headless mode:** The guard fires in all modes (headless and interactive), matching compound's behavior. There is no headless bypass.
- **Phrasing variance:** The `work` skill uses "FAIL:" prefix and different wording than compound/ship. This PR uses the compound/ship phrasing ("Error:") for consistency with the acceptance criteria. Normalizing `work` is out of scope.

## Non-goals

- Adding guards to skills that already have them (ship, compound, work)
- Adding guards to skills where running on main is intentional (sync, help, go)
- Modifying PreToolUse hooks
- Adding automated test infrastructure for guard behavior

## Verification Checklist

After implementation, run this grep to confirm all five core workflow skills have guards:

```bash
grep -l "defense-in-depth\|On default branch" plugins/soleur/skills/{brainstorm,plan,compound,ship,work}/SKILL.md
```

Expected: 5 files returned. If fewer, a guard is missing.

## References

### Issue and PR context

- Parent issue: #419 (verify PreToolUse hooks in CI)
- GitHub issue: #447

### Existing guard implementations (verified line numbers)

- Ship guard: `plugins/soleur/skills/ship/SKILL.md:34`
- Compound guard: `plugins/soleur/skills/compound/SKILL.md:28`
- Work guard: `plugins/soleur/skills/work/SKILL.md:64` (uses "FAIL:" phrasing, not "defense-in-depth")

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md` -- Direct parent: filed #447
- `knowledge-base/project/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md` -- Hook > docs enforcement pattern
- `knowledge-base/project/learnings/2026-02-24-guardrails-chained-commit-bypass.md` -- Guard pattern pitfalls (not applicable here but reviewed)

## Semver

`semver:patch` -- no new capabilities, consistency improvement only.
