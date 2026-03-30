---
title: "feat: review skill creates GitHub issues instead of local todos"
type: feat
date: 2026-03-30
issue: "#1288"
deepened: 2026-03-30
---

# Review Skill: Create GitHub Issues Instead of Local Todos

## Enhancement Summary

**Deepened on:** 2026-03-30
**Sections enhanced:** 4 (Technical Approach, Implementation Phases, Issue Body Template, Test Scenarios)
**Research sources:** 4 institutional learnings, existing `gh issue create` patterns from 6 skills

### Key Improvements

1. Use `--body-file` pattern instead of inline `--body` to avoid `$()` command substitution permission prompts (from learning: `2026-02-22-command-substitution-in-plugin-markdown`)
2. Add duplicate detection before issue creation to prevent duplicates when review runs twice on the same PR
3. Add graceful error handling per `gh issue create` call (log and continue, from `compound-capture` pattern)
4. Add concrete command for active milestone detection

### New Considerations Discovered

- Finding descriptions from review agents may contain arbitrary markdown, newlines, and special characters -- `--body-file` handles this safely
- The `$()` permission prompt learning has recurred 4 times in the project; this plan would have introduced a 5th occurrence without the deepening pass

## Overview

Update the `/soleur:review` skill's Step 2 (Create Todo Files) and its supporting reference (`review-todo-structure.md`) to create GitHub issues with appropriate labels and milestones instead of local `todos/*.md` files. Review findings should be tracked in the issue tracker for roadmap visibility, prioritization, and milestone planning.

## Problem Statement

The `/soleur:review` skill currently stores all findings as `todos/*.md` files via the `file-todos` skill. This creates several problems:

1. **Invisible to the roadmap** -- `todos/*.md` files are local to the repo and cannot be milestoned, assigned, or surfaced in project planning.
2. **Accumulation without tracking** -- Pre-existing todos pile up with no centralized prioritization. During the #1047 review session, 13 pre-existing pending todos were found with no GitHub issue tracking.
3. **No cross-session persistence** -- Findings from one PR's review cannot be surfaced during future planning sessions unless someone reads `todos/`.
4. **No labeling or filtering** -- The file-based system cannot leverage GitHub's label taxonomy (`priority/p1-high`, `domain/engineering`, `type/bug`, etc.) for filtering and automation.
5. **Disconnected from existing workflows** -- The `ticket-triage` agent, daily triage workflow, and scheduled automations all operate on GitHub issues, not `todos/` files.

## Proposed Solution

Replace the file-todos flow in `/soleur:review` Step 2 with GitHub issue creation via `gh issue create`. Retain the ability to create local todo files as an opt-in fallback for offline or quick-triage scenarios.

### Design Decisions

**Primary output: GitHub issues.** Each review finding becomes a GitHub issue with:

- Title following conventional format: `review: <description>`
- Labels: `code-review` + priority label (`priority/p1-high`, `priority/p2-medium`, `priority/p3-low`) + domain label (e.g., `domain/engineering`)
- Milestone: Default to `Post-MVP / Later`; P1 findings get the current active milestone
- Body: Structured markdown with Problem Statement, Location, Proposed Solution, Severity, and back-link to the reviewed PR

**No local todos.** The review skill will no longer create `todos/*.md` files. GitHub issues are the single source of truth. The review skill already requires GitHub API access (for `gh pr view`), so offline scenarios are not realistic. Removing the dual-output path simplifies the SKILL.md, the reference document, and the summary report.

**Label mapping:**

| Review Severity | GitHub Priority Label | GitHub Domain Label |
|----------------|----------------------|-------------------|
| P1 (CRITICAL)  | `priority/p1-high`   | Inferred from finding category |
| P2 (IMPORTANT) | `priority/p2-medium` | Inferred from finding category |
| P3 (NICE-TO-HAVE) | `priority/p3-low` | Inferred from finding category |

**Category-to-domain mapping:**

Default to `domain/engineering` for all findings. The agent may override to `domain/product` for agent-native findings if clearly product-scoped.

## Technical Approach

### Files to Modify

1. **`plugins/soleur/skills/review/SKILL.md`** -- Update Step 5 (Findings Synthesis and Todo Creation) to create GitHub issues instead of local todos
2. **`plugins/soleur/skills/review/references/review-todo-structure.md`** -- Rewrite to describe GitHub issue creation flow
3. **`plugins/soleur/skills/triage/SKILL.md`** -- Update description to reflect that review findings now live in GitHub issues; the triage skill's scope narrows to legacy local todos only

### Research Insights

