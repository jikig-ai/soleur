---
title: "fix: replace dead resolve-todo-parallel step in one-shot pipeline"
type: fix
date: 2026-04-02
deepened: 2026-04-02
---

# fix: Replace dead resolve-todo-parallel step in one-shot pipeline

## Enhancement Summary

**Deepened on:** 2026-04-02
**Sections enhanced:** 2 (Technical Approach, Acceptance Criteria)
**Research sources:** 5 institutional learnings, review-todo-structure.md template analysis

### Key Improvements

1. Added pipeline continuation safety rules from 3 learnings about one-shot stall patterns
2. Added skill description word budget constraint from learning about pre-commit failures
3. Added concrete `gh` CLI commands and SKILL.md prose for the new Step 5
4. Identified `review-todo-structure.md` template scoping gap -- `Source: PR #` line is in the template but needs verification that it is consistently emitted

## Overview

After PR #1329, the `/review` skill creates GitHub issues with the `code-review` label instead of local `todos/*.md` files. The one-shot pipeline (Step 5) chains `resolve-todo-parallel` after review, but `resolve-todo-parallel` reads from `todos/*.md` only -- it finds nothing after a GitHub-issues-based review. This is a dead step that wastes pipeline time and produces no results.

## Problem Statement

The one-shot pipeline at `plugins/soleur/skills/one-shot/SKILL.md` Step 5 invokes `soleur:resolve-todo-parallel`. That skill's workflow:

1. Reads all unresolved TODOs from `todos/*.md`
2. Plans resolution order with dependency analysis
3. Spawns parallel `pr-comment-resolver` agents

After PR #1329, `/review` no longer writes to `todos/*.md`. It creates GitHub issues via `gh issue create` with the `code-review` label and appropriate priority/milestone labels. The `resolve-todo-parallel` skill finds zero pending items and exits as a no-op.

**Impact:** Every one-shot pipeline run wastes a skill invocation on Step 5 with no effect.

## Proposed Solution

Replace the dead `resolve-todo-parallel` invocation in one-shot Step 5 with a GitHub-issue-aware resolution step that auto-fixes P1 (blocks-merge) review findings. The new step will:

1. Fetch open GitHub issues with the `code-review` label scoped to the current PR (filter by PR number in issue body, e.g., `Source: PR #<pr_number>`)
2. For P1 (critical/blocks-merge) issues: spawn parallel `pr-comment-resolver` agents, passing the issue body's `## Problem` and `## Proposed Fix` sections as structured context
3. For P2/P3 issues: skip (tracked for later resolution, not blocking merge)
4. After resolution: commit fixes and close resolved GitHub issues with a reference to the fixing commit
5. If no P1 issues exist: proceed immediately (no-op is fine)

This approach preserves the one-shot pipeline's intent (resolve blocking review findings before shipping) while adapting to the GitHub-issues-based review output.

### Why not Option 1 (update resolve-todo-parallel to handle both)?

The `resolve-todo-parallel` skill has a clear, well-defined scope: local `todos/*.md` files. Merging two different data sources (local files and GitHub issues) into one skill creates confusion about what the skill does. The `triage` skill description already notes this boundary: "For GitHub issues, use ticket-triage agent." Keeping the skills separate is cleaner.

### Why not Option 3 (remove the step entirely)?

Removing the step means P1 review findings that block merge would not be auto-resolved in the one-shot pipeline. The `/ship` skill does check for unresolved review comments, but that is a gate (blocks), not a resolver (fixes). In one-shot mode, the pipeline should attempt to fix P1 findings autonomously before hitting the ship gate. Removing auto-resolution degrades the one-shot promise.

**Reviewer note:** The simplicity reviewer suggested splitting this into (a) remove dead step now, (b) file a separate feat issue for P1 auto-resolution. This was considered but rejected because the dead step removal alone leaves a functional gap in one-shot -- the pipeline would hit `/ship`'s P1 gate with no prior attempt to fix, which is a worse user experience than a no-op step. The replacement logic is 5 inline instructions, not a new skill.

