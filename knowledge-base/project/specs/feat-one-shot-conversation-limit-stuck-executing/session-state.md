# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-conversation-limit-stuck-executing/knowledge-base/project/plans/2026-05-06-fix-one-shot-conversation-limit-stuck-executing-plan.md
- Status: complete

### Errors
None blocking. Mid-task user note: pasted Sentry error `[Pasted text #4]` not visible during planning — surfaced separately at /work entry (see Mid-Session Context below).

### Decisions
- Root cause identified: `tryLedgerDivergenceRecovery` (May-5 PR #3295) detects orphan slots (slot present, conversation invisible) but NOT the inverse — a slot whose conversation IS visible (`status='active'`) yet no live WS is heartbeating it. After tab-supersession (`SUPERSEDED` close), the dashboard's stuck-active slot has no live heartbeat, but the recovery helper's visible-set check still finds the conversation → `didRecover=false` → cap-hit close fires; user is dead-ended for the 0–180 s reaper window.
- Fix scope: extend `tryLedgerDivergenceRecovery` (Phase 1) with a second SELECT for `last_heartbeat_at < now() - 120s`. Union-with-dedup against the orphan set, single Promise.all reap, single Sentry mirror with `orphanCount + staleHeartbeatCount`. Threshold = 120 s, matching the four pre-existing coupled sites.
- Plan Phase 2 = single-file copy edit (`ws-client.ts:125`) — verified at deepen-time that `upgrade-at-capacity-modal.tsx` and `upgrade-copy.ts` do NOT duplicate the misleading "completed" wording.
- Application-layer sync-reap chosen over migration changes — the existing 60 s reaper + 120 s pg_cron sweep + 120 s lazy sweep all do the same job asynchronously; the user is staring at the modal NOW and waiting up to 180 s is the dead-end. Sync-reap runs at cap-hit time, sub-second recovery.
- User-Brand Impact threshold = `single-user incident` — free-tier first-PDF-chat is funnel-top; one user hitting this colors product perception. CPO sign-off + `user-impact-reviewer` required pre-merge.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Bash, Read, Edit, Write, ToolSearch
- Direct verification of plan's file:line citations against current main; PRs #3217, #3295 confirmed MERGED via `gh pr view` + `git log --grep`.

## Mid-Session Context (User-Provided)

**Sentry error received during planning** (May 6, 2026, 8:57:23 p.m. CEST, ID 57ff3df022884680ab6c6882b9e92dd0):
- Tag/feature: `concurrency-stuck-active-reaper silent...` (truncated; suffix likely `silent-fallback` or `silent-reap`)
- This is the **async reaper** path firing — confirmed via `reportSilentFallback` (rule cq-silent-fallback-must-mirror-to-sentry).
- **Validates the plan's diagnosis**: stuck-active slots ARE being detected, but only by the eventual reaper (60–180 s after the fact). The user-blocking sync path (`tryLedgerDivergenceRecovery` at cap-hit time) has no equivalent stale-heartbeat detector, so the user dead-ends until the async reaper catches up.
- **Implication for /work**: Phase 1 must mirror Sentry from the new sync-reap path with the same `feature` label so the existing dashboard groups both. Confirm whether the current Sentry tag is exactly `concurrency-stuck-active-reaper` and reuse verbatim if so.
