---
title: "chore: add defense-in-depth branch guards to brainstorm and plan skills"
type: fix
date: 2026-03-05
---

# chore: add defense-in-depth branch guards to brainstorm and plan skills

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
**Insert after:** line 35 (the `cat CLAUDE.md` / `fi` block closing)
**Insert before:** line 37 ("Plugin loader constraint" paragraph)

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
**Insert after:** line 31 (the `cat CLAUDE.md` / `fi` block closing)
**Insert before:** line 33 ("Check for knowledge-base directory and load context")

## Acceptance Criteria

- [ ] `brainstorm/SKILL.md` aborts on main/master before writing any files (`plugins/soleur/skills/brainstorm/SKILL.md`)
- [ ] `plan/SKILL.md` aborts on main/master before writing any files (`plugins/soleur/skills/plan/SKILL.md`)
- [ ] Guard phrasing matches compound/ship: "defense-in-depth alongside PreToolUse hooks"
- [ ] Guard placement is before any file-writing or research phases
- [ ] No other behavioral changes to either skill

## Test Scenarios

- Given the brainstorm skill is invoked on main, when Phase 0 runs, then it aborts with "Error: brainstorm cannot run on main/master"
- Given the brainstorm skill is invoked on a feature branch, when Phase 0 runs, then it proceeds normally
- Given the plan skill is invoked on main, when Phase 0 runs, then it aborts with "Error: plan cannot run on main/master"
- Given the plan skill is invoked on a feature branch, when Phase 0 runs, then it proceeds normally

## Non-goals

- Adding guards to skills that already have them (ship, compound, work)
- Adding guards to skills where running on main is intentional (sync, help, go)
- Modifying PreToolUse hooks
- Adding automated test infrastructure for guard behavior

## References

- Parent issue: #419
- Ship guard: `plugins/soleur/skills/ship/SKILL.md:34`
- Compound guard: `plugins/soleur/skills/compound/SKILL.md:28`
- Work guard: `plugins/soleur/skills/work/SKILL.md:64`
- GitHub issue: #447

## Semver

`semver:patch` -- no new capabilities, consistency improvement only.