## Technical Approach

### Change 1: Update one-shot SKILL.md Step 5

Replace the `soleur:resolve-todo-parallel` invocation with inline GitHub-issue resolution logic. No new skill is needed -- the logic is concise enough to live directly in the one-shot instructions.

**File:** `plugins/soleur/skills/one-shot/SKILL.md`

Replace the current Step 5 line:

```text
5. Use the **Skill tool**: `skill: soleur:resolve-todo-parallel`
```

With the following prose block (approximate SKILL.md content):

```markdown
5. **Resolve P1 review findings.** List open GitHub issues with `code-review` + `priority/p1-high` labels:

   `gh issue list --label code-review --label priority/p1-high --state open --json number,title,body`

   Filter results to issues whose body contains `Source: PR #<current_pr_number>` (scopes to this review session; the review skill's issue template includes this line). If zero P1 issues match, proceed immediately to Step 5.5.

   For each P1 issue, spawn a parallel `pr-comment-resolver` agent. Pass the issue body's `## Problem`, `## Proposed Fix`, and `Location:` fields as the agent's input. After all agents complete, commit fixes and close each resolved issue:

   `gh issue close <number> --comment "Fixed in <commit-sha>"`

   Do NOT end your turn after this step. Proceed to Step 5.5.
```

#### Research Insights (Pipeline Continuation Safety)

Three institutional learnings document the same failure class in one-shot: skills or inline steps that use finality language ("stop", "done", "announce to the user") cause the model to end its turn, skipping remaining pipeline steps.

- `2026-03-03-and-stop-halt-language-breaks-pipeline.md` -- "and stop" in work Phase 4 halted the pipeline
- `2026-03-03-pipeline-continuation-stalls.md` -- "Implementation complete." was interpreted as a turn boundary
- `2026-03-02-skill-handoff-blocks-pipeline-when-announcing.md` -- "Announce to the user" triggered turn end

**Constraint for the new Step 5:** The inline instructions must end with explicit continuation language ("Do NOT end your turn. Proceed to Step 5.5.") and must NOT use "done", "complete", "stop", or "announce." The model must flow through Step 5 to Step 5.5 (QA) without stalling.

The existing CONTINUATION GATE after Step 3 (work) is the reference pattern. Step 5 does not need its own gate because it is inline prose (not a Skill tool invocation), but it does need the explicit "Proceed to Step 5.5" instruction at the end.

#### Agent Input Format Mapping

The `pr-comment-resolver` agent accepts "a comment or review feedback" generically. The GitHub issue body from `/review` follows the template in `review-todo-structure.md` (line 24):

```markdown
**Source:** PR #<pr_number> review | **Effort:** <Small|Medium|Large>

## Problem
<description>
**Location:** `<file_path>:<line_number>`

## Proposed Fix
<recommended fix>
```

This maps directly to the agent's "analyze the comment" workflow:

- `## Problem` + `Location:` --> agent step 1 (identify code location and change nature)
- `## Proposed Fix` --> agent step 2 (plan the resolution)

No agent modification is needed.

### Change 2: Update resolve-todo-parallel description (required)

Add a note to the `resolve-todo-parallel` SKILL.md body (not the YAML description field) clarifying it handles legacy local `todos/*.md` only, consistent with the note already added to the `triage` skill body in PR #1329.

**File:** `plugins/soleur/skills/resolve-todo-parallel/SKILL.md`

Add a note block after the title, similar to the triage skill's note:

