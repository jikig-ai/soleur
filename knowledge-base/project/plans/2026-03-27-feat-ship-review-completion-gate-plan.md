---
title: "feat: add review completion gate to /ship skill"
type: feat
date: 2026-03-27
---

# feat: add review completion gate to /ship skill

## Overview

The `/ship` skill has no verification that `/review` was executed before creating and merging a PR. When invoked directly (bypassing `/one-shot`), unreviewed code can reach production. This plan adds a review evidence check to `/ship` that blocks or warns when no review evidence exists.

## Problem Statement

The `/one-shot` pipeline enforces the correct order: work -> review -> resolve-todos -> compound -> ship. But `/ship` as a standalone skill has no defense-in-depth check. Three gaps exist:

1. **Direct `/ship` invocation** -- a user running `/work` then `/ship` (skipping `/review`) ships unreviewed code
2. **Direct `/work` invocation** -- when invoked directly (not via one-shot), work's Phase 4 chains directly to compound -> ship, skipping review entirely
3. **Manual merge** -- draft PRs exist on GitHub before review completes; a manual merge is possible (out-of-scope: branch protection rules are the correct mitigation; that is a separate configuration task)

**Threat model:** The work Phase 4 change prevents gaps 1 and 2 (the primary fix). The ship Phase 1.5 gate is defense-in-depth for direct `/ship` invocations that bypass `/work`.

Source: #1170, identified during #1129/#1131/#1134 implementation session.

## Proposed Solution

Add a new **Phase 1.5: Review Evidence Gate** to `/ship` SKILL.md, inserted between the existing Phase 1 (Validate Artifact Trail) and Phase 2 (Capture Learnings).

### Review Evidence Detection

Check for evidence that `/review` ran on the current branch, using two signals (stop at first match):

| Signal | Detection Method | Confidence |
|--------|-----------------|------------|
| `todos/` directory with review-tagged files | `grep -rl "code-review" todos/ 2>/dev/null` | High -- review creates todo files tagged `code-review` |
| Commit message pattern | `git log origin/main..HEAD --oneline` matching `refactor: add code review findings` | High -- review instructs this exact commit message (coupled to review SKILL.md Step 5; if that message changes, update this grep) |

**Zero-finding reviews:** If `/review` runs and finds no issues, no todo files are created and no review commit exists. The gate falls through to "no evidence found." In interactive mode, "Skip review" handles this case -- the user confirms review ran cleanly. In headless mode, this is an acceptable false negative: zero-finding reviews are rare in practice, and the one-shot pipeline (the primary headless caller) creates its own evidence via the review step.

### Gate Behavior

**If review evidence found:** Continue silently. Log which signal matched.

**If no review evidence found:**

- **Interactive mode:** Present a warning and ask:
  - "No evidence that `/review` ran on this branch. How would you like to proceed?"
  - Options: **Run review now** (invoke `skill: soleur:review`), **Skip review** (continue with acknowledgment), **Abort** (stop shipping)
- **Headless mode:** Abort with error message: "Error: no review evidence found. Run `/review` before `/ship` or use `/one-shot` for the full pipeline." Headless mode is used by automated pipelines where unreviewed code must never ship silently.

### Work Skill Phase 4 Fix

Additionally, update `/work` SKILL.md Phase 4's direct-invocation path to insert `/review` before `/ship`:

**Current direct-invocation chain:** compound -> ship

**Updated direct-invocation chain:** review -> resolve-todo-parallel -> compound -> ship

This ensures that even when a user runs `/work` standalone, review happens before shipping.

## Technical Approach

### Files to Modify

1. **`plugins/soleur/skills/ship/SKILL.md`** -- add Phase 1.5: Review Evidence Gate between Phase 1 and Phase 2
2. **`plugins/soleur/skills/work/SKILL.md`** -- update Phase 4 direct-invocation chain to include review

### Phase 1.5 Implementation Detail

