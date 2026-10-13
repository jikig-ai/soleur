# Phase 0 finding — #5751 production root-cause confirmation

**Verdict: H-A (multiple serialized invocations) COMPOUNDED by H-C (stale-search-index in-prompt DEDUP RULE).** Not H-B (single-run retry).

## Evidence

### Issue create-time cross-check (`gh issue view`, all `app/soleur-ai`, all digests)

| date | issue | createdAt (UTC) | gap | vs 08:00 cron |
|---|---|---|---|---|
| 2026-06-30 | #5737 | 07:04:36 | — | **before cron** |
| 2026-06-30 | #5740 | 07:08:04 | +3m28s | **before cron** |
| 2026-06-21 | #5596 | 08:05:21 | — | after cron |
| 2026-06-21 | #5597 | 08:06:49 | +1m28s | after cron |
| 2026-06-20 | #5592 | 08:05:37 | — | after cron |
| 2026-06-20 | #5593 | 08:08:06 | +2m29s | after cron |

The 2026-06-30 pair is the decisive observation: **both digests were filed BEFORE the 08:00 UTC scheduled cron**, so both came from operator manual-trigger events (`cron/community-monitor.manual-trigger`) on a recovery day — i.e. **two distinct handler invocations**, not one run's retry. This rules in H-A. The 1.5–3.5 min gaps are shorter than a full ~5-min eval, which independently weakens H-B (a retried `claude-eval` step would re-spawn a full eval ≈ one eval-duration later).

### `routine_runs` pull (prod, `DATABASE_URL_POOLER` :6543→:5432, ssl rejectUnauthorized:false)

Columns: `id, routine_id, run_id, status, trigger_source, actor_class, actor_id, delegating_principal, started_at, ended_at, duration_ms, error_summary` (no `attempt` column).

- Table range: 2026-06-16 → 2026-06-30 (1889 rows).
- `routine_id='cron-community-monitor'`: rows for **06-22 through 06-29 only — exactly ONE `scheduled` row per clean day**. There are **NO rows for the three double-file dates 06-20, 06-21, 06-30** (all in range), consistent with the #5728 silent-missed era where the terminal run-log/heartbeat step never recorded even though the eval ran and filed issues.

`routine_runs` therefore cannot supply per-attempt discrimination for the affected days (rows absent; no `attempt` column), so the H-A verdict rests on the issue-timing cross-check above (the 06-30 both-before-cron pair is dispositive).

### H-C compound

All six issues are full eval **digests** (live `## Platform Status` / `## Key Metrics`), NOT the `ensureScheduledAuditIssue` `Automated FAILED self-report` stub — confirming the premise in the plan that the second issue is a second eval digest, not the audit fallback. The reason neither invocation suppressed the other: the in-prompt `DEDUP RULE` read the GitHub **search** index (`gh issue list --search 'Community Monitor in:title'`), which lags the primary index by minutes, so the second invocation 1.5–3.5 min later did not see the first issue.

## Fix mapping

- **H-A → handler-side fresh-LIST date-dedup** (PRIMARY): reliable because `concurrency:{scope:"fn",limit:1}` serializes the two invocations, so the second's LIST read runs after the first's create. `digestIssueExistsForDate(...)` keyed on `runStartedAt.slice(0,10)`, FAILED/audit-stub excluded, fail-OPEN. Skip path posts an OK heartbeat (no false-RED).
- **H-C → in-prompt DEDUP RULE switched** from `--search '… in:title'` (stale index) to `gh issue list --label … --json …` (fresh LIST index).
- **NOT** Inngest `idempotency`/`debounce` (disjoint trigger payloads → empty-key collapse; no H-B coverage) — per the deepen-pass verdict.
