# Learning: a comment-skip added during review swallowed the real map, and my "real tree" check predated it

## Problem

PR #9769 teaches `sentry-monitors-audit.sh` to treat a cron detector as declared-pending when its monitor is a key of `local.cron_monitor_alert_unrouted`. The first review round (six seats, no P1) asked the awk map parser to skip `/* */` block comments, to match the TS parity guard's comment stripping. The guard I added, `/\/\*/ { cm=1 }`, opened a block on ANY line containing `/*`, including `cron-monitor-alerts.tf:13`, a `#` comment quoting `apps/web-platform/infra/sentry/*.tf`. `cm` never cleared, so the real map was skipped and both declared-pending monitors would have warned again in production, the exact defect the PR exists to close. The 77-assertion suite stayed green because every fixture was synthetic.

I HAD run the audit against the real `infra/sentry` tree earlier. That check predated the guard, and nothing made it re-run.

## Solution

Anchor the opener to a line that STARTS with `/*` (`^[[:space:]]*\/\*`). Add row T19p7, which runs the audit against the real `infra/sentry` directory and expects both monitors pending; restoring the unanchored guard turns it RED (77/1). Two fix-round seats (verification and security) found it independently; the test-design seat confirmed it and listed the five other survivors, now each killed by a row (opener trailing comment, commented-out opener, populated-then-sibling map, multi-line header comment, report wording).

## Key Insight

A fix written during review is the least-audited surface in the diff, and "I verified this against the real artifact" is a claim about a moment. Any later edit to a parser that reads a real file invalidates it. For a parser/extractor guard, keep one committed row that runs it against the REAL file it exists to read, so the verification re-runs on every later edit instead of living in session memory. Synthetic fixtures are written by the author who is thinking about the shapes the fix handles; the real tree contains the shape nobody thought of (a glob inside a comment).

## Session Errors

1. **Resume brief carried a stale hard constraint** (web-1 wipe "must not happen"; the operator had dispatched it that day). Recovery: the planner read live state and reported it, no action taken. **Prevention:** existing rule, brief facts are preconditions to re-derive.
2. **A closed issue in the args would trip one-shot's closed-issue gate.** Recovery: scrubbed up front. **Prevention:** existing sharp edge.
3. **The self-match hook denied a process-pattern search with the full-command-line flag, twice** (once for the command, once for a Bash call whose heredoc text merely quoted that flag). Recovery: `kill_mine` from `proc.sh`, and the Write tool for prose. **Prevention:** hook worked; write prose files with the Write tool, not a Bash heredoc.
4. **Session-start restore overwrote a local `.mcp.json` edit.** Recovery: backed up before the restore. **Prevention:** inspect `git diff .mcp.json` before running the restore.
5. **The block-comment guard regression (above).** **Prevention:** a committed real-tree row for any extractor guard.
6. **Two first-run test assertions wrong; one wording edit broke an existing grep.** Recovery: the suite named each immediately. **Prevention:** none beyond running the suite after each edit.
7. **Affected gate queued 40+ minutes; I edited the tree under it, voiding its verdict.** Recovery: killed it with `kill_mine`, reran at ship. **Prevention:** do not edit under a queued gate (existing rule); check `--capacity` before launch.
8. **Size overshoot.** The plan's 100-line stop rule was measured on the unreviewed fix (98); review hardening took it to 151/6 in 3 files. Shipped, disclosed in the PR body.

## Tags
category: logic-errors
module: sentry-monitors-audit
