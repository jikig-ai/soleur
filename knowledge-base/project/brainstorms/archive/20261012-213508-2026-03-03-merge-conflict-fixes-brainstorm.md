# Merge Conflict Targeted Fixes

**Date:** 2026-03-03
**Status:** Approved
**Issue:** #395

## What We're Building

Four targeted fixes that close the remaining merge conflict gaps after tag-only versioning (#412) eliminated the #1 conflict source (14+ incidents from version file bumps):

1. **Canonicalize merge strategy** — Update AGENTS.md hard rule and `pre-merge-rebase.sh` hook from rebase to merge. Resolves the contradiction where AGENTS.md mandates rebase but both `/ship` and `/merge-pr` use merge.

2. **Pre-push sync in /ship** — Add a sync step before `/ship` Phase 6 (push) that fetches `origin/main` and merges into the feature branch. If conflicts occur, attempt Claude-assisted resolution (reusing merge-pr Phase 3.3 patterns). If confidence is low, abort and present a structured summary of each conflict. Catches conflicts *before* PR creation instead of after.

3. **Conflict marker pre-commit hook** — Add a guard to `guardrails.sh` that greps staged content for `<<<<<<<`, `=======`, `>>>>>>>` markers. Prevents accidentally committing unresolved conflicts (documented failure mode in merge-pr design lessons).

4. **Worktree refresh command** — Add a `refresh` subcommand to `worktree-manager.sh` that fetches `origin/main` and merges into the current worktree branch. Closes the gap where long-lived worktrees have no mechanism to stay current with main.

## Why This Approach (Not a Pipeline)

The original issue (#395) proposed a full autonomous merge conflict resolution pipeline. Research revealed:

- **The #1 conflict source is already fixed.** Tag-only versioning (#412) eliminated version file conflicts — the 14+ events cited in #395.
- **80% of the pipeline already exists.** `/ship` Phase 6.5 and `/merge-pr` Phase 2-3 both handle conflict resolution. Adding a fourth codepath would be technical debt.
- **The remaining friction is low-frequency.** Content conflicts in docs/constitution are rare and handled adequately by existing mechanisms once the sync happens earlier.

Targeted fixes give 90% of the value at 20% of the cost. A full pipeline can be revisited if conflict frequency remains high after these fixes land.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Rebase vs. merge | **Merge** | Both skills already use merge. PRs are squash-merged so history stays linear regardless. Rebase creates per-commit conflicts (harder). |
| Pipeline vs. fixes | **Targeted fixes** | #1 source already eliminated. Remaining gaps are small. A pipeline would be over-engineering. |
| Conflict resolution failure mode | **Claude-assisted, then structured summary** | Attempt auto-resolution first (reuses merge-pr pattern). Fall back to structured conflict summary if confidence is low. |
| Shared utility extraction | **Deferred** | Not enough conflict resolution code to justify a shared script yet. Can extract later if the pattern stabilizes. |
| Update AGENTS.md | **Yes** | Resolving the rebase/merge contradiction is prerequisite. Cannot have rules that contradict the tools. |

## Open Questions

- After these fixes land, should the `pre-merge-rebase.sh` hook be renamed to `pre-merge-sync.sh` to reflect the merge strategy?
- Should the worktree `refresh` command also run `npm install` after merge (since `node_modules/` is not shared)?
- Should `/merge-pr` Phase 2 be updated to use the same pre-push sync pattern, or left as-is since it already handles conflicts?

## Research Context

### CTO Assessment

- Identified 3 overlapping codepaths with inconsistent strategies
- Recommended extracting a shared skill (deferred — fixes come first)
- Flagged rebase-vs-merge as blocking decision (resolved: merge)
- Estimated 2-3 days for full pipeline vs. hours for targeted fixes

### Institutional Learnings (22 relevant)

- **CHANGELOG truncation during rebase** — Full file rewrite required, not edit
- **Worktree loss from stash** — Never stash in worktrees, use checkpoint commits
- **Conflict markers committed** — No pre-commit guard exists (fix #3 addresses this)
- **Pre-merge rebase hook** — Hook stdout corrupts JSON; redirect both streams
- **Tag-only versioning** — Eliminated 14+ conflict events (context for reduced scope)
