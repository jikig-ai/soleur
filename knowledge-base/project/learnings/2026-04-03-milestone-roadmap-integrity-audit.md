# Learning: Milestone-Roadmap Integrity Requires Bidirectional Enforcement

## Problem

The roadmap defined Phase 5 with 5 features but the Phase 5 GitHub milestone had zero issues assigned. The AGENTS.md rule "every `gh issue create` must include `--milestone`" enforced issues → milestones (every issue must have a milestone) but not milestones → issues (every milestone must have issues). This one-way gate allowed Phase 5 to exist as an empty shell for weeks.

Additionally, 23+ issues across milestones were misassigned relative to the roadmap (wrong phase, missing milestone, or present in milestone but absent from roadmap table). Statuses in the roadmap were stale — Phase 1 items marked "Not started" were actually closed, Phase 2 items marked "Not started" were Done.

## Solution

1. **Audit methodology:** Cross-referenced `gh api repos/.../milestones` and `gh api repos/.../issues?milestone=N` against every row in `roadmap.md`. Identified misassignments, missing issues, and stale statuses.
2. **Fixed misassignments:** Retroactively milestoned #667-#671 to Phase 1, moved #1375 from Post-MVP to Phase 2, moved operational issues (#1082, #1083, #1169) from Phase 3 to Post-MVP.
3. **Created Phase 5 issues:** 5 properly-defined issues (#1423, #1425, #1427-#1429) with acceptance criteria, dependencies, and technical context.
4. **Updated roadmap statuses:** Corrected all stale "Not started" entries to "Done" based on closed issue state.
5. **Added workflow gate:** New AGENTS.md rule requiring every roadmap feature to have a linked GitHub issue, enforced at the point of adding features to the roadmap.

## Key Insight

Integrity constraints must be bidirectional. A rule that says "every X must have a Y" is only half the constraint — you also need "every Y must have at least one X." The milestone system had issues → milestones but not milestones → issues. The roadmap had features → phases but not phases → verified issue links. Both gaps allowed silent drift.

## Session Errors

- **`gh milestone list` doesn't exist** — `gh` CLI has no `milestone` subcommand; must use `gh api repos/.../milestones`. Prevention: Use `gh api` for milestone operations, not hypothetical subcommands.
- **Closed milestone blocks issue assignment** — `gh issue edit --milestone` cannot target a closed milestone. Prevention: Reopen milestone via API before assigning, then re-close.
- **Label `feat` doesn't exist** — Correct label is `type/feature`. Prevention: Run `gh label list` before using labels in issue creation.
- **Worktree disappeared between commands** — The `milestone-audit` worktree was lost after creation, requiring recreation. Prevention: Verify worktree exists with `ls` before proceeding to file operations.
- **`gh issue edit` CWD error** — Three consecutive `gh issue edit` calls failed with "Unable to read current working directory" after the milestone reopen API call. Prevention: Run commands from the worktree directory, not the bare repo root.

## Tags

category: workflow
module: product-management