Insert after the Phase 1 section (line ~68 in ship/SKILL.md), before Phase 2:

```markdown
## Phase 1.5: Review Evidence Gate

Check for evidence that `/review` ran on the current branch. This is defense-in-depth --
`/one-shot` already enforces review ordering, but direct `/ship` invocations bypass it.

**Step 1: Check for review artifacts.**

Search for todo files tagged as code-review findings:

```bash
grep -rl "code-review" todos/ 2>/dev/null | head -1
```

**Step 2: Check commit history for review evidence.**

If Step 1 found nothing, check for the review commit pattern:

```bash
git log origin/main..HEAD --oneline | grep "refactor: add code review findings"
```

**If either step found evidence:** Continue to Phase 2. Log: "Review evidence found via [signal]."

**If no evidence found:**

**Headless mode:** Abort: "Error: no review evidence found on this branch. Run `/review` before
`/ship`, or use `/one-shot` for the full pipeline."

**Interactive mode:** Present options via AskUserQuestion:

- **Run /review now** -> invoke `skill: soleur:review`, then continue to Phase 2
- **Skip review** -> continue to Phase 2 (user accepts risk)
- **Abort** -> stop

```

### Work SKILL.md Phase 4 Update

In the "invoked directly by the user" section, change the step sequence from:

```text
1. skill: soleur:compound
2. skill: soleur:ship
```

To:

```text
1. skill: soleur:review
2. skill: soleur:resolve-todo-parallel
3. skill: soleur:compound
4. skill: soleur:ship
```

## Acceptance Criteria

- [ ] `/ship` Phase 1.5 detects `todos/` files tagged `code-review` as review evidence
- [ ] `/ship` Phase 1.5 detects `refactor: add code review findings` commit message as review evidence
- [ ] `/ship` in headless mode aborts when no review evidence is found
- [ ] `/ship` in interactive mode presents Run/Skip/Abort options when no review evidence is found
- [ ] `/work` Phase 4 direct-invocation path includes review and resolve-todo-parallel before compound and ship
- [ ] One-shot pipeline continues to work unchanged (review evidence is created by step 4)

## Test Scenarios

- Given a branch with `todos/` files tagged `code-review`, when `/ship` runs, then Phase 1.5 passes silently
- Given a branch with a `refactor: add code review findings` commit, when `/ship` runs, then Phase 1.5 passes silently
- Given a branch with non-review todo files (no `code-review` tag), when `/ship` runs, then Phase 1.5 does NOT treat them as review evidence
- Given a branch with no review artifacts and headless mode, when `/ship` runs, then it aborts with a clear error message
- Given a branch with no review artifacts and interactive mode, when `/ship` runs, then it presents Run/Skip/Abort options
- Given `/review` ran with zero findings (no todos created, no commit), when `/ship` runs in interactive mode, then user can select "Skip review" to proceed
- Given `/work` invoked directly (not via one-shot), when Phase 4 runs, then it chains: review -> resolve-todo-parallel -> compound -> ship

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is a pure workflow tooling change modifying two SKILL.md files within the plugin. No infrastructure, legal, marketing, product, or operational implications. The CTO assessment: straightforward defense-in-depth gate following established patterns (Phase N.5 conditional gates already exist in `/ship` at Phase 5.5 and Phase 6.5). Risk is low -- the gate is additive and has explicit skip paths for user override.

## References

- Issue: #1170
- Learning: `knowledge-base/project/learnings/2026-02-26-decouple-work-from-ship-review-before-merge.md`
- Learning: `knowledge-base/project/learnings/2026-03-25-plan-review-simplifies-gate-design.md`
- Ship SKILL.md: `plugins/soleur/skills/ship/SKILL.md`
- Work SKILL.md: `plugins/soleur/skills/work/SKILL.md`
- Review SKILL.md: `plugins/soleur/skills/review/SKILL.md`
- One-shot SKILL.md: `plugins/soleur/skills/one-shot/SKILL.md`
