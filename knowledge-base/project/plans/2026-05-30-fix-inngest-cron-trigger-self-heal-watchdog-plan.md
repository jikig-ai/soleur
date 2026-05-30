---
title: "Fix: Inngest cron-trigger desync regression — immediate restoration + durable self-healing watchdog"
date: 2026-05-30
type: fix
classification: ops-remediation + durable-fix
brand_survival_threshold: aggregate pattern
lane: cross-domain
status: planned
related_issues:
  - "#4533 (CLOSED — prior remediation, CI guard only; DO NOT reopen)"
  - "fresh regression issue (created by this plan, Phase 0)"
related_prs:
  - "#4531 (shipped function-registry-count.test.ts CI guard)"
  - "#3940 (PR-F Inngest substrate)"
  - "#4538 (restart-inngest-server.yml workflow)"
related_adrs:
  - "ADR-030 (self-hosted Inngest, loopback-only, reject Inngest Cloud)"
  - "ADR-033 (cron functions invoke claude-code via child-process spawn)"
sentry_incidents:
  - "5032155 (scheduled-gh-pages-cert-state)"
  - "5010688 (scheduled-community-monitor)"
---

# Fix: Inngest cron-trigger desync regression — immediate restoration + durable self-healing

🐛 **Live production regression.** Two Sentry cron monitors are flagged **Regressed** (2026-05-30):

| Monitor | monitor.id | Sentry incident | Last OK check-in | Inngest function |
|---------|-----------|-----------------|------------------|------------------|
| `scheduled-gh-pages-cert-state` | `85cb82dd-1d52-4a43-b71f-6d15249bdd08` | 5032155 | 2026-05-26T06:48:18Z | `cron-gh-pages-cert-state.ts` |
| `scheduled-community-monitor` | `ad956d6c-ff20-4e4d-a61f-3db689d2e96a` | 5010688 | 2026-05-25T11:56:14Z | `cron-community-monitor.ts` |

> The `auth-callback-no-code-burst` line in the Sentry emails is a **red herring** (coincidental alert-routing artifact, per the 2026-05-27 learning). Ignore it.

This is **not** the same as #4533. #4533 (CLOSED COMPLETED 2026-05-27) shipped **only a preventive CI guard** (`function-registry-count.test.ts`) and **deferred** the operational server restart. The guard is a build-time parity check; it cannot detect or repair a *runtime* trigger desync. The failure recurred. **Do NOT reopen #4533** — open a fresh regression issue (Phase 0).

## Enhancement Summary

**Deepened on:** 2026-05-30

