# Post-Ship Autonomous Monitor

**Date:** 2026-05-26
**Status:** Ready for planning
**Lane:** single-domain

## What We're Building

End-to-end autonomous post-ship pipeline: from auto-merge queue through production health verification. Today the workflow stops at "auto-merge enabled" which leaves a gap — CI failures block merge silently, Sentry regressions go unnoticed until the next session, and postmerge is never chained automatically.

Three changes close the gap:

1. **CI failure auto-fix in ship Phase 7**: When a required check fails during the merge poll, attempt diagnosis and fix (run failing tests, commit fix, push, re-queue auto-merge). Cap at 1 attempt before escalating (reduced from 2 per plan review).
2. **Auto-chain to postmerge**: After ship Phase 7 confirms merge + release workflows pass, invoke `/soleur:postmerge` automatically with the PR number.
3. **Sentry cron monitor check in postmerge**: New phase — verify Sentry cron monitors report `ok` or `active` post-deploy.

## Why This Approach

- Extends existing skills (ship + postmerge) rather than creating new ones
- Ship Phase 7 already has the merge poll loop, release workflow verification, and follow-through detection — CI auto-fix is a natural addition to the failure branch
- Postmerge already has health checks, browser verification, and issue updates — Sentry check is a natural new phase
- Monitor tool replaces bash polling loops for reliability

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where to add CI auto-fix | Ship Phase 7 failure branch | Already detects required-check failures; today it just reports |
| Where to add Sentry check | Postmerge new Phase 3.5 | Postmerge owns production verification; Sentry is a production signal |
| Polling mechanism | Monitor tool everywhere | Bash `while` + `sleep` loops are unreliable in Claude Code (sleep blocked, context consumed, no notifications). Monitor tool is purpose-built. |
| Auto-chain trigger | Ship Phase 7, after release workflows pass | Natural handoff point — merge confirmed, deploy in progress |
| Sentry check: window | 15 minutes post-deploy | Enough time for errors to surface without false positives from cold-start transients |
| Sentry check: threshold | >2x error count vs pre-deploy baseline | Detects regressions without flagging normal background noise |
| Sentry check: monitors | Also verify cron monitor heartbeats report `ok` | Covers scheduled function health, not just request-path errors |
| CI auto-fix: attempt cap | 2 fix attempts before escalating | Prevents infinite fix-break loops while catching most transient issues |
| CI auto-fix: scope | Only required checks, not optional/informational | Don't block merge on non-required checks |

## Open Questions

1. **Sentry API authentication**: Credentials are in Doppler `prd` as `SENTRY_API_TOKEN` — need to verify this is available in the operator's shell session or if we need `doppler run`
2. **Sentry release naming**: Verify the release tag format matches what the web-platform release workflow publishes (likely `web-platform@X.Y.Z+<sha>`)
3. **Monitor tool timeout**: The Monitor tool has per-line notifications — need to design the poll commands to emit state-change events efficiently

## Inciting Incident

PR #4498 was shipped during this session. After enabling auto-merge, the agent stopped. The PR needed a rebase (pre-merge hook handled it), but there was no autonomous monitoring of CI status, merge completion, or production health. Meanwhile, the very Sentry error that triggered this session (`cron-oauth-probe` JWT decode failure) demonstrated that production errors can surface immediately after deploy and need automated detection.