**Use `--body-file` pattern (mandatory).** Per learning `2026-02-22-command-substitution-in-plugin-markdown`, bash code blocks in plugin markdown that use `$()` trigger Claude Code permission prompts. The established safe pattern (from `compound-capture`) is:

1. Write the issue body to a temporary file (e.g., `/tmp/review-finding-001.md`)
2. Run `gh issue create --body-file /tmp/review-finding-001.md ...`

This also naturally handles newlines, special characters, and arbitrary markdown in finding descriptions.

**Graceful error handling per issue.** Per `compound-capture` pattern: if `gh issue create` fails (network error, auth failure, rate limit), log the error and continue to the next finding. Do not block the entire review synthesis on one failed issue creation. The summary report should note failed creations.

**Duplicate detection.** Before creating an issue, check if one already exists for this finding from the same PR:

```text
gh issue list --label code-review --search "review: <description>" --json number,title --jq '.[0].number // empty'
```

If a match exists, skip creation and reference the existing issue in the summary.

**Active milestone detection.** The plan says "P1 findings get the current active milestone" -- use this concrete command to find it:

```text
gh api repos/:owner/:repo/milestones --jq '[.[] | select(.state=="open") | select(.title | startswith("Phase"))] | sort_by(.due_on) | .[0].title // "Post-MVP / Later"'
```

This selects the earliest open Phase milestone, falling back to `Post-MVP / Later`.

### Implementation Phases

#### Phase 1: Update `review-todo-structure.md` Reference

Rewrite the reference document to describe the new GitHub issue creation flow:

- **Label prerequisite** -- Verify `code-review` label exists; create with `gh label create code-review --description "Finding from code review" --color 0E8A16` if missing
- **Issue body template** -- Simplified markdown body with: Problem Statement, Location (file:line), Proposed Solution, and a one-liner for effort estimate. Severity and category are captured in labels, not duplicated in the body. PR back-link included. Body is written to a temp file and passed via `--body-file` (not inline `--body`) to avoid `$()` permission prompts and handle arbitrary markdown safely.
- **Label selection logic** -- Map P1/P2/P3 to `priority/*` labels; default `domain/engineering`; always add `code-review` label
- **Milestone selection** -- P1 findings get current active milestone; P2/P3 get `Post-MVP / Later`
- **Batch creation strategy** -- Use parallel `gh issue create` calls grouped by severity. If a review produces 15+ findings, batch sequentially to avoid GitHub API rate limits.
- **`--milestone` enforcement** -- Every `gh issue create` must include `--milestone` per AGENTS.md Guard 5

#### Phase 2: Update SKILL.md Step 5

Modify the review skill's Step 5 (currently "Findings Synthesis and Todo Creation Using file-todos Skill") to:

1. Replace the `<critical_requirement>` block to state findings are stored as GitHub issues
2. Update Step 2 (Create Todo Files) heading to "Create GitHub Issues"
3. Replace file-todos skill references with `gh issue create` commands
4. Add `code-review` label existence check before first issue creation
5. Update the Summary Report template to show issue URLs instead of todo file paths
6. Update "Next Steps" to reference `gh issue list --label code-review` instead of `ls todos/*-pending-*.md`
7. Remove `/triage` from the primary flow; note it applies to legacy local todos only

#### Phase 3: Update Triage Skill Description

Update `plugins/soleur/skills/triage/SKILL.md` description to clarify scope:

- Triage skill handles legacy local `todos/*.md` files
- Review findings now create GitHub issues directly (no triage needed -- severity is set at creation)
- The `ticket-triage` agent handles GitHub issue classification (complementary, not overlapping)

### Issue Body Template

The body is written to a temporary file (e.g., `/tmp/review-finding-001.md`) and passed via `--body-file`. This avoids `$()` command substitution permission prompts and handles arbitrary markdown safely.

**Template content:**

```markdown
**Source:** PR #{pr_number} review | **Effort:** {Small|Medium|Large}

## Problem

{description}

**Location:** `{file_path}:{line_number}`

## Proposed Fix

{recommended fix}

## Acceptance Criteria

- [ ] {criterion_1}
- [ ] {criterion_2}
```

Severity and category are captured in issue labels (`priority/*`, `domain/*`, `code-review`), not duplicated in the body.

**Creation command pattern:**

```text
# 1. Write body to temp file (using Write tool, not echo/cat)
# 2. Create issue with --body-file
gh issue create --title "review: {description}" --body-file /tmp/review-finding-001.md --label code-review --label priority/p2-medium --label domain/engineering --milestone "Post-MVP / Later"
```

**Error handling:** If `gh issue create` exits non-zero, log the error and continue to the next finding. Report failed creations in the summary.