### Key Improvements
1. **IaC apply path corrected** — found `.github/workflows/apply-sentry-infra.yml` auto-applies sentry monitors on merge via a `-target=` allowlist; replaced the wrong "manual Doppler-triplet apply" prescription with "add the `-target` line, merge auto-applies" (no operator step). The allowlist edit is now a load-bearing Files-to-Edit item (AC7).
2. **Re-sync asymmetry pinned** — verified the server runs with no `--poll-interval`, so H9a needs a restart (won't self-heal by polling) while H9b needs only a manual-trigger event. The watchdog's two heal paths map to this; the polling change is scoped out as a tracked deferred candidate.
3. **Loopback access + send-retry confirmed** — watchdog reaches `/v1/functions` via `host.docker.internal:8288` from the container (no SSH); manual-trigger sends route through the existing `sendInngestWithRetry`.

### New Considerations Discovered
- The watchdog rides the substrate it monitors (meta-failure surfaced by its own Sentry monitor + restart re-sync).
- Manual-trigger fires the handler once (restores the check-in) but does NOT re-plan the cron — H9b heal is two-stage (immediate trigger + escalate-to-restart if recurring).
- `test-destroy-guard-sentry-scope-guard.sh` (type-only) and `test-destroy-guard-counter-sentry.sh` (jq destroy-counter) are NOT tripped by adding a same-type monitor — verified, no fixture update needed.

## Overview

The work has two parts, both in scope for this PR cycle:

- **(a) IMMEDIATE RESTORATION** — restore service now via the push-button `restart-inngest-server.yml` workflow + manual-trigger events, verify both functions re-register their cron triggers and both Sentry monitors recover an `ok` check-in. Tracked via the fresh issue.
- **(b) DURABLE SELF-HEALING** — add a heartbeat-watchdog Inngest cron that queries the self-hosted server's `/v1/functions` registry, detects dropped (H9a) or de-planned (H9b) cron triggers, and **self-restores without operator intervention**. The CI guard (#4531) is insufficient because the desync is a *runtime* event after deploy churn, and Soleur operators are non-technical and cannot SSH (`hr-never-label-any-step-as-manual-without`, never-defer-operator-actions). **The operational/automation piece is NOT deferred this time.**

### Root cause (already diagnosed, confirmed against code)

Both functions are Inngest crons on the self-hosted Hetzner Inngest server (`inngest-server.service`, SQLite at `/var/lib/inngest/`, loopback `127.0.0.1:8288`). They stopped checking in within ~1 day of each other → **shared-substrate failure**: the Inngest server drops or de-plans cron triggers after deploy churn (`web-platform-release.yml` redeploys the container on every `apps/web-platform/**` merge; each restart triggers an SDK function-sync PUT). Runbook **H9** (`cloud-scheduled-tasks.md:264`) documents two sub-modes:

- **H9a — function deregistered (full desync).** A loopback blip during container restart leaves the sync response empty; the server drops the function from its registry. `/v1/functions` no longer lists it.
- **H9b — cron trigger not re-planned (partial desync).** The function IS registered (`/v1/functions` lists it) but its `cron` trigger was not re-planned in the scheduler (SQLite write-lock contention during a sync burst). Only event-triggered invocations work; the cron never fires.

### Why the existing guards don't cover this

1. **`function-registry-count.test.ts` (#4531)** is a *source-parity* test — route.ts count, cron-file↔route parity, slug↔terraform parity. It runs at CI. It proves the source is internally consistent; it says nothing about the *running server's* scheduler state.
2. **`inngest-heartbeat.timer` → Better Stack** (60s ping) proves only the **server process is alive** (`/health` 200). H9 is precisely "process alive but cron de-planned" — the heartbeat is green throughout the outage.
3. **`restart-inngest-server.yml`'s `verify_inngest_health`** (`ci-deploy.sh:197`) curls `/health`, not `/v1/functions`. After a restart it reports "healthy" even if triggers are still missing — it verifies liveness, not cron-plan integrity. **This is the verification gap the durable fix must close.**
4. **`cron-cloud-task-heartbeat`** monitors GitHub *issue freshness* (a downstream proxy that only changes on anomalies), not Inngest cron-fire health. It would not detect H9.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task description / runbook) | Codebase reality (verified) | Plan response |
|---|---|---|
| Prior issue #4533 closed COMPLETED | `gh issue view 4533` → `state: CLOSED`, no closing PR ref recorded | Do not reopen; open fresh regression issue (Phase 0). |
| `restart-inngest-server.yml` exists, workflow_dispatch-able | Confirmed: `.github/workflows/restart-inngest-server.yml`, `on: workflow_dispatch`. Sends `restart inngest _ latest` to deploy webhook; polls `deploy-status`. | Use as-is for Phase 1 restoration. |
| Functions have a manual-trigger event | Confirmed: **every** `cron-*.ts` registers `[{ cron: "..." }, { event: "cron/<name>.manual-trigger" }]`. 33 cron functions, uniform pattern. | Manual-trigger via `inngest.send("cron/<name>.manual-trigger")` is the H9b recovery lever — no SSH, no restart. |
| Runbook H9 distinguisher queries `/v1/functions` | Confirmed at `cloud-scheduled-tasks.md:289` — `curl -s http://127.0.0.1:8288/v1/functions \| jq '.[] \| select(.slug==...) \| {slug, triggers}'`. Loopback-only (firewall-closed externally per `inngest-bootstrap.sh:14`). | Watchdog runs **inside the web-platform container** (reaches `127.0.0.1:8288` via `host.docker.internal:8288`, per `INNGEST_BASE_URL` at `ci-deploy.sh:425`), so it has loopback access without SSH. |
| Server re-discovers functions via polling | Inngest self-host docs: server uses `--poll-interval` to poll the SDK app URL. **BUT** `inngest-bootstrap.sh:147` ExecStart sets **no `--poll-interval` and no `--sdk-url`** — function (re)sync is bound to **container restart** (SDK PUTs on startup), not continuous polling. | H9a recovery genuinely needs a restart/redeploy (can't rely on polling re-sync). H9b recovery needs only a manual-trigger event. Watchdog must handle both. |
| `restart-inngest-server.yml` verify step checks cron plan | It checks `/health` only (`ci-deploy.sh:197`). | Phase 3 adds a `/v1/functions` trigger-presence assertion to the restart workflow's verify step (closes the liveness-vs-plan gap). |
| `inngest.send` may blip on loopback during restart | `send-with-retry.ts` exists (`sendInngestWithRetry`, 2 retries, transient-error classifier). | Watchdog's manual-trigger sends MUST route through `sendInngestWithRetry`. |
| ADR for cron substrate | `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` + `ADR-030` (self-hosted, loopback). | Watchdog is pure-IO (Octokit + loopback HTTP + inngest.send), ADR-033 I1/I2/I5 apply; no claude spawn, no BYOK. |

## User-Brand Impact

**If this lands broken, the user experiences:** silent loss of operational safety nets — the GitHub Pages TLS cert can expire un-alerted (`scheduled-gh-pages-cert-state` is the only cert-expiry watchdog; a missed fire means a cert lapse could take the docs/marketing site offline with zero warning), and community-platform health goes unmonitored. The failure is invisible until a *downstream* outage surfaces it.

**If this leaks, the user's data/workflow is exposed via:** N/A — no user data flows through these monitors. Both are platform-internal ops crons using an installation-scoped GitHub token; the watchdog reads only the loopback `/v1/functions` registry (function slugs + trigger metadata, no payloads) and fires manual-trigger events with empty `data: {}`.

**Brand-survival threshold:** `aggregate pattern` — no single fire-miss is a brand-survival event, but a *recurring* substrate that silently drops monitors erodes the reliability of every cron Soleur runs (33 functions ride this substrate). The durable fix targets the aggregate failure mode, not one incident.

_threshold: aggregate pattern, reason: ops-internal monitors with no user-data surface; recurring substrate fragility is the risk, not a single incident._

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Fresh regression issue exists.** A new GitHub issue (NOT #4533) tracks this regression, labelled `type/bug` + `priority/p1-high` + `domain/engineering` + `infra-drift`, body references Sentry incidents 5032155 + 5010688 and links runbook H9. PR body uses `Ref #<new>` (NOT `Closes #<new>` — closure is a post-merge step after restoration verified; per the ops-remediation `Closes`-vs-`Ref` Sharp Edge).
- [ ] **AC2 — Watchdog function created.** `apps/web-platform/server/inngest/functions/cron-inngest-cron-watchdog.ts` exists, registered in `app/api/inngest/route.ts` (count 40→41), follows the `_cron-shared` + `postSentryHeartbeat` pattern, has both `{ cron: "..." }` and `{ event: "cron/inngest-cron-watchdog.manual-trigger" }` triggers, and carries the ADR-033 I1/I2/I5 header invariants.
- [ ] **AC3 — Watchdog queries the real registry.** The handler fetches `http://${INNGEST_HOST}/v1/functions` (host derived from `INNGEST_BASE_URL`, fallback `host.docker.internal:8288`) inside `step.run`, parses each function's `slug` + `triggers[]`, and for every cron function in an **expected-cron manifest** computes: (i) MISSING (slug absent → H9a) or (ii) UNPLANNED (slug present but no `cron`-type trigger → H9b).
- [ ] **AC4 — Self-heal action wired.** On H9b (UNPLANNED), the watchdog fires `cron/<name>.manual-trigger` for each affected function via `sendInngestWithRetry`, and records the remediation. On H9a (MISSING), the watchdog initiates the restart path (see AC5) — it does NOT silently no-op.
- [ ] **AC5 — H9a restart without SSH.** H9a recovery is achievable without an operator SSH. Chosen mechanism documented in the plan + implemented: the watchdog POSTs the deploy webhook `restart inngest _ latest` (same HMAC + CF-Access path as `restart-inngest-server.yml`, secrets read from Doppler prd at runtime) **OR** files a `priority/p0-critical` auto-issue that triggers `restart-inngest-server.yml`. (Decision recorded in §Design Decision D1.)
- [ ] **AC6 — Idempotent + non-thrashing.** Watchdog does NOT re-fire a manual-trigger for the same function more than once per watchdog interval, and does NOT restart-loop: a restart is initiated at most once per N consecutive H9a detections, gated by a cooldown record (file under `/var/lib/inngest/` or an open dedup issue). Verified by a unit test simulating two consecutive H9a ticks → exactly one restart attempt.
- [ ] **AC7 — Observability is SSH-free.** Watchdog posts a Sentry heartbeat (`scheduled-inngest-cron-watchdog`, new `cron-monitors.tf` resource) with `ok=false` when any function is MISSING/UNPLANNED. A new `sentry_cron_monitor` resource is added to `apps/web-platform/infra/sentry/cron-monitors.tf` AND its `-target=sentry_cron_monitor.scheduled_inngest_cron_watchdog` line is added to `.github/workflows/apply-sentry-infra.yml`'s apply allowlist (without it the monitor never auto-applies). `reportSilentFallback` mirrors any watchdog-internal failure. No verification step in this PR requires `ssh`.
- [ ] **AC8 — CI guard extended.** `function-registry-count.test.ts` expected count bumped 40→41 (test `(a)`), and the watchdog's own slug is added to `KNOWN_UNMONITORED_SLUGS` **only if** it is genuinely unmonitored — it is NOT (it has a Sentry monitor), so it must map to a real `cron-monitors.tf` resource (test `(c)`). Verify the suite passes: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts`.
- [ ] **AC9 — Restart workflow verify-step gap closed.** `restart-inngest-server.yml` (or `ci-deploy.sh verify_inngest_health`) is extended to assert `/v1/functions` returns ≥1 function **with a cron trigger** after restart — not just `/health` 200. So a future push-button restart proves cron-plan integrity, not just process liveness. (If implemented in `ci-deploy.sh`, add a unit assertion in `ci-deploy.test.sh`.)
- [ ] **AC10 — Watchdog cadence chosen + justified.** Cron cadence for the watchdog is set so detection latency < the tightest monitored cadence's miss window. `scheduled-gh-pages-cert-state` fires daily `0 3 * * *`; `scheduled-community-monitor` daily `0 8 * * *`. Watchdog runs at least every few hours (proposed `0 */4 * * *`) so a desync is caught and healed before the next daily fire is missed. Cadence + rationale recorded in the function header.
- [ ] **AC11 — Tests.** Vitest unit tests for the watchdog parser (H9a/H9b classification from a fixture `/v1/functions` payload), the cooldown/idempotency logic, and the heal-action dispatch (mocked `sendInngestWithRetry`). `cron-no-byok-lease-sweep.test.ts` still passes (watchdog uses no BYOK). All synthesized fixtures (`cq-test-fixtures-synthesized-only`).
- [ ] **AC12 — Type/lint/build green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; project lint clean; route.ts `cq-nextjs-route-files-http-only-exports` preserved (watchdog imported + added to `functions` array only).
- [ ] **AC13 — Runbook updated.** `cloud-scheduled-tasks.md` H9 section gains a "Self-healing (automated)" subsection describing the watchdog, its detection/heal logic, its Sentry monitor, and how to read its state without SSH. The manual SSH fallback is retained but explicitly labelled last-resort (`hr-no-ssh-fallback-in-runbooks` — the watchdog + restart-workflow are the primary paths).
- [ ] **AC14 — Learning captured.** A bug-fix learning at `knowledge-base/project/learnings/bug-fixes/<topic>.md` (date chosen at write time) documents the regression, why the CI-guard-only #4533 remediation was insufficient, and the watchdog design. References both Sentry incidents.

### Post-merge (operator / automated)

- [ ] **AC15 — IMMEDIATE RESTORATION executed.** `gh workflow run restart-inngest-server.yml` dispatched; workflow completes green; then verify (SSH-free, via the watchdog's manual-trigger + Sentry API): fire `inngest.send("cron/gh-pages-cert-state.manual-trigger")` and `cron/community-monitor.manual-trigger` (or dispatch the watchdog's own manual-trigger to do it), then confirm **both** Sentry monitors flip from Regressed/Error to `ok` (query Sentry monitor check-in status via API per `hr-no-dashboard-eyeball-pull-data-yourself`). Detail: this restoration can run pre-merge too (it does not depend on the new code) — the watchdog code is the *durable* fix; restoration is the *immediate* fix. Prefer running restoration first.
- [ ] **AC16 — Both monitors confirmed `ok`.** Sentry API confirms `scheduled-gh-pages-cert-state` (monitor 85cb82dd...) and `scheduled-community-monitor` (monitor ad956d6c...) each have a fresh `ok` check-in dated after the restart. Recorded as a comment on the fresh issue.
- [ ] **AC17 — Watchdog first fire confirmed.** After merge + deploy, the watchdog's first scheduled (or manual-trigger) fire posts an `ok` Sentry heartbeat to `scheduled-inngest-cron-watchdog`, confirming the loopback `/v1/functions` query works in production. Recorded on the fresh issue.
- [ ] **AC18 — Fresh issue closed.** `gh issue close <new>` after AC16 + AC17 confirmed (post-merge, per ops-remediation `Closes`-vs-`Ref` discipline).

## Implementation Phases

> Phase order is dependency-driven: restoration (Phase 1) is independent of new code and runs first; the watchdog contract (Phase 2 manifest + parser) precedes the heal-action (Phase 2 dispatch) precedes registry wiring (Phase 3).

### Phase 0 — Premise lock + fresh issue
- Confirm #4533 stays closed; open the fresh regression issue (AC1).
- Confirm both Sentry monitors are currently Regressed via Sentry API (baseline).

### Phase 1 — IMMEDIATE RESTORATION (no new code; can run before merge)
- `gh workflow run restart-inngest-server.yml`; poll to green.
- After restart, fire the two manual-trigger events (H9b recovery) so each function checks in immediately rather than waiting for the next daily cron:
  - `inngest.send({ name: "cron/gh-pages-cert-state.manual-trigger", data: {} })`
  - `inngest.send({ name: "cron/community-monitor.manual-trigger", data: {} })`
  - (From a context with loopback access — e.g. a one-off `gh workflow run` of a manual-trigger dispatcher, or via the restart workflow's host; document the exact SSH-free path used.)
- Verify both Sentry monitors flip to `ok` via Sentry API (AC15/AC16).

### Phase 2 — Watchdog function (the durable fix)
- New file `cron-inngest-cron-watchdog.ts`:
  - **Expected-cron manifest** — the set of `{ slug, fnId }` that MUST have a live `cron` trigger. Derive at build time from the same source the CI guard reads (cron-file list), OR hard-code the audited set with a CI test asserting manifest↔route parity (mirror `function-registry-count.test.ts` so the manifest can't drift). Prefer derivation to avoid a second hand-maintained list.
  - **Step 1:** fetch `/v1/functions` from loopback host (AC3).
  - **Step 2:** classify each manifest entry → OK / MISSING (H9a) / UNPLANNED (H9b).
  - **Step 3 (heal):** for UNPLANNED → `sendInngestWithRetry(() => inngest.send({ name: "cron/<name>.manual-trigger", data: {} }))`; for MISSING → restart path per D1, gated by cooldown (AC6).
  - **Step 4:** `postSentryHeartbeat({ ok: noDefects, sentryMonitorSlug: "scheduled-inngest-cron-watchdog", ... })`.
  - Registration: `[{ cron: "0 */4 * * *" }, { event: "cron/inngest-cron-watchdog.manual-trigger" }]`, account-scope concurrency limit 1 (mirror siblings).
- Unit tests (AC11): fixture-driven parser, cooldown, dispatch.

### Phase 3 — Registry + infra wiring
- `route.ts`: import + add `cronInngestCronWatchdog` to `functions` array (count → 41).
- `function-registry-count.test.ts`: bump `(a)` to 41 (AC8).
- `cron-monitors.tf`: add `scheduled-inngest-cron-watchdog` Sentry monitor resource (AC7). Follow the existing resource shape; cadence margin sized to the `0 */4 * * *` schedule. (IaC: this is a Sentry monitor TF resource only — no new server/secret/vendor. See §Infrastructure.)
- `restart-inngest-server.yml` / `ci-deploy.sh`: extend verify step to assert `/v1/functions` has ≥1 cron-triggered function (AC9) + `ci-deploy.test.sh` assertion.

### Phase 4 — Docs + learning
- Runbook H9 self-healing subsection (AC13).
- Bug-fix learning (AC14).

## Research Insights (deepen-plan, 2026-05-30)

**Precedent-diff (Phase 4.4) — scheduled-work pattern:** Confirmed Inngest is canonical (ADR-033); 31 `cron-*.ts` functions exist, all dual-trigger `[{cron}, {event: "cron/<name>.manual-trigger"}]`. The watchdog mirrors this verbatim (`cron-cloud-task-heartbeat.ts` is the closest structural sibling — pure-IO, Octokit, `postSentryHeartbeat`, no claude spawn). NOT a GHA cron. No novel pattern.

**Inngest server re-sync mechanism (verified against `inngest-bootstrap.sh:147` + Inngest self-host docs):** `inngest start` ExecStart sets **no `--poll-interval` and no `--sdk-url`** — function discovery is bound to the SDK PUT on container startup, not continuous polling. Consequence (load-bearing): **H9a (function dropped) genuinely requires a restart/redeploy to re-sync; it will NOT self-heal by polling.** H9b (trigger de-planned) is recoverable via a manual-trigger event alone. The watchdog's two heal paths map exactly to this asymmetry. (A future `--poll-interval` change is the Non-Goal that could eliminate the restart dependency — tracked as a deferred candidate.)

**`/v1/functions` loopback access from the container:** `INNGEST_BASE_URL=http://host.docker.internal:8288` (`ci-deploy.sh:425`) — the watchdog, running in the web-platform container, reaches the loopback registry without SSH. Firewall (`firewall.tf`) closes 8288 externally; the bridge gateway path is the only reach, and the container has it.

**`inngest.send` loopback resilience:** `sendInngestWithRetry` (`send-with-retry.ts`) already retries transient loopback failures (2 retries, exp backoff, classifies `ECONNRESET`/`ECONNREFUSED`/`fetch failed`/`TimeoutError`). Watchdog manual-trigger sends MUST route through it (the loopback blips precisely during the restart window the watchdog is reacting to).

**IaC apply mechanism — CORRECTED:** Initial plan prescribed a manual Doppler-triplet `terraform apply`. Deepen-plan found `.github/workflows/apply-sentry-infra.yml` auto-applies `sentry_cron_monitor.*` on merge via a hand-maintained `-target=` allowlist (17 cron entries). The correct mechanism is "add the `-target` line, merge, auto-applies" — no operator step. Both affected monitors (`scheduled_community_monitor`, `scheduled_gh_pages_cert_state`) are already in the allowlist; the watchdog's must be added.

**Cited PR/issue states (verified live):** #4533 CLOSED (prior remediation), #4531 MERGED (CI guard + runbook H9), #3940 MERGED (PR-F substrate), #4538 CLOSED (restart workflow), #4591 MERGED (apply-sentry-infra `-target` extension precedent). All titles match claimed roles.

## Design Decision D1 — H9a restart mechanism (watchdog → restart, no SSH)

Two candidates for how the watchdog initiates a server restart on H9a:

- **D1-A (preferred): watchdog POSTs the deploy webhook directly.** The watchdog signs `{"command":"restart inngest _ latest"}` with `WEBHOOK_DEPLOY_SECRET` + CF-Access headers (all in Doppler prd, already injected into the web-platform container) and POSTs `https://deploy.soleur.ai/hooks/deploy`. This is the exact payload `restart-inngest-server.yml` sends. Fully autonomous, zero operator action. Risk: gives the runtime container restart authority — but it already holds the webhook secret for other paths; scope is `restart inngest` only (the webhook's `ci-deploy.sh` rejects any non-`inngest` restart component at line 256).
- **D1-B (fallback): watchdog files a `priority/p0-critical` auto-issue.** A GH Action on that label dispatches `restart-inngest-server.yml`. One hop more, but keeps restart authority in CI rather than the runtime. Slower (issue→action latency).

**Decision:** Implement **D1-A** with a cooldown (AC6) so a persistent H9a can't restart-loop. D1-B is the documented manual escalation if the webhook POST itself fails. This keeps the operator fully out of the loop (never-defer-operator-actions). Confirm at /work whether the container can reach `deploy.soleur.ai` (egress) — if not, fall back to D1-B. Verify egress reachability as a Phase 2 precondition.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add one `sentry_cron_monitor` resource named `scheduled_inngest_cron_watchdog` (underscore convention per siblings; slug `scheduled-inngest-cron-watchdog`, `schedule = { crontab = "0 */4 * * *" }`, `checkin_margin_minutes` ~120 + `max_runtime_minutes` ~5, sized to the 4-hourly cadence). No new providers, no new secrets, no new server. Mirror an existing one-step monitor resource's shape (e.g. `scheduled_oauth_probe` at `cron-monitors.tf:65`).
- `.github/workflows/apply-sentry-infra.yml` — **add `-target=sentry_cron_monitor.scheduled_inngest_cron_watchdog \` to the apply allowlist** (currently ~17 cron targets, lines ~182+). Without this line the new monitor is never auto-applied. This is the load-bearing IaC edit; do NOT omit it.
- Required provider/version pins: unchanged (`jianyuan/sentry`, already in `.terraform.lock.hcl`). Sensitive vars: none new (`SENTRY_*` already in Doppler `prd_terraform`).
- No new `random_id`, no new vendor account, no new Doppler secret (watchdog reuses `INNGEST_BASE_URL`, `WEBHOOK_DEPLOY_SECRET`, `CF_ACCESS_*`, `SENTRY_*` already in Doppler prd).

### Apply path
- **(a) auto-apply-on-merge — CORRECTED at deepen-plan.** The new Sentry monitor is applied automatically by `.github/workflows/apply-sentry-infra.yml` on merge to main (path-filtered `push` on `apps/web-platform/infra/sentry/**`). That workflow runs the canonical Doppler-triplet `terraform apply` internally, scoped to a hand-maintained `-target=sentry_cron_monitor.*` / `-target=sentry_uptime_monitor.*` allowlist (currently 17 cron entries, lines ~182+). **Therefore the new monitor's `-target=sentry_cron_monitor.scheduled_inngest_cron_watchdog` line MUST be added to that allowlist in this PR — otherwise the resource is silently never applied** (the workflow only applies listed targets; an un-listed resource is a silent no-op). No operator `terraform apply` step is needed (PR merge IS the remediation, per the automation-feasibility gate).
- **Guard suites to sweep** (per the #4591 `-target=` allowlist Sharp Edge): adding a new `sentry_cron_monitor.*` target is the SAME resource TYPE as existing entries, so it does NOT trip `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` (type-only check) NOR `tests/scripts/test-destroy-guard-counter-sentry.sh` (jq-fixture destroy-counter, not a `-target` count). Verified at deepen-plan by reading both. No fixture/count update needed — but re-run both at /work to confirm green.
- Blast radius: one new monitor; zero downtime; applies on merge with no manual step.

### Distinctness / drift safeguards
- The monitor resource is prd-only (Sentry monitors are not dev/prd-split in this repo). No `lifecycle.ignore_changes` needed (additive). State lands in the encrypted R2 backend.

### Vendor-tier reality check
- Sentry Crons monitors are within the existing plan (33 monitors already provisioned). No tier gate.

## Observability

```yaml
liveness_signal:
  what: "scheduled-inngest-cron-watchdog Sentry cron monitor — ok check-in every 4h proves the watchdog ran AND the loopback /v1/functions query succeeded."
  cadence: "0 */4 * * * (every 4 hours UTC)"
  alert_target: "Sentry Crons missed-checkin alert (same routing as the 33 existing monitors)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (new resource) + cron-inngest-cron-watchdog.ts postSentryHeartbeat"
error_reporting:
  destination: "Sentry via reportSilentFallback (watchdog-internal failures: loopback fetch error, send-with-retry exhaustion, webhook POST failure) + ok=false heartbeat when a monitored function is MISSING/UNPLANNED"
  fail_loud: "ok=false heartbeat flips the watchdog's own Sentry monitor to error; reportSilentFallback mirrors internal exceptions. No silent catch."
failure_modes:
  - mode: "monitored cron function dropped from registry (H9a)"
    detection: "slug absent in /v1/functions response"
    alert_route: "watchdog initiates restart (D1-A) + ok=false heartbeat → Sentry"
  - mode: "monitored cron trigger de-planned (H9b)"
    detection: "slug present but no cron-type trigger in /v1/functions"
    alert_route: "watchdog fires cron/<name>.manual-trigger via sendInngestWithRetry + ok=false heartbeat"
  - mode: "watchdog itself cannot reach loopback /v1/functions"
    detection: "fetch throws / non-200 inside step.run"
    alert_route: "reportSilentFallback → Sentry; ok=false heartbeat (watchdog miss is itself a substrate signal)"
  - mode: "restart webhook POST fails (egress blocked / 5xx)"
    detection: "non-202 from deploy.soleur.ai/hooks/deploy"
    alert_route: "reportSilentFallback + fall back to D1-B (file p0 auto-issue)"
logs:
  where: "pino structured logs → journald → Vector → Better Stack Logs (existing shipper, inngest-bootstrap.sh Vector sink)"
  retention: "Better Stack Logs default retention"
discoverability_test:
  command: "curl -s https://<sentry-api>/.../monitors/scheduled-inngest-cron-watchdog/ | jq '.status' — OR query the 33-monitor list; confirm last check-in is ok and recent. (No ssh.)"
  expected_output: "status ok, last check-in within the last 4h+margin"
```

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)
**Status:** reviewed (plan-author assessment; no Task subagent available in this environment — deepen-plan will spawn data-integrity-guardian + architecture-strategist domain agents)
**Assessment:** Pure ops-substrate change. CTO concerns: (1) the watchdog must not itself become a desync victim — it has the same dual-trigger shape, so a full-substrate H9a could drop the watchdog too; mitigated because H9a recovery is restart (which re-syncs ALL functions including the watchdog), and the watchdog's own Sentry monitor catches a watchdog miss. (2) Restart authority in the runtime (D1-A) is a privilege-scope question — bounded by `ci-deploy.sh`'s `restart inngest`-only allowlist. (3) Cooldown is load-bearing to prevent restart-loops (AC6). No product/UX/legal/security-of-user-data surface (no user data, no auth flow, no new external surface).

### Product/UX Gate
Not relevant — no user-facing surface. Tier: NONE.

## Test Scenarios

1. Parser: fixture `/v1/functions` with all 33 crons present+planned → zero defects.
2. Parser: fixture with `cron-gh-pages-cert-state` slug absent → MISSING (H9a).
3. Parser: fixture with `scheduled-community-monitor` present but `triggers` lacking a `cron` entry → UNPLANNED (H9b).
4. Heal: UNPLANNED → exactly one `sendInngestWithRetry` call with `cron/community-monitor.manual-trigger`.
5. Cooldown: two consecutive H9a ticks within cooldown window → exactly one restart attempt (AC6).
6. Heartbeat: any defect → `postSentryHeartbeat({ ok: false })`; clean → `ok: true`.
7. `function-registry-count.test.ts` passes at count 41.
8. `ci-deploy.test.sh` — restart verify asserts ≥1 cron-triggered function.

## Non-Goals / Out of Scope

- Switching the Inngest server to continuous `--poll-interval` polling (would re-sync functions without container restart). **Deferred candidate** — could make H9a self-heal without a restart at all. If deferred, file a tracking issue with re-eval criteria (Phase 4 milestone): "Evaluate `--poll-interval N` on inngest-server.service ExecStart to eliminate restart-dependency for function re-sync." This is a genuine follow-up, not a punt of the in-scope automation (the watchdog covers H9a via restart today).
- Migrating the watchdog off the same substrate it monitors (e.g. a GHA-cron watchdog as belt-and-suspenders). ADR-033 prefers Inngest > GHA cron; a same-substrate watchdog with restart-recovery + its own Sentry monitor is sufficient for `aggregate pattern` threshold. Note as a deferred candidate if deepen-plan's domain agents judge the self-monitoring blind spot material.

## Open Code-Review Overlap

None. Checked all 7 planned file paths against 74 open `code-review` issues (`gh issue list --label code-review --state open`); zero bodies reference any planned file. Check ran 2026-05-30.

## Sharp Edges

- **The watchdog rides the substrate it monitors.** A full-substrate H9a can drop the watchdog itself. Defense: (a) restart re-syncs all functions including the watchdog; (b) the watchdog's own Sentry monitor (`scheduled-inngest-cron-watchdog`) flips to `missed` if the watchdog stops firing, surfacing the meta-failure. Do not assume the watchdog is immune.
- **`/health` ≠ cron-plan health.** Any verification (restart workflow, watchdog, runbook) that checks `/health` proves only process liveness. H9 is precisely "healthy process, no cron plan." Always assert against `/v1/functions` trigger presence, never `/health` alone (AC9).
- **Manual-trigger fires the handler, not the cron plan.** `inngest.send("cron/<name>.manual-trigger")` makes the function RUN once (recovers the missed check-in) but does NOT re-plan the cron schedule. For H9b the de-planned trigger persists until the next container restart re-syncs it. So H9b heal = manual-trigger (restore the immediate check-in) **+** flag for re-sync; if H9b recurs every interval, escalate to restart. Document this two-stage semantic; do not treat a single manual-trigger as a permanent H9b fix.
- **Cooldown state must survive restart.** If the cooldown record lives only in process memory, a restart-loop defeats it (each restart clears memory → infinite loop). Persist the cooldown to `/var/lib/inngest/` (survives container restart; the inngest-server SQLite dir is host-bind-mounted) or to an open dedup GitHub issue.
- **`A plan whose ## User-Brand Impact section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail deepen-plan Phase 4.6.`** This plan's section is filled with threshold `aggregate pattern` + scope-out reason.
- **Sentry monitor API endpoint scope.** When verifying the new monitor (AC17) and existing ones (AC16) via API, the `/organizations/{org}/monitors/` endpoint is Crons-only and is the correct surface here (these ARE cron monitors, not uptime monitors) — unlike the #4591 uptime-monitor case.
- **`Closes` vs `Ref` for ops-remediation.** PR body uses `Ref #<new>`; the issue is closed post-merge after AC16/AC17 (restoration + watchdog first-fire) confirm, NOT at merge.
