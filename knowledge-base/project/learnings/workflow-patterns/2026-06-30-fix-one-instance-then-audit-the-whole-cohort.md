# Learning: a bug fixed in ONE member of a uniform cohort almost always lives in the siblings — audit the cohort, don't stop at the reported instance

category: workflow-patterns
module: inngest-cron-substrate
date: 2026-06-30
refs: #5786, #5751; learning bug-fixes/2026-06-30-cron-digest-double-file-stale-search-index-and-opposite-dedup-predicates.md

## Problem

#5751 fixed the duplicate-`[Scheduled]`-digest bug for ONE cron
(`cron-community-monitor`). The fix shipped and the issue closed. But the bug was
a property of a *shared substrate* (the `resolveOutputAwareOk` +
`ensureScheduledAuditIssue` per-run-digest cohort), not of that one cron — the
operator immediately noticed the SAME duplication on the content generator and
the weekly roadmap review and asked "are those fixed too?". They were not.

An audit found the identical bug in **7** more crons (all confirmed double-filing
in prod), and the actual cohort boundary was precise: the 8 callers of
`ensureScheduledAuditIssue` (community-monitor + the 7).

## Solution / Key Insight

**When you fix a bug that stems from a shared mechanism, the fix is incomplete
until you have audited every other consumer of that mechanism.** The cheap,
decisive audit is: find the precise cohort boundary in code (here: `git grep -l
ensureScheduledAuditIssue` over the cron functions), then for each member pull the
*production* evidence of the same symptom (here: `gh issue list --search "<title>
in:title"` looking for same-day duplicate pairs). Both were available without
running anything — the bug class and the prod duplicates were greppable.

**Two reusable rules:**

1. **Single-instance fix → cohort sweep is the default, not an upsell.** A
   recurring-symptom bug in a member of a uniform family (claude-eval crons, a set
   of API routes sharing a middleware, migrations sharing a trigger) is a property
   of the family. Closing the one reported issue without sweeping the family leaves
   N-1 live instances of the same defect. The operator should not have to ask;
   surface the cohort audit as part of the original fix's follow-through.

2. **Generalizing a helper to cover the cohort must preserve the original member
   byte-identically, and the ONE variant member is the highest-risk.** Extending
   `isRealScheduledDigest`/`digestIssueExistsForDate` from a hardcoded prefix to a
   per-cron `(titlePrefix, titleSuffix?)` signature: community-monitor is preserved
   by passing its existing constant + empty suffix (proven by re-running its exact
   unit cases). The genuine design fork was the ONE member whose shape differed —
   `cron-campaign-calendar`'s digest title carries a trailing ` (heartbeat)` suffix
   the exact-anchor matcher would silently never match. Prod evidence (all four
   campaign-calendar duplicates carried the suffix) settled the choice (generalize
   the matcher, don't normalize the prompt). The variant member is where the audit
   pays for itself — a naive "apply the same fix to all" would have shipped a
   silent no-op for it.

## Why it matters

The fix bias throughout is fail-OPEN (a wrong per-cron prefix → a duplicate
paper-cut, never a zero-digest), so the sweep is low-risk to land broadly. The
cost of NOT sweeping is the operator re-reporting the same bug per cron, and N-1
crons continuing to double-file daily. The audit (`ensureScheduledAuditIssue`
callers × prod duplicate pairs) cost minutes and pinned the exact 7-cron set.

## Session Errors

1. **An implementation subagent + a review agent each first read the `main`
   checkout instead of the worktree** (absolute `apps/web-platform/` paths resolve
   to the bare/main tree, not `.worktrees/<name>/`) — Recovery: both self-caught
   and re-targeted the worktree path before editing/concluding; no wrong-tree
   writes, conclusions reconciled against the committed worktree state.
   **Prevention:** already the worktree-CWD class — subagents must `cd
   <worktree-abs-path>` + verify `pwd`, and a reviewer reading absolute paths must
   confirm the `.worktrees/` segment is present. (The one-shot planning-subagent
   template already mandates the CWD-verification first tool call; extend the habit
   to read/review subagents.)
