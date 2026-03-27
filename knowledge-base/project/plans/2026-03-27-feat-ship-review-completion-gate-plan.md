---
title: "feat: add review completion gate to /ship skill"
type: feat
date: 2026-03-27
deepened: 2026-03-27
---

# feat: add review completion gate to /ship skill

## Enhancement Summary

**Deepened on:** 2026-03-27
**Sections enhanced:** 3 (Technical Approach, Implementation Detail, Work Phase 4 Update)
**Research sources:** Existing ship Phase 5.5/6.5 patterns, headless mode convention learning, pipeline continuation learnings, review SKILL.md todo structure

### Key Improvements From Deepening

1. Added explicit `--headless` forwarding requirements to work Phase 4 update
2. Added `|| true` guard on `grep` command to prevent pipefail exit in shell-script contexts
3. Added implementation note about `Abort` option language in pipeline-compatible phrasing
4. Documented insertion point precisely (after line 70 `**If no artifacts exist**` block, before `## Phase 2`)

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

Insert after Phase 1's `**If no artifacts exist**` block (line ~70 in ship/SKILL.md), before `## Phase 2: Capture Learnings`.

#### Research Insights

**Pattern consistency:** Phase 5.5 uses Trigger/Detection/If-triggered structure with headless/interactive branching. Phase 6.5 uses If-condition/action branching. Phase 1.5 should follow the Phase 5.5 pattern since it has the same dual-mode behavior.

**`grep -rl` edge case:** When the `todos/` directory does not exist, `grep -rl` returns exit code 2 (not 1). The `2>/dev/null` suppresses stderr, and the Bash tool does not use `pipefail`, so this is safe. However, add `|| true` as a defensive guard for future-proofing in case the command is extracted to a shell script with `set -euo pipefail`.

**Pipeline language:** The `Abort` option says "stop" which is fine because abort genuinely terminates the flow. But per the pipeline continuation learnings (2026-03-03), the `Run /review now` and `Skip review` paths must NOT use halt language -- they must explicitly say "continue to Phase 2."

**Exact text to insert:**

````markdown
## Phase 1.5: Review Evidence Gate

Check for evidence that `/review` ran on the current branch. This is defense-in-depth --
`/one-shot` already enforces review ordering, but direct `/ship` invocations bypass it.

**Step 1: Check for review artifacts.**

Search for todo files tagged as code-review findings:

```bash
grep -rl "code-review" todos/ 2>/dev/null | head -1 || true
```

**Step 2: Check commit history for review evidence.**

If Step 1 found nothing, check for the review commit pattern:

```bash
git log origin/main..HEAD --oneline | grep "refactor: add code review findings" || true
```

**If either step produced output:** Review evidence found. Continue to Phase 2.

**If both steps produced no output:**

**Headless mode:** Abort with: "Error: no review evidence found on this branch. Run `/review` before `/ship`, or use `/one-shot` for the full pipeline."

**Interactive mode:** Present options via AskUserQuestion:

"No evidence that `/review` ran on this branch. How would you like to proceed?"

- **Run /review now** -> invoke `skill: soleur:review`, then continue to Phase 2
- **Skip review** -> continue to Phase 2 (user accepts the risk; this also covers zero-finding reviews where review ran cleanly)
- **Abort** -> stop shipping

````

### Work SKILL.md Phase 4 Update

In the "invoked directly by the user" section (line ~370 in work/SKILL.md), change the step sequence.

#### Research Insights

**Headless forwarding (from learning 2026-03-03-headless-mode-skill-bypass-convention):** The `--headless` flag must be forwarded explicitly to each child skill invocation. The existing work Phase 4 already forwards to compound and ship. The new review and resolve-todo-parallel steps must also receive the flag. Use the same conditional pattern: `skill: soleur:review` or `skill: soleur:review --headless` if `HEADLESS_MODE=true`.

**Pipeline continuation (from learning 2026-03-03-skill-handoff-contradicts-pipeline-continuation):** The one-shot path must remain unchanged. The work skill already has separate code paths for one-shot vs direct invocation. Only the direct-invocation path changes.

**Exact change:**

Current text in the "invoked directly by the user" block:

```text
1. `skill: soleur:compound` (or `skill: soleur:compound --headless` if headless)
2. `skill: soleur:ship` (or `skill: soleur:ship --headless` if headless)
```

Replace with:

```text
1. `skill: soleur:review` (or `skill: soleur:review --headless` if headless)
2. `skill: soleur:resolve-todo-parallel`
3. `skill: soleur:compound` (or `skill: soleur:compound --headless` if headless)
4. `skill: soleur:ship` (or `skill: soleur:ship --headless` if headless)
```

Note: `resolve-todo-parallel` does not accept `--headless` (it has no interactive prompts -- it processes all approved todos automatically).

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
- Learning: `knowledge-base/project/learnings/2026-03-03-headless-mode-skill-bypass-convention.md` (headless forwarding pattern)
- Learning: `knowledge-base/project/learnings/2026-03-03-skill-handoff-contradicts-pipeline-continuation.md` (pipeline language)
- Learning: `knowledge-base/project/learnings/2026-03-03-and-stop-halt-language-breaks-pipeline.md` (halt language)
- Ship SKILL.md: `plugins/soleur/skills/ship/SKILL.md` (Phase 1 ends at line ~70, Phase 5.5 for gate pattern reference)
- Work SKILL.md: `plugins/soleur/skills/work/SKILL.md` (Phase 4 direct-invocation at line ~370)
- Review SKILL.md: `plugins/soleur/skills/review/SKILL.md` (Step 5 commit message at line ~344)
- One-shot SKILL.md: `plugins/soleur/skills/one-shot/SKILL.md` (steps 4-7 for reference ordering)
- Review todo structure: `plugins/soleur/skills/review/references/review-todo-structure.md` (todo file naming and tagging)
