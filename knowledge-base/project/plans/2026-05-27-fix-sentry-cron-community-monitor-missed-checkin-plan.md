---
title: "fix: Sentry cron monitor scheduled-community-monitor missed check-in"
type: fix
date: 2026-05-27
classification: ops-remediation
branch: feat-one-shot-fix-sentry-cron-community-monitor
worktree: .worktrees/feat-one-shot-fix-sentry-cron-community-monitor
lane: single-domain
requires_cpo_signoff: false
---

# fix: Sentry cron monitor `scheduled-community-monitor` missed check-in

Sentry cron monitor `scheduled-community-monitor` (id: `ad956d6c-ff20-4e4d-a61f-3db689d2e96a`) is reporting a missed check-in incident (#5010688). Last successful check-in was 2026-05-25T11:56:14+00:00 (2 days ago). The community monitor cron fires daily at `0 8 * * *` UTC via the Inngest cron substrate.

## Research Insights

### Timeline Reconstruction

1. **2026-05-25 ~08:00 UTC** -- Community monitor fires on the Inngest substrate. Succeeds. Sentry check-in at ~11:56 UTC. Creates issue #4401.
2. **2026-05-25 ~22:22 UTC** -- PR #4460 merges: migrates `scheduled-community-monitor` from GHA to Inngest. Deletes the GHA workflow file. Sentry monitor mutated in place (margin 60->30, runtime 10->55).
3. **2026-05-26 ~07:25 UTC** -- Issue #4466 resolved: 7 community-platform secrets (DISCORD_*, BSKY_*, LINKEDIN_*) mirrored from `prd_scheduled` to `prd` Doppler config. Web-platform redeployed (`v0.101.67`).
4. **2026-05-26 ~08:00 UTC** -- Community monitor should fire. **MISSED.**
5. **2026-05-26 ~14:26 UTC** -- PR #4483 merges: massive 22-workflow migration to Inngest (TR9 Phase 2). Adds ~21 new Inngest functions to the route registry, going from ~18 to ~39 registered functions. Multiple deploys follow throughout the day.
6. **2026-05-27 ~08:00 UTC** -- Community monitor should fire. **MISSED** (second consecutive day).

### Root Cause Hypotheses

The cron handler at `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` is correctly registered in the Inngest serve route at `apps/web-platform/app/api/inngest/route.ts` (line 80). The Sentry monitor resource exists in `apps/web-platform/infra/sentry/cron-monitors.tf` (lines 202-212) with the correct schedule `0 8 * * *`. The handler code itself has no obvious bugs -- it follows the established claude-eval-substrate pattern used by 5+ sibling cron functions.

**Hypothesis A (MOST LIKELY): Inngest server state desync after rapid deploy churn**

Between May 25 22:00 UTC and May 27 03:00 UTC, the web-platform was deployed 15+ times. Each deploy restarts the Next.js process (which registers functions with Inngest via the `/api/inngest` PUT sync endpoint). The Inngest server itself (`inngest-server.service` systemd unit) runs on the same Hetzner node using SQLite storage at `/var/lib/inngest/`. During rapid deploy-restart cycles:
- The self-hosted Inngest server receives multiple sync requests in quick succession
- The cron scheduler may lose track of registered functions during a narrow race window
- PR #4497 (merged 2026-05-26) documents a "transient Inngest loopback blip during deploy restart cycle on 2026-05-26" (Sentry error `3b092551ae484cdeb2ea0ca34e630996`)
- The massive function-count jump (18->39 functions) via PR #4483 at 14:26 UTC may have triggered an incomplete sync

**Verification command:** SSH into the Hetzner node and query the Inngest server's function registry:
```bash
curl -s http://127.0.0.1:8288/v1/functions | jq '.[] | select(.slug == "cron-community-monitor") | {slug, triggers}'
```
If the function is missing from the registry, a re-sync is needed.

**Hypothesis B: Concurrency queue starvation**

All cron functions share `scope: "account", key: '"cron-platform"', limit: 1`. With 3 hourly functions (`cron-oauth-probe` at `0 * * * *`, `cron-github-app-drift-guard` at `0 * * * *`, `cron-membership-health` at `17 * * * *`) and `cron-bug-fixer` at `0 6 * * *` (50-min max duration), the community monitor at `0 8 * * *` competes for a single concurrency slot. If `cron-bug-fixer` runs long AND the hourly probes fire at 08:00, the community monitor could be queued indefinitely and eventually dropped by Inngest's internal queue expiry.

However, this wouldn't explain why the monitor succeeded daily from May 17-25 -- the concurrency model hasn't changed.

**Hypothesis C: Inngest server OOM or crash during large function registration**

The `inngest-server.service` has `MemoryMax=512M`. Registering 39 functions (up from ~18) may push the SQLite-backed function registry close to the memory ceiling, causing an OOM kill during the cron scheduler's planning window.

**Verification:** `journalctl -u inngest-server.service --since "2026-05-26 06:00" --until "2026-05-27 12:00" | grep -i "oom\|kill\|restart\|error"`

**Hypothesis D: `postSentryHeartbeat` silently failing (env vars missing after redeploy)**

The heartbeat function in `_cron-shared.ts:67-81` silently skips if `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, or `SENTRY_PUBLIC_KEY` are unset or malformed. If the redeploy after PR #4483 lost these env vars, the cron would run but never check in with Sentry -- the monitor would report "missed check-in" even though the function executed.

However, the Sentry check-in env triple is in Doppler `prd` (not `prd_scheduled`), and other Inngest cron monitors (daily-triage, oauth-probe) would also be affected, which the alert doesn't mention.

### Codebase Patterns

- **Sentry heartbeat mechanism:** `_cron-shared.ts:postSentryHeartbeat()` POSTs to `https://{SENTRY_INGEST_DOMAIN}/api/{SENTRY_PROJECT_ID}/cron/{slug}/{SENTRY_PUBLIC_KEY}/?status={ok|error}` with a 10s timeout
- **Concurrency model:** All cron-* functions share `account-scope "cron-platform" limit: 1` per ADR-033
- **Inngest server:** Self-hosted on Hetzner, `inngest-server.service` systemd unit, SQLite at `/var/lib/inngest/`, MemoryMax 512M
- **Deploy mechanism:** `ci-deploy.sh` rebuilds the Docker container and restarts; Inngest syncs functions via PUT to `/api/inngest`

### Learnings Applied

- `knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` -- silent heartbeat failures are the most common cause of "missed check-in" when the cron actually ran
- `knowledge-base/project/learnings/2026-04-21-cloud-task-silence-watchdog-pattern.md` -- silence = neither success nor failure issue = task did not run at all
- `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` -- H1-H8 diagnosis checklist

## User-Brand Impact

- **If this lands broken, the user experiences:** No direct user impact. Community monitoring produces internal digests; the founder (sole operator) loses daily visibility into community platform activity.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A -- community monitor reads public data (Discord, GitHub, X, Bluesky, HN). No PII, no secrets in output.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor scheduled-community-monitor
  cadence: daily at 08:00 UTC (with 30-min margin)
  alert_target: Sentry issue (incident #5010688) -> operator email
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf:202-212

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN (reportSilentFallback)
  fail_loud: Sentry cron monitor missed-check-in alert; [cloud-task-silence] watchdog issue

failure_modes:
  - mode: Inngest function registry desync after deploy
    detection: Sentry cron monitor missed-check-in (checkin_margin_minutes = 30)
    alert_route: Sentry issue -> operator email
  - mode: Concurrency queue starvation
    detection: Sentry cron monitor missed-check-in + other crons still firing
    alert_route: Sentry issue -> operator email
  - mode: Inngest server OOM crash
    detection: journalctl inngest-server.service shows OOM kill
    alert_route: Better Stack heartbeat (inngest-heartbeat.timer) + Sentry missed check-in

logs:
  where: journalctl -u inngest-server.service + Inngest web UI at 127.0.0.1:8288
  retention: journald default (1GB cap on Hetzner), Sentry 90 days

discoverability_test:
  command: curl -s https://soleur.app/api/inngest | jq '.functions[] | select(.slug == "cron-community-monitor") | .slug'
  expected_output: '"cron-community-monitor"'
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** Investigate root cause via Inngest server logs and function registry. Document which hypothesis (A-D) was confirmed, or if a new root cause was discovered.
- [ ] **AC2:** If Hypothesis A confirmed (Inngest desync): trigger a manual re-sync of the Inngest function registry by restarting the web-platform container (which re-POSTs the function list to Inngest) AND restarting `inngest-server.service` if needed.
- [ ] **AC3:** If Hypothesis B confirmed (concurrency starvation): add schedule stagger to community-monitor (e.g., move from `0 8` to `30 8` or `0 8` with explicit queue priority) to avoid collision with hourly probes.
- [ ] **AC4:** If Hypothesis C confirmed (OOM): raise `MemoryMax` for `inngest-server.service` in `apps/web-platform/infra/inngest-bootstrap.sh:155` from `512M` to `768M` (Hetzner cx33 has 8GB RAM).
- [ ] **AC5:** If Hypothesis D confirmed (env vars): verify `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` present in Doppler `prd` and accessible to the running web-platform process.
- [ ] **AC6:** Add a preventive guard: after the massive TR9 Phase 2 migration, add a smoke test that verifies Inngest function count matches expected count after deploy. File path: `apps/web-platform/test/server/inngest/function-registry-count.test.ts`.
- [ ] **AC7:** Update `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` with a new hypothesis H9 covering "Inngest server desync after deploy churn" if that is the confirmed root cause.

### Post-merge (operator)

- [ ] **AC8:** Trigger a manual community-monitor fire via Inngest event: `curl -X POST http://127.0.0.1:8288/e/cron%2Fcommunity-monitor.manual-trigger -H "Content-Type: application/json" -d '{"name":"cron/community-monitor.manual-trigger","data":{}}' -H "Authorization: Bearer ${INNGEST_EVENT_KEY}"`. Automation: not feasible because the command targets the Hetzner-local loopback (127.0.0.1:8288), not a public endpoint.
- [ ] **AC9:** Verify Sentry cron monitor `scheduled-community-monitor` shows a successful check-in after the manual trigger. Verification via: `curl -sH "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" "https://sentry.io/api/0/organizations/jikigai/monitors/scheduled-community-monitor/checkins/?limit=3" | jq '.[0].status'` -- expect `"ok"`.
- [ ] **AC10:** Wait for the next natural 08:00 UTC fire on the day after merge. Verify issue `[Scheduled] Community Monitor - YYYY-MM-DD` is created with label `scheduled-community-monitor`. Verification via: `gh issue list --label scheduled-community-monitor --state all --limit 1 --json number,title,createdAt`.

## Implementation Phases

### Phase 1: Diagnose (operator-side, Hetzner node)

Investigate the four hypotheses in order by querying the Hetzner node:

1. Check Inngest function registry: `curl -s http://127.0.0.1:8288/v1/functions | jq '[.[] | .slug] | sort'` -- verify `cron-community-monitor` is present and count matches expected 39 functions.
2. Check Inngest server logs: `journalctl -u inngest-server.service --since "2026-05-26 06:00" --until "2026-05-27 12:00" | grep -iE "oom|kill|restart|error|community|sync|register" | tail -50`.
3. Check for heartbeat env vars: `doppler secrets get SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY -p soleur -c prd --plain 2>/dev/null | wc -l` -- expect 3 non-empty lines.
4. Check Inngest run history for community-monitor: `curl -s http://127.0.0.1:8288/v1/runs?function_slug=cron-community-monitor&limit=5 | jq '.[] | {id, status, started_at, ended_at}'` (note: exact API path may vary by Inngest version).

### Phase 2: Fix (based on diagnosis)

**If Hypothesis A (most likely):**
1. Restart `inngest-server.service`: `sudo systemctl restart inngest-server.service`
2. Wait 30s for Inngest to re-read SQLite state
3. Trigger a web-platform re-sync: `curl -X PUT http://127.0.0.1:8288/api/inngest -H "Content-Type: application/json"` (or restart the web-platform container which triggers auto-sync)
4. Re-verify function registry contains `cron-community-monitor`
5. Trigger manual fire per AC8

**If another hypothesis:**
Apply the appropriate fix per the AC (AC3/AC4/AC5).

### Phase 3: Preventive measures (code changes)

1. Add `apps/web-platform/test/server/inngest/function-registry-count.test.ts` that asserts the expected function count (currently 39) matches the `functions` array length in `route.ts`. This catches registration drift.
2. Update `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` with the confirmed root cause as H9.
3. Commit a compound learning documenting the diagnosis and fix.

## Files to Edit

| File | Change |
|------|--------|
| `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` | Add H9 hypothesis for Inngest desync after deploy churn |
| `apps/web-platform/test/server/inngest/function-registry-count.test.ts` | NEW: Assertion that function count matches route.ts registration array |

## Files to Create

| File | Purpose |
|------|---------|
| `knowledge-base/project/learnings/bug-fixes/sentry-cron-community-monitor-missed-checkin.md` | Document root cause, diagnosis steps, and fix |

## Open Code-Review Overlap

None

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Root cause is different from all four hypotheses | Phase 1 diagnosis is systematic; if all four hypotheses are excluded, escalate to Inngest server version investigation and file a tracking issue |
| Inngest server restart disrupts running cron functions | The `cron-platform` concurrency limit is 1; restart during the cron quiet window (after 14:00 UTC daily-content-publisher, before 16:00 Monday campaign-calendar) minimizes blast radius |
| Manual trigger fires during natural cron window, creating duplicate issues | The community-monitor prompt has a DEDUP RULE that checks for recent open issues with the same label before creating new ones |

## Test Scenarios

- Given Inngest server restarted, when community-monitor manual trigger is sent, then function executes and Sentry receives `ok` check-in
- Given function-registry-count test exists, when a new Inngest function is added but not registered in route.ts, then test fails
- Given all cron functions registered, when `curl /v1/functions` is queried, then count matches expected 39

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Split cron-platform concurrency into pools | Eliminates queue starvation | Premature per ADR-033; requires Hetzner sizing review | Defer per ADR-033 re-eval criteria |
| Move community-monitor back to GHA | Known working substrate | Contradicts TR9 migration goal; loses Inngest observability | Reject |
| Add retry logic to Inngest cron registration | Self-healing | Inngest SDK handles retries internally; would be redundant | Reject |
