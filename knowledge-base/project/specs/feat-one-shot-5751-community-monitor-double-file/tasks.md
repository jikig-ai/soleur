---
plan: knowledge-base/project/plans/2026-06-30-fix-community-monitor-double-digest-plan.md
issue: 5751
lane: cross-domain
---

# Tasks — fix cron-community-monitor double-digest (#5751)

> Derived from the finalized (deepen-passed) plan. RED-first; investigation gates the fix layer.

## Phase 0 — Production root-cause confirmation (NO code)

- [ ] 0.1 Pull `routine_runs` for `cron-community-monitor` 2026-06-20/06-21/06-30
      (run_id, trigger type CRON vs EVENT, attempt, started_at, duration_ms, status,
      error_summary) via Supabase MCP / runbook H11. Determine one-run-two-attempts (H-B)
      vs two-runs (H-A) and whether any was EVENT-triggered.
- [ ] 0.2 `gh issue view` #5737/#5740/#5596/#5597/#5592/#5593 — correlate createdAt/author
      to the run window(s); confirm both bodies are real digests.
- [ ] 0.3 Sentry exec-path search: `scheduled-output-missing`, `verify-output-failed`,
      `handler-body-threw`, `ensure-audit-issue-failed` for these dates — confirm the
      audit path did NOT fire; capture whether heartbeatOk was false.
- [ ] 0.4 If H-A: check `trigger-cron/route.ts` + operator history for duplicate
      `cron/community-monitor.manual-trigger` emissions in the recovery window.
- [ ] 0.5 Record verdict (H-A / H-B / H-C-compound) in spec + PR body.

## Phase 1 — RED regression test

- [ ] 1.1 Verify `apps/web-platform/vitest.config.ts` `include:` glob for the test path.
- [ ] 1.2 Build a **fake octokit issue store** so issue-count is observable (NOT the
      mocked-spawn proxy). New `…-dedup.test.ts` if the heartbeat test mocks don't fit.
- [ ] 1.3 RED: two serialized same-date invocations → exactly ONE digest (H-A); OR
      eval-step throw-after-side-effect → no duplicate on retry (H-B).
- [ ] 1.4 RED: skip path posts OK heartbeat (no false-RED); FAILED/audit stub does NOT
      suppress a real digest; LIST-read error fails OPEN (spawns).

## Phase 2 — Fix (primary = handler-side LIST date-dedup)

- [ ] 2.1 Extract `digestIssueExistsForDate(label, date)` in `_cron-shared.ts` from the
      `ensureScheduledAuditIssue` LIST shape (`:1091-1101`): LIST endpoint (not search),
      date anchor `runStartedAt.slice(0,10)`, **exclude** `- FAILED` titles +
      `Automated FAILED self-report` bodies, **fail-OPEN** on read error.
- [ ] 2.2 Wire the dedup into `cron-community-monitor.ts` to short-circuit the second
      serialized invocation's eval/issue; on skip, short-circuit to an OK heartbeat.
- [ ] 2.3 If Phase 0 = H-B: switch the in-prompt `DEDUP RULE` (`:227-229`) from
      `--search '… in:title'` to `gh issue list --label … --json …` (fresh index) and/or
      make issue-create idempotent (pre-spawn step is memoized → won't cover H-B).
- [ ] 2.4 Do NOT add Inngest `idempotency`/`debounce`; do NOT touch
      `resolveOutputAwareOk`/`verifyScheduledIssueCreated` beyond the skip-path OK.

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.2 New test GREEN; `cron-community-monitor{,-heartbeat}.test.ts` stay green.
- [ ] 3.3 Test asserts issue-count == 1 (invariant via fake store), not "mock called".
- [ ] 3.4 PR body: `Ref #5751`; close #5751 after the post-deploy single-issue probe.