## Acceptance Criteria

- [ ] `/soleur:review` creates GitHub issues for each finding via `gh issue create`
- [ ] Each issue has `code-review` label plus appropriate `priority/*` and `domain/*` labels
- [ ] Each issue has a milestone (`--milestone` flag always present, per AGENTS.md Guard 5)
- [ ] P1 findings get the current active milestone; P2/P3 get `Post-MVP / Later`
- [ ] Issue body contains structured markdown with Problem Statement, Location, Findings, and Proposed Solution
- [ ] Issue title follows format: `review: <description>` with PR back-link in body
- [ ] Summary Report shows GitHub issue URLs instead of todo file paths
- [ ] The `review-todo-structure.md` reference is rewritten to describe GitHub issue creation
- [ ] The `code-review` label exists (created if missing)
- [ ] Backward compatibility: `/triage` skill still works for any remaining legacy local todos

## Test Scenarios

- Given a PR with 3 findings (1 P1, 1 P2, 1 P3), when `/soleur:review` completes, then 3 GitHub issues are created with correct priority labels and milestones
- Given a P1 finding, when a GitHub issue is created, then it has `priority/p1-high`, `code-review`, and `domain/engineering` labels
- Given a finding with file location `app/services/auth.rb:42`, when the issue is created, then the body contains the file:line reference
- Given the `--milestone` AGENTS.md guard, when `gh issue create` is called, then `--milestone` flag is always present
- Given a review with no findings, when synthesis completes, then no GitHub issues are created and the summary says "No findings"
- Given `gh issue create` fails for one finding (network error), when synthesis continues, then remaining findings are still created and the summary notes the failure
- Given a review runs twice on the same PR, when duplicate detection checks existing issues, then no duplicate issues are created
- Given a finding description contains newlines and special markdown characters, when the body is written via `--body-file`, then the issue body renders correctly

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **GitHub issues only (no local todos)** | Simplest, single source of truth | Breaking change for triage skill | **Chosen** -- review skill requires GitHub API access anyway; offline is not realistic |
| Local todos only (status quo) | No changes needed | Invisible to roadmap, root cause of #1288 | Rejected -- the problem |
| GitHub issues primary + optional local todos | Backward compatible | Dual-output path adds complexity, undermines the purpose | Rejected -- per plan review feedback |
| GitHub issues via API (not CLI) | More control over creation | `gh` CLI is the project standard, API is unnecessary complexity | Rejected |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is an internal developer tooling change modifying how the review skill persists findings. The architectural impact is low -- replacing file writes with `gh issue create` CLI calls. The main risk is ensuring the `--milestone` guard (AGENTS.md Guard 5) is always satisfied and that the label taxonomy matches existing GitHub labels. No infrastructure changes needed. The `gh` CLI is already authenticated and used throughout the project.

## Plan Review

**Reviewers:** DHH Rails Reviewer, Kieran Rails Reviewer, Code Simplicity Reviewer

**Changes applied from review:**

1. Dropped optional local todos entirely (all 3 reviewers agreed -- dual output undermines the purpose)
2. Added `code-review` label creation/verification step (Kieran -- label doesn't exist yet)
3. Simplified category-to-domain mapping to a single default (DHH -- 7 rows mapping to the same value is ceremony)
4. Simplified issue body template from 7+ sections to 3 core sections (Code Simplicity)
5. Added rate limit handling note for 15+ findings (Kieran)
6. Moved PR back-link from title to body (Kieran -- parenthetical doesn't trigger useful linking)

## References

### Source Files

- Issue: #1288
- Review skill: `plugins/soleur/skills/review/SKILL.md`
- Todo structure reference: `plugins/soleur/skills/review/references/review-todo-structure.md`
- File-todos skill: `plugins/soleur/skills/file-todos/SKILL.md`
- Triage skill: `plugins/soleur/skills/triage/SKILL.md`
- Ticket-triage agent: `plugins/soleur/agents/support/ticket-triage.md`
- Compound-capture skill (body-file pattern): `plugins/soleur/skills/compound-capture/SKILL.md:332-336`

### Institutional Learnings Applied

- `$()` command substitution avoidance: `knowledge-base/project/learnings/2026-02-22-command-substitution-in-plugin-markdown.md`
- GitHub issue auto-close syntax: `knowledge-base/project/learnings/2026-02-22-github-issue-auto-close-syntax.md`
- Domain label alignment: `knowledge-base/project/learnings/2026-03-02-triage-domain-labels-must-match-org-structure.md`
- `gh` CLI pitfalls (error handling, rate limits): `knowledge-base/project/learnings/2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`
