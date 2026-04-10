---
module: Brainstorm Skill
date: 2026-04-10
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "CPO domain assessment advised deferring KB sharing because 'KB API and viewer are not started'"
  - "Roadmap Phase 3 status columns showed 'Not started' for items CLOSED on GitHub for weeks"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [roadmap, stale-data, domain-assessment, brainstorm, cpo]
synced_to: [brainstorm]
---

# Troubleshooting: Stale Roadmap Data Causes Incorrect Domain Leader Assessments

## Problem

During brainstorm for #1745 (KB sharing), the CPO domain assessment recommended deferring the feature because "KB API (3.1) and viewer (3.2) are prerequisites that don't exist yet." Both items had been CLOSED on GitHub for weeks. The CPO read `roadmap.md` as ground truth, but Phase 3 status columns had not been synced with GitHub milestone states since 2026-04-06.

## Environment

- Module: Brainstorm Skill (Phase 0.5 Domain Leader Assessment)
- Affected Component: `plugins/soleur/skills/brainstorm/SKILL.md`, `knowledge-base/product/roadmap.md`
- Date: 2026-04-10

## Symptoms

- CPO assessment said "KB API (3.1) and viewer (3.2) are prerequisites that don't exist yet" — both were CLOSED
- Roadmap showed 3.1 as "Not started", 3.2 as "Stub only" — both were Done
- Five Phase 3 items (3.1, 3.2, 3.3, 3.5, 3.16) listed as not started but all CLOSED on GitHub
- Phase 1 and Phase 2 milestones fully closed but roadmap "Current State" still showed stale counts

## What Didn't Work

**Direct solution:** The problem was identified on the first investigation attempt after the user flagged the CPO's stale data concern.

## Session Errors

**Worktree disappeared after creation** — Created `kb-session-sharing` worktree successfully but it was gone when checking `git worktree list` later.

- **Recovery:** Recreated the worktree with `worktree-manager.sh --yes create kb-session-sharing`
- **Prevention:** Check worktree exists immediately after creation before proceeding. May be a race condition with parallel session cleanup processes.

**Glob tool failed on worktree path** — `Glob` returned "Directory does not exist" for a path that `Bash` commands could access.

- **Recovery:** Used `Bash` `find` command instead
- **Prevention:** Known environmental quirk with worktree paths and the Glob tool. Fall back to Bash when Glob fails on worktree paths.

**First roadmap read from bare repo root** — Read `knowledge-base/product/roadmap.md` from bare repo root (stale copy) before reading the correct version from worktree.

- **Recovery:** Re-read from worktree path
- **Prevention:** Always read files from the worktree path when one is active. Bare repo root files are stale by definition.

## Solution

Two changes applied:

**1. Brainstorm skill fix — Phase 0.25 Roadmap Freshness Check:**

Added a new step between Phase 0 (setup) and Phase 0.5 (domain assessment) that syncs roadmap status columns from GitHub milestone data before domain leaders are spawned:

```markdown
### Phase 0.25: Roadmap Freshness Check

1. Read the roadmap's `last_updated` frontmatter date
2. For each phase milestone, run `gh issue list --milestone "<name>" --state all`
3. Compare GitHub state against roadmap status columns
4. If CLOSED issue listed as "Not started"/"Stub only"/"In progress", update to "Done"
5. Update Current State section and frontmatter dates
6. Commit if changes were made
```

**2. Roadmap data fix:**

Updated `knowledge-base/product/roadmap.md` Phase 3 table:

- 3.1 KB REST API: Not started → Done
- 3.2 KB viewer UI: Stub only → Done
- 3.3 Conversation inbox: Not started → Done
- 3.5 Secure token storage: Not started → Done
- 3.16 Start Fresh onboarding: Not started → Done
- Added 3.17 KB sharing (#1745) as new item

Updated Current State section with correct open/closed counts.

## Why This Works

The root cause was a missing synchronization step. The roadmap document is the canonical product truth (per AGENTS.md workflow gate), but it was only updated during manual CPO reviews — not automatically before workflows that depend on it. Domain leaders read the roadmap to make assessments, so stale status columns propagate directly into incorrect recommendations.

The fix ensures the roadmap is synced with GitHub issue states before any domain assessment runs. This is a mechanical check (compare roadmap status column against `gh issue view` state), not a judgment call — making it reliable and automatable.

## Prevention

- The Phase 0.25 Roadmap Freshness Check now prevents this class of error for all future brainstorms
- When adding new workflows that read `roadmap.md` for decision-making, consider whether a freshness check is needed
- The existing AGENTS.md workflow gate ("update roadmap when changing milestones") prevents staleness at the write side; Phase 0.25 adds defense at the read side

## Related Issues

- See also: [cpo-scope-boundaries-dogfood-20260324.md](cpo-scope-boundaries-dogfood-20260324.md) — CPO making different category of assessment mistakes (scope boundaries, not stale data)
