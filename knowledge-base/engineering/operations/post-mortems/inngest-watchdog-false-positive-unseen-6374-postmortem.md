---
title: "Inngest health-watchdog: false-positive P1 ran unseen ~14h + churned ~14 restarts on a healthy scheduler"
date: 2026-07-13
incident_pr: "#6384"
incident_window: "2026-07-12T20:43:00Z → 2026-07-13T08:15:00Z (~14h)"
recovery_at: "2026-07-13T08:15:00Z (approx — false alarm cleared when the eventsV2 read path recovered; inngest was never actually down)"
suspected_change: "The external watchdog's sole liveness signal rode the inventory hook's heavy 365-day eventsV2 read path (a #5542-era design), which can 500 on deadline/page-ceiling/pool/gateway faults while the cron executor stays healthy."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - observability-gap
  - false-positive-alarm
  - restart-churn
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/observability incident with zero personal-data exposure (the watchdog reads inngest process-liveness + open-issue metadata; it moves no user content). GDPR Art. 33/34 not engaged."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

On 2026-07-12/13 the external Inngest health watchdog (`.github/workflows/scheduled-inngest-health.yml`, built after the #5542 silent-crash-loop) filed a P1 `[ci/inngest-down]` issue (#6374) and auto-dispatched hourly-cadence (`*/15`) restarts of `restart-inngest-server.yml`. **Inngest was not actually down** — the `scheduled-inngest-cron-watchdog` Sentry monitor checked in `ok` at 20:01, 00:01, 04:00, and 08:00 UTC, spanning the entire alarm window, proving the cron executor fired throughout. The alarm was a **false positive**: the watchdog's sole liveness signal was the inventory hook's heavy 365-day `eventsV2` read, which returned HTTP 500 (`inventory hook HTTP 500: <empty body>` — a gateway/read-path fault, not the inventory script's FATAL-text body a genuine functions-query failure emits). Three observability defects compounded it: (1) the intended Sentry heartbeat had **no `sentry_cron_monitor` resource** for its slug, so it paged nowhere and the alarm sat only in a GitHub issue no operator watches → **~14h unseen**; (2) the probe false-positived because liveness rode the eventsV2 read; (3) the restart dispatch had **no cap**, bouncing a healthy scheduler ~14×.

## Status

resolved — all three defects fixed in PR #6384; #6374 confirmed false-positive.

## Symptom

A P1 `[ci/inngest-down]` GitHub issue (#6374) open + repeatedly commented, and `restart-inngest-server.yml` dispatched every `*/15` cycle, while inngest itself kept firing crons normally. No operator page (no Sentry email, no Slack, no SMS) for ~14h.

## Incident Timeline

- **Start time (detected):** 2026-07-12T20:43:00Z (watchdog filed #6374)
- **End time (recovered):** 2026-07-13T08:15:00Z (read-path fault cleared; no service recovery needed)
- **Duration (MTTR):** ~14h to human awareness (the false alarm itself was self-limiting; the *paging gap* is the real MTTR driver)

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-07-12 20:43 | Watchdog eventsV2 read 500s; files P1 #6374; dispatches restart. |
| system | 2026-07-12 20:43 → 2026-07-13 08:15 | ~14 restart dispatches at `*/15`; heartbeat posts to a non-existent Sentry monitor slug → pages nowhere. |
| system | 2026-07-12 20:01 / 00:01 / 04:00 / 08:00 | `scheduled-inngest-cron-watchdog` monitor checks in `ok` — executor alive throughout. |
| human | 2026-07-13 (day) | Operator notices #6374; routes `/soleur:go` to fix the watchdog defects. |
| agent | 2026-07-13 | PR #6384 fixes all three defects + adds a readiness advisory; #6374 verdict = false-positive. |

## Participants and Systems Involved

External GitHub Actions watchdog (`scheduled-inngest-health.yml`), the on-host inngest webhook hooks (`inngest-inventory` / new `inngest-liveness`), the self-hosted inngest-server, Sentry Crons (the missing monitor), and `restart-inngest-server.yml`.

## Detection (+ MTTD)

- **How detected:** external/manual — the operator eventually saw the open GitHub issue. The intended monitoring path (Sentry heartbeat) was silently dropped because its monitor slug had no IaC resource.
- **MTTD (mean time to detect):** ~14h — dominated entirely by the paging gap (Defect 1). With the fix, a single `?status=error` or missed check-in pages within one `*/15` cadence (~15–30 min).

## Triggered by

system — an eventsV2 read-path fault (deadline/page-ceiling/pool/gateway) on a probe that should never have gated liveness on that path.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Inngest actually down | #6374 title says "down" | `scheduled-inngest-cron-watchdog` checked in `ok` all window; 500 body was empty (gateway), not the inventory FATAL text | REJECTED |
| False positive from eventsV2 read-path fault + missing Sentry monitor + uncapped restart | 4 `ok` beacons spanning the window; empty-body 500; no monitor resource for the heartbeat slug; no restart cap in the workflow | CONFIRMED |

## Resolution

PR #6384: (1) added the `scheduled_inngest_health` `sentry_cron_monitor` + its `apply-sentry-infra.yml` `-target=` entry + a workflow-heartbeat↔IaC parity guard so a heartbeat can never again page into the void; (2) added an `INVENTORY_LIVENESS_ONLY` mode (cheap `/v0/gql functions` + `durability_state`, no eventsV2) behind a new `/hooks/inngest-liveness` hook the watchdog now probes, with a `probe_unavailable` classification so a broken/undeployed probe path never counts as `inngest_down`; (3) an issue-AGE give-up gate (~45 min) that caps restart churn and escalates to a loud "restarts exhausted" comment; (4) a readiness advisory in postmerge that surfaces open `[ci/inngest-down]` issues.

## Recovery verification

`scheduled-inngest-cron-watchdog` `ok` check-ins across the window (Sentry) prove the executor never failed. Post-merge: the new monitor auto-applies via `apply-sentry-infra.yml`; the liveness hook auto-applies via `apply-deploy-pipeline-fix.yml`; a forced `?status=error` will confirm the operator now receives the Sentry page.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did a P1 run unseen for 14h?** The operator-facing signal (Sentry heartbeat) paged nowhere.
2. **Why did it page nowhere?** The heartbeat posts to slug `scheduled-inngest-health`, which had **no `sentry_cron_monitor` resource** — Sentry silently drops check-ins for unknown slugs.
3. **Why was there no monitor resource?** The watchdog was built (post-#5542) with the heartbeat step but the IaC monitor was never added, and the existing parity guard covered only Inngest-function slugs, not GHA-workflow heartbeat slugs.
4. **Why was the alarm firing at all (falsely)?** The watchdog's sole liveness signal rode the inventory hook's heavy 365-day eventsV2 read, which 500'd on a gateway/read-path fault while crons fired.
5. **Why did it churn ~14 restarts?** The dispatch step had no cap and no give-up — a restart cannot fix a probe fault, so it bounced a healthy scheduler indefinitely.

**Final root cause:** a liveness probe coupled to an independent heavy read path, whose *only* surviving alarm channel was an unmonitored Sentry slug + an unwatched GitHub issue, with an uncapped self-remediation loop.

## Versions of Components

- **Version(s) that triggered the outage:** the pre-#6384 `scheduled-inngest-health.yml` + `inngest-inventory.sh` (eventsV2-coupled liveness; no Sentry monitor; no restart cap).
- **Version(s) that restored the service:** PR #6384 (liveness-only probe + monitor + parity guard + age-gate).

## Impact details

### Services Impacted

None at runtime — inngest continued firing all `server/inngest/functions/` crons (armed reminders, KB sync, triage). The impact was to the *monitoring layer*: a false P1, ~14 wasted restart dispatches, and a 14h-blind window that would have equally hidden a **real** outage.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none actual — scheduled actions (reminders, syncs) fired normally. Latent risk: a *real* inngest outage would have gone equally unseen, silently dropping a user's scheduled action.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Operator attention diverted to triage a false P1; ~14 no-op restart dispatches consumed CI minutes and briefly bounced a healthy scheduler.

## Lessons Learned

### Where we got lucky

Inngest was genuinely healthy — the same 14h-blind paging gap on a *real* outage would have silently dropped every user's scheduled action. The false positive surfaced the gap before a real one did.

### What went well

The independent `scheduled-inngest-cron-watchdog` beacon gave an unambiguous "executor was alive" signal that made the false-positive determination decisive rather than guesswork.

### What went wrong

A heartbeat was emitted to a Sentry monitor slug that did not exist in IaC (paged nowhere); the liveness signal was coupled to a heavy independent read path; and the auto-restart loop had no cap or give-up.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._

## Residual vector — #6407 (functions-query transient)

**Discovered:** 2026-07-14, after 6 recurrences of `[ci/inngest-down]` in ~2 days (2026-07-12 → 07-14), each a false-positive P1 whose dispatched auto-restart then RED-failed.

**What #6374 did not close.** #6374 decoupled the liveness verdict from the heavy 365-day `eventsV2` read (the original false-positive path). It did NOT anticipate the **cheap `/v0/gql functions` liveness query ITSELF transiently failing**: a curl transport blip makes `fetch_functions()` emit `{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}`, which trips the fail-loud FATAL guard (`inngest-inventory.sh`) → the webhook wraps it as HTTP 500 + FATAL body → the classifier maps any `inngest-inventory: FATAL` body to `inngest_down` → restart family. The watchdog's 3× retry (8s apart) does not help a transport blip persisting ~24s. During run 29334263944 the deploy-status payload showed `services.inngest_server="active"`, `restart_count:0`, `sandbox_canary.verdict="pass"`, and Better Stack showed inngest live-processing events throughout — a healthy process, a transient GQL read. **The FATAL exit happened BEFORE any process-liveness check** — the independent "is the HTTP server serving?" signal that would falsify the down verdict was never consulted.

**Compounding failure — the failed remediation.** The dispatched restart sent `restart inngest _ latest` to `ci-deploy.sh`, whose FD-200 advisory `flock -n 200` is non-blocking; a loser wrote `final_write_state 1 "lock_contention"` exit 1, and the restart-verify poll latched it as a terminal failure → `::error::Restart failed` → RED. But `lock_contention` on a restart means another deploy/restart already holds the critical section and will bring inngest current — benign. The sibling web-platform-release deploy poll already treated `lock_contention` as non-terminal (ADR-079 amendment #5960); the restart poll never got that treatment.

**Fix (#6407).**
1. **`/health` corroboration before `inngest_down`.** In `INVENTORY_LIVENESS_ONLY` mode, before emitting the FATAL sentinel on a functions-query failure, `inngest-inventory.sh` probes the SAME loopback server's `/health` (the endpoint `ci-deploy.sh verify_inngest_health` gates on). `/health=200` (server serving; GQL read blipped) → a new **soft** `inngest-inventory: DEGRADED` sentinel → classifier mode `functions_query_degraded` (NO restart, own `[ci/inngest-functions-degraded]` soft issue, heartbeat `ok`). `/health != 200` (wedged/stopped) → keep FATAL → `inngest_down` → restart (recovers a wedge). `systemctl is-active`/ExecStart were rejected — both read for a wedged/stopped unit; `/health` is the only same-signal-class corroborator.
2. **Persistence-escalation ceiling.** A SUSTAINED `functions_query_degraded` (health-ok but functions permanently wedged) escalates to `inngest_down` after ~45 min (reusing the #6374 age-gate logic against the new issue title) — never soft-masked forever.
3. **Union-widening.** The new soft mode is routed through EVERY watchdog consumer (probe `case`, `ISSUE_CLASS` case before the `*)→down` default, heartbeat `ok` allowlist, auto-close, persistence gate) so it neither falls through to a false `[ci/inngest-down]` P1 nor rots a soft issue open.
4. **Restart poll `lock_contention` non-terminal (ADR-079 #5960).** `restart-inngest-server.yml`'s verify poll treats `reason=lock_contention` for `component=inngest` as non-terminal + does a final STATE re-read at budget expiry before exiting benign; an unconfirmed state fails loud.
5. **Observability.** Journald `SOLEUR_INNGEST_LIVENESS_VERDICT` (mode/health_code/functions/durability) and `SOLEUR_INNGEST_RESTART_LOCK_CONTENTION` (action/component/outcome) markers (Vector Source 4 → Better Stack) self-report both decisions.

**GDPR.** N/A — the watchdog and restart path move no user content (process-liveness + open-issue metadata only). Art. 33/34 not engaged (consistent with the primary incident above).

**References.** ADR-030 #6374 log entry (refined 2026-07-14 #6407); ADR-079 amendment #5960; runbook `## External watchdog: functions-query degraded + restart lock_contention — #6407`.