```markdown
> **Note:** The `/soleur:review` skill now creates GitHub issues directly for all new findings.
> This skill handles only legacy local `todos/*.md` files that predate the GitHub issue integration.
```

#### Research Insight (Skill Description Word Budget)

From `2026-03-30-skill-description-word-budget-awareness.md`: The cumulative YAML `description:` field word count across all skills has a 1,800-word budget enforced by pre-commit hook. The current `resolve-todo-parallel` description is already concise (~25 words). Do NOT modify the YAML `description:` field -- add the legacy note to the body text only. This avoids any risk of exceeding the word budget. Run `bun test plugins/soleur/test/components.test.ts` before committing to verify.

### Change 3: Update triage skill reference

The `triage` SKILL.md still references `/resolve-todo-parallel` in its "Next Steps" section (line 208). This reference remains valid since triage operates on local `todos/*.md` files. No change needed.

## Acceptance Criteria

- [ ] One-shot Step 5 fetches `code-review` + `priority/p1-high` issues scoped to the current PR and resolves them
- [ ] One-shot Step 5 is a no-op when no P1 `code-review` issues exist (does not error or block)
- [ ] One-shot Step 5 no longer invokes `soleur:resolve-todo-parallel`
- [ ] Issue scoping filters by `Source: PR #<number>` in issue body (does not pick up issues from unrelated reviews)
- [ ] `resolve-todo-parallel` skill description clarifies it handles `todos/*.md` only (required, not optional)
- [ ] The `pr-comment-resolver` agent is reused (no new agent needed)
- [ ] Closed P1 issues include a reference to the fixing commit

## Test Scenarios

- Given a one-shot pipeline run where review produces zero P1 findings, when Step 5 executes, then it proceeds immediately to Step 5.5 (QA) without error
- Given a one-shot pipeline run where review produces 2 P1 `code-review` issues, when Step 5 executes, then it spawns 2 parallel `pr-comment-resolver` agents, commits fixes, and closes both issues
- Given a one-shot pipeline run where review produces only P2/P3 issues, when Step 5 executes, then it proceeds immediately (P2/P3 are not blocking)
- Given open P1 `code-review` issues from a prior unrelated review, when Step 5 executes for a new PR, then it does NOT attempt to resolve those issues (scoped by `Source: PR #` in body)
- Given Step 5 completes (with or without P1 resolutions), when the model processes the step output, then it continues to Step 5.5 without stalling (no finality language in the step prose)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal pipeline orchestration fix.

## Plan Review

**Reviewers:** DHH, Kieran, Code Simplicity

**Key feedback applied:**

1. **Issue scoping (Kieran):** Added PR-number filtering to prevent picking up issues from unrelated reviews
2. **Agent input format (Kieran):** Added explicit mapping from GitHub issue body structure to `pr-comment-resolver` expected input
3. **Change 2 made required (Kieran):** Description update for `resolve-todo-parallel` changed from "optional" to "required"
4. **Split vs combine (Simplicity):** Considered splitting into remove + separate feat issue; rejected because removal alone creates a functional gap in one-shot (ship gate blocks but nothing attempts to fix)

## Context

- **Source issue:** #1337 (found by pattern-recognition-specialist on PR #1329)
- **Root cause PR:** #1329 (`feat(review): create GitHub issues instead of local todos`)
- **Related skill:** `resolve-pr-parallel` -- resolves PR comments (different scope: PR review threads vs GitHub issues)
- **Related skill:** `fix-issue` -- automated single-file fix for GitHub issues (different scope: general issues, not pipeline integration)

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/skills/one-shot/SKILL.md` | Replace Step 5 with GitHub-issue resolution logic |
| `plugins/soleur/skills/resolve-todo-parallel/SKILL.md` | Add clarifying note about `todos/*.md` scope |

## References

- GitHub issue: #1337
- PR #1329: review skill GitHub issues migration
- `plugins/soleur/skills/one-shot/SKILL.md` (lines 107-108): current Step 5
- `plugins/soleur/skills/resolve-todo-parallel/SKILL.md`: skill being replaced
- `plugins/soleur/skills/review/references/review-todo-structure.md`: issue creation template
- `plugins/soleur/agents/engineering/workflow/pr-comment-resolver.md`: agent reused for resolution
