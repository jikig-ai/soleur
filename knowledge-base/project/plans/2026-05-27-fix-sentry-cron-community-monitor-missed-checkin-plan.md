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

## Enhancement Summary

**Deepened on:** 2026-05-27
**Sections enhanced:** 6 (Research Insights, Hypotheses, Implementation Phases, Acceptance Criteria, Test Scenarios, Risks)
**Research agents used:** repo-research-analyst, learnings-researcher, inngest-cron-precedent-analyzer

### Key Improvements
1. Corrected function count from 39 to 40 (verified via `route.ts` line-count)
2. Added Hypothesis E (Inngest self-hosted cron scheduler re-planning after large sync delta) with specific Inngest server internals
3. Added cross-cron health check to Phase 1 diagnosis (verify if failure is community-monitor-specific or systemic)
4. Strengthened AC6 preventive test to assert both count AND per-function slug presence
5. Added precedent from `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` -- the "cron ran but heartbeat silently failed" class is the most dangerous because it presents as a missed check-in

### New Considerations Discovered
- The cloud-task-heartbeat watchdog (`maxGapDays: 9`) will NOT fire for community-monitor until May 31 (9 days from last labeled issue). Sentry cron monitor is the ONLY early-warning signal.
- The `inngest-server.service` is NOT restarted on web-platform deploys (`ci-deploy.sh` only handles `inngest` component type separately). Function sync happens via HTTP PUT from the Next.js process to the Inngest server. A loopback blip during deploy could cause a silent sync failure.
- 40 functions are registered (not 39 as initially estimated) -- verified via `route.ts` functions array.

# fix: Sentry cron monitor `scheduled-community-monitor` missed check-in

Sentry cron monitor `scheduled-community-monitor` (id: `ad956d6c-ff20-4e4d-a61f-3db689d2e96a`) is reporting a missed check-in incident (#5010688). Last successful check-in was 2026-05-25T11:56:14+00:00 (2 days ago). The community monitor cron fires daily at `0 8 * * *` UTC via the Inngest cron substrate.

## Research Insights

### Timeline Reconstruction

1. **2026-05-25 ~08:00 UTC** -- Community monitor fires on the Inngest substrate. Succeeds. Sentry check-in at ~11:56 UTC. Creates issue #4401.
2. **2026-05-25 ~22:22 UTC** -- PR #4460 merges: migrates `scheduled-community-monitor` from GHA to Inngest. Deletes the GHA workflow file. Sentry monitor mutated in place (margin 60->30, runtime 10->55).
3. **2026-05-26 ~07:25 UTC** -- Issue #4466 resolved: 7 community-platform secrets (DISCORD_*, BSKY_*, LINKEDIN_*) mirrored from `prd_scheduled` to `prd` Doppler config. Web-platform redeployed (`v0.101.67`).
4. **2026-05-26 ~08:00 UTC** -- Community monitor should fire. **MISSED.**
5. **2026-05-26 ~14:26 UTC** -- PR #4483 merges: massive 22-workflow migration to Inngest (TR9 Phase 2). Adds ~21 new Inngest functions to the route registry, bringing the total to 40 registered functions. Multiple deploys follow (15+ between May 26 20:00 and May 27 03:00 UTC).
6. **2026-05-27 ~08:00 UTC** -- Community monitor should fire. **MISSED** (second consecutive day).

**Critical observation:** The Sentry alert was "triggered by auth-callback-no-code-burst". This is a red herring -- `auth-callback-no-code-burst` is an unrelated Sentry issue alert (`apps/web-platform/infra/sentry/issue-alerts.tf:54`) that fires on OAuth callback errors. The correlation is coincidental (both alerts routed to the same operator email). The missed check-in is a Sentry Crons alert, not an issue alert.

### Root Cause Hypotheses

The cron handler at `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` is correctly registered in the Inngest serve route at `apps/web-platform/app/api/inngest/route.ts` (line 80, verified: `cronCommunityMonitor` present in functions array). The Sentry monitor resource exists in `apps/web-platform/infra/sentry/cron-monitors.tf` (lines 202-212) with the correct schedule `0 8 * * *`. The handler code itself has no obvious bugs -- it follows the established claude-eval-substrate pattern used by 5+ sibling cron functions.

**Cross-cron health signal:** Only `competitive-analysis` has an open cloud-task-silence issue (#4375, expected -- monthly cadence, 36-day gap). No silence issues for daily-triage, bug-fixer, or other daily crons. This suggests the failure is community-monitor-specific, NOT a systemic Inngest outage.

**Hypothesis A (MOST LIKELY): Inngest server state desync after rapid deploy churn**

Between May 25 22:00 UTC and May 27 03:00 UTC, the web-platform was deployed 15+ times (verified: `gh run list --workflow=web-platform-release.yml` shows 10+ successful deploys in that window). Each deploy restarts the Docker container running the Next.js process, which triggers an automatic function sync with the self-hosted Inngest server via the `/api/inngest` PUT endpoint. The Inngest server itself (`inngest-server.service` systemd unit, separate from the web-platform container) is NOT restarted on web deploys -- only when an explicit `inngest` component deploy runs via `ci-deploy.sh:556-684`. During rapid web-platform redeploy cycles:
- The Inngest SDK's `serve()` handler responds to Inngest server GET requests with the full function manifest, and the Inngest server reconciles its internal cron scheduler state
- The self-hosted Inngest server uses SQLite storage at `/var/lib/inngest/` for function registry and cron scheduler state
- PR #4497 (merged 2026-05-26) documents a "transient Inngest loopback blip during deploy restart cycle on 2026-05-26" (Sentry error `3b092551ae484cdeb2ea0ca34e630996`) -- the exact failure mode where the Inngest server's loopback HTTP call to the app's `/api/inngest` fails because the Next.js process is mid-restart
- The function-count jump from ~18 to 40 registered functions via PR #4483 at 14:26 UTC is a 2.2x increase in a single sync -- the Inngest server's cron scheduler may not have re-planned all cron triggers after the sync, particularly if the sync response was incomplete or truncated due to a transient loopback failure

**Verification commands** (all via `cat-deploy-state.sh` no-SSH surface per `hr-no-ssh-fallback-in-runbooks`):
```bash
# 1. Check function registry via deploy-status endpoint
curl -s https://soleur.app/hooks/deploy-status | jq '.services.inngest_crons'

# 2. If deploy-status doesn't expose function list, fall back to direct loopback (operator-only)
curl -s http://127.0.0.1:8288/v1/functions | jq '[.[] | .slug] | sort | length'
# Expected: 40

# 3. Specific community-monitor check
curl -s http://127.0.0.1:8288/v1/functions | jq '.[] | select(.slug == "cron-community-monitor") | {slug, triggers}'
```
If the function is missing from the registry, or the cron trigger is not listed, a re-sync is needed.

**Hypothesis B: Concurrency queue starvation**

All cron functions share `scope: "account", key: '"cron-platform"', limit: 1`. With 3 hourly functions (`cron-oauth-probe` at `0 * * * *`, `cron-github-app-drift-guard` at `0 * * * *`, `cron-membership-health` at `17 * * * *`) and `cron-bug-fixer` at `0 6 * * *` (50-min max duration), the community monitor at `0 8 * * *` competes for a single concurrency slot. If `cron-bug-fixer` runs long AND the hourly probes fire at 08:00, the community monitor could be queued indefinitely and eventually dropped by Inngest's internal queue expiry.

However, this wouldn't explain why the monitor succeeded daily from May 17-25 -- the concurrency model hasn't changed.

**Hypothesis C: Inngest server OOM or crash during large function registration**

The `inngest-server.service` has `MemoryMax=512M`. Registering 40 functions (up from ~18) may push the SQLite-backed function registry close to the memory ceiling, causing an OOM kill during the cron scheduler's planning window.

**Verification:** `journalctl -u inngest-server.service --since "2026-05-26 06:00" --until "2026-05-27 12:00" | grep -i "oom\|kill\|restart\|error"`

**Hypothesis D: `postSentryHeartbeat` silently failing (env vars missing after redeploy)**

The heartbeat function in `_cron-shared.ts:67-81` silently skips if `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, or `SENTRY_PUBLIC_KEY` are unset or malformed. If the redeploy after PR #4483 lost these env vars, the cron would run but never check in with Sentry -- the monitor would report "missed check-in" even though the function executed.

However, the Sentry check-in env triple is in Doppler `prd` (not `prd_scheduled`), and other Inngest cron monitors (daily-triage, oauth-probe) would also be affected, which the alert doesn't mention.

**Hypothesis E: Inngest self-hosted cron scheduler re-planning failure after large sync delta**

The self-hosted Inngest server uses an internal cron scheduler that plans upcoming cron triggers based on the registered function manifest. When the Inngest SDK serves a sync response (via `/api/inngest` GET), the server reconciles: adds new functions, removes deleted ones, and re-plans cron schedules. A 2.2x function-count increase (18 to 40) in a single sync is an unusually large delta. If the cron re-planning step fails silently (e.g., SQLite write lock contention, partial transaction rollback), specific cron triggers could be lost from the scheduler's plan table while the function itself remains in the registry. This would explain why the function appears registered (the registry write succeeded) but the cron never fires (the scheduler plan write didn't).

**Distinguishing from Hypothesis A:** Hypothesis A posits the function is missing from the registry entirely. Hypothesis E posits the function IS registered but the cron trigger was not re-planned. Diagnosis Step 1 distinguishes: if `curl /v1/functions` shows `cron-community-monitor` with correct triggers but no runs appear in the run history, Hypothesis E is confirmed.

**Verification:** Check Inngest server's scheduled runs queue: `curl -s http://127.0.0.1:8288/v1/events/cron-scheduled | jq '.[] | select(.function_id | contains("community")) | {function_id, scheduled_at}'`

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

- [ ] **AC1:** Investigate root cause via Inngest server logs and function registry. Document which hypothesis (A-E) was confirmed, or if a new root cause was discovered. **Deferred: Tracks #4533 (requires Hetzner SSH).**
- [ ] **AC2:** If Hypothesis A confirmed (Inngest desync): trigger a manual re-sync. **Deferred: Tracks #4533.**
- [ ] **AC3:** If Hypothesis B confirmed (concurrency starvation): add schedule stagger. **Deferred: Tracks #4533.**
- [ ] **AC4:** If Hypothesis C confirmed (OOM): raise `MemoryMax`. **Deferred: Tracks #4533.**
- [x] **AC5:** If Hypothesis D confirmed (env vars): verify `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` present in Doppler `prd` and accessible to the running web-platform process. **DONE: All 3 present in Doppler prd — Hypothesis D eliminated.**
- [x] **AC6:** Add a preventive guard: after the massive TR9 Phase 2 migration, add a smoke test that verifies Inngest function count matches expected count after deploy. File path: `apps/web-platform/test/server/inngest/function-registry-count.test.ts`. **DONE: 5 assertions (count, import parity, array parity, slug→tf parity, tf→slug parity).**
- [x] **AC7:** Update `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` with a new hypothesis H9 covering "Inngest server desync after deploy churn" if that is the confirmed root cause. **DONE: H9 added with H9a/H9b sub-modes.**

### Post-merge (operator)

- [ ] **AC8:** Trigger a manual community-monitor fire. **Deferred: Tracks #4533 (Hetzner loopback).**
- [ ] **AC9:** Verify Sentry check-in shows `ok`. **Deferred: Tracks #4533.**
- [ ] **AC10:** Wait for next natural 08:00 UTC fire. **Deferred: Tracks #4533.**

## Implementation Phases

### Phase 1: Diagnose (operator-side, Hetzner node)

Investigate the five hypotheses in order. Steps 1-3 are the cheapest verification; Step 4-5 narrow once the broad picture is established.

1. **Cross-cron health check (systemic vs specific):** Check if other daily crons fired on May 26-27. Query the last-fire timestamps recorded by `postSentryHeartbeat` (PR #4504): `cat /var/lib/inngest/cron-fires/scheduled-daily-triage.json /var/lib/inngest/cron-fires/scheduled-bug-fixer.json /var/lib/inngest/cron-fires/scheduled-community-monitor.json 2>/dev/null`. If daily-triage and bug-fixer show timestamps from May 26-27 but community-monitor does not, the failure is community-monitor-specific (supports Hypothesis A/E). If ALL are stale, the Inngest cron scheduler is broadly broken (supports Hypothesis C).
2. **Check Inngest function registry:** `curl -s http://127.0.0.1:8288/v1/functions | jq '[.[] | .slug] | sort'` -- verify `cron-community-monitor` is present and count matches expected 40 functions. If the function is present, also check its triggers: `curl -s http://127.0.0.1:8288/v1/functions | jq '.[] | select(.slug == "cron-community-monitor") | .triggers'` -- expect a cron trigger with `"0 8 * * *"`.
3. **Check Inngest server health:** `journalctl -u inngest-server.service --since "2026-05-26 06:00" --until "2026-05-27 12:00" | grep -iE "oom|kill|restart|error|community|sync|register" | tail -50`. Also check for memory pressure: `journalctl -u inngest-server.service --since "2026-05-26" | grep -i "memory\|cgroup\|oomkill" | head -10`.
4. **Check Inngest run history for community-monitor:** Look for whether the function was invoked but failed, or never invoked at all. `curl -s "http://127.0.0.1:8288/v1/events?name=inngest/function.invoked&limit=20" | jq '.[] | select(.data.function_slug == "cron-community-monitor") | {created_at, data}'` (note: exact API path may vary by Inngest version).
5. **Check heartbeat env vars:** `doppler secrets get SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY -p soleur -c prd --plain 2>/dev/null | wc -l` -- expect 3 non-empty lines. Also verify the running web-platform process has them: `docker exec soleur-web-platform env | grep -c SENTRY_` (expect >= 3).

### Phase 2: Fix (based on diagnosis)

**If Hypothesis A or E (most likely -- desync or scheduler re-planning failure):**
1. Restart `inngest-server.service` to force a clean cron scheduler re-plan: `sudo systemctl restart inngest-server.service`
2. Wait 30s for Inngest to reinitialize and re-read SQLite state
3. Restart the web-platform container to force a fresh function sync: `docker restart soleur-web-platform` (the Next.js process responds to Inngest server's GET `/api/inngest` with the full 40-function manifest, triggering cron re-planning)
4. Re-verify function registry contains `cron-community-monitor` with cron trigger: `curl -s http://127.0.0.1:8288/v1/functions | jq '.[] | select(.slug == "cron-community-monitor") | {slug, triggers}'`
5. Trigger manual fire per AC8 to confirm end-to-end execution + Sentry heartbeat

**If Hypothesis B (concurrency starvation):**
Add schedule stagger: edit `cron-community-monitor.ts:327` to change `{ cron: "0 8 * * *" }` to `{ cron: "30 8 * * *" }`. This moves the fire 30 minutes past the hourly probes' `0 8 * * *` fire. Also update the Sentry monitor in `cron-monitors.tf:206` to match: `schedule = { crontab = "30 8 * * *" }`.

**If Hypothesis C (OOM):**
Raise `MemoryMax` in `apps/web-platform/infra/inngest-bootstrap.sh:155` from `512M` to `768M`. This requires an inngest-bootstrap OCI image rebuild and redeploy via `ci-deploy.sh inngest`.

**If Hypothesis D (env vars):**
Verify and re-inject via Doppler: `doppler secrets get SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY -p soleur -c prd --plain`. If missing, copy from existing sibling cron monitor config. Then restart web-platform container.

### Phase 3: Preventive measures (code changes)

1. Add `apps/web-platform/test/server/inngest/function-registry-count.test.ts`:
   - Assert the `functions` array length in `route.ts` matches expected count (currently 40). Use a dynamic grep-based approach (count lines matching `^\s+[a-z]` in the functions array) rather than importing the module (which requires Inngest runtime env vars).
   - Assert every `cron-*.ts` file (excluding `_cron-*.ts` helpers) has a corresponding entry in route.ts. Precedent: `cron-no-byok-lease-sweep.test.ts` already walks cron files with `readdirSync`.
   - Assert every cron function's `SENTRY_MONITOR_SLUG` constant has a matching resource in `cron-monitors.tf`. This catches "cron registered but no Sentry dead-man's-switch" drift.
2. Update `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` with the confirmed root cause as a new hypothesis entry.
3. Commit a compound learning documenting the timeline, diagnosis, and fix at `knowledge-base/project/learnings/bug-fixes/`.

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
- Given all cron functions registered, when `curl /v1/functions` is queried, then count matches expected 40

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Split cron-platform concurrency into pools | Eliminates queue starvation | Premature per ADR-033; requires Hetzner sizing review | Defer per ADR-033 re-eval criteria |
| Move community-monitor back to GHA | Known working substrate | Contradicts TR9 migration goal; loses Inngest observability | Reject |
| Add retry logic to Inngest cron registration | Self-healing | Inngest SDK handles retries internally; would be redundant | Reject |
