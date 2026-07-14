---
title: "fix: Inngest watchdog functions-query false-positive (corroborate before inngest_down) + restart lock_contention benign"
date: 2026-07-14
type: fix
issue: 6407
closes: 6407
branch: feat-one-shot-6407-inngest-redis-durable-fix
brand_survival_threshold: aggregate pattern
lane: cross-domain
status: draft
---

# fix: Durably fix recurring `ci/inngest-down` watchdog false-positives + restart `lock_contention` (#6407)

🐛 **6th recurrence of `[ci/inngest-down]` in ~2 days** (issues 2026-07-12 → 07-14). Each occurrence is a **false-positive P1** followed by a **failed auto-restart**. This closes #6407.

## Overview

The self-hosted Inngest health watchdog (`.github/workflows/scheduled-inngest-health.yml`, `*/15`) filed a P1 `[ci/inngest-down]` and dispatched `restart-inngest-server.yml` **while inngest was UP and processing events**, and the dispatched restart then **failed on a deploy-lock collision**. Two independent defects compound into a self-inflicted false alarm + failed remediation:

**Root cause (verified via observability — supersedes the issue body's stale redis hypothesis; the backend is SQLite + Postgres, NO redis in the live ExecStart):**

1. **Defect A — liveness over-sensitivity (the false positive).** The liveness hook (`/hooks/inngest-liveness` → `inngest-inventory.sh` in `LIVENESS_ONLY` mode) runs a single `/v0/gql functions` curl. On a **transient curl transport failure** it emits `{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}` (`inngest-inventory.sh:337-338`), which trips the fail-loud FATAL guard (`inngest-inventory.sh:398-408`) and prints the `inngest-inventory: FATAL … refusing to emit a false-clean empty functions baseline` sentinel. The webhook wraps that as HTTP 500 + FATAL body; `classify_liveness_mode` maps any `inngest-inventory: FATAL` body → **`inngest_down`** (`scripts/inngest-liveness-classify.sh:42-43`) → restart family. The watchdog already retries the whole probe 3× (8s apart, `scheduled-inngest-health.yml:94-131`), but a transient that persists ~24s still yields `inngest_down` on all 3 attempts. **Crucially, the FATAL exit (line 408) happens BEFORE `derive_durability_state()` (line 418) and before any process-liveness check** — the independent "is the process actually up?" signal that would falsify the down verdict is never consulted. During run 29334263944 the deploy-status payload showed `services.inngest_server="active"`, `restart_count:0`, `sandbox_canary.verdict="pass"`, and Better Stack logs showed inngest live-processing `triage.p0p1_issue` / `oneshot/monitor-close` events throughout — the process was healthy; only the GQL read transiently failed.

2. **Defect B — restart `lock_contention` → hard P1 (the failed remediation).** The dispatched `restart-inngest-server.yml` sends `restart inngest _ latest` to `ci-deploy.sh`, whose FD-200 advisory `flock -n 200` (`ci-deploy.sh:1263`) is non-blocking: a loser writes `final_write_state 1 "lock_contention"` and exits 1. The workflow's "Verify restart completion" poll reads `exit_code≠0, reason=lock_contention` and **latches it as a terminal failure** → `::error::Restart failed` → the run RED-fails (run 29334263944, 2026-07-14 12:53:50 UTC). But a `lock_contention` on a restart means **another deploy/restart is already in the critical section and will bring inngest current** — it is benign, not a failure. The sibling **web-platform-release deploy poll already treats `lock_contention` as non-terminal per ADR-079 amendment #5960**; the restart poll simply never received that same treatment.

**The fix (three coordinated changes, each grounded in an existing decision):**

- **(A)** Corroborate an apparent `inngest_down` against an **independent, co-located process-liveness signal** (`systemctl is-active inngest-server.service`, the same signal `cat-deploy-state.sh` exposes as `services.inngest_server`) **before** emitting the FATAL sentinel. If the process is active, downgrade to a new **soft** mode `functions_query_degraded` — no restart, no `[ci/inngest-down]` P1 — routed to its own soft issue class. Add bounded retry on the functions curl as defense-in-depth. Extends the ADR-030 #6374 liveness decision.
- **(B)** Give the `restart-inngest-server.yml` verify poll the **ADR-079 #5960 non-terminal-`lock_contention`** treatment: keep polling for a fresh `component=inngest` terminal; treat a lock loss as "restart already in progress" (benign), never an immediate `::error` P1.
- **(C)** Both decisions self-report via monitored `SOLEUR_*` journald markers (tags `inngest-inventory` and `ci-deploy` are already in Vector Source 4 → Better Stack), so the next occurrence is diagnosable without SSH.

Host-script changes ship via **immutable redeploy** (`apply-deploy-pipeline-fix.yml` → `/hooks/infra-config` push, `infra-config-apply.sh` FILE_MAP), never in-place SSH (`hr-prod-host-config-change-immutable-redeploy`).

## Research Reconciliation — Diagnosis vs. Codebase

| Claim (issue/diagnosis) | Codebase reality (verified) | Plan response |
|---|---|---|
| Issue body: redis loss / crash-loop | Live ExecStart is SQLite + Postgres (`--postgres-max-open-conns`), NO `--redis-uri`; `restart_count:0`, `oom_killed:false` | Ignore redis hypothesis entirely; no redis re-staging. Trust the parent diagnosis. |
| "watchdog `/v0/gql` returned `__FETCH_FAILED__` on all 3 attempts → inngest_down" | Confirmed: `fetch_functions()` single curl → `__FETCH_FAILED__` envelope (`inngest-inventory.sh:337-338`) → FATAL (`:398-408`) → classifier `inngest_down` (`inngest-liveness-classify.sh:42`). Watchdog 3× retry at `scheduled-inngest-health.yml:94-131`. | Defect A: corroborate before FATAL. |
| "restart failed with reason=lock_contention" | Confirmed: `flock -n 200` loser → `final_write_state 1 "lock_contention"` exit 1 (`ci-deploy.sh:1263-1268`); restart verify latches it (`restart-inngest-server.yml:142-154`). | Defect B: non-terminal treatment (ADR-079 #5960). |
| "host was HEALTHY (`services.inngest_server=active`)" | `cat-deploy-state.sh` derives `services.inngest_server` from `systemctl is-active inngest-server.service`; served via `/hooks/deploy-status`. The SAME `is-active` signal is available co-located inside the liveness hook. | Use `systemctl is-active` as the corroboration signal (new `INVENTORY_INNGEST_ACTIVE` seam, mirrors existing `INVENTORY_REDIS_ACTIVE`). |
| Prior fix #6384 (2026-07-13) "resolved" the false-positive class | #6384 decoupled liveness from the heavy eventsV2 read and added `probe_unavailable` + the age-gate. It did NOT anticipate the cheap functions query ITSELF transiently failing. | #6407 completes #6384: the functions-query fault is the residual false-positive vector. |

## User-Brand Impact

**If this lands broken, the user experiences:** a **real** inngest outage going unactioned — if corroboration is too permissive it could mask a genuine down, silently dropping a user's scheduled action (armed reminder, KB sync, triage); or, if defect B is mis-scoped, a genuine restart failure is swallowed as benign.
**If this leaks, the user's data/workflow is exposed via:** N/A — the watchdog and restart path move no user content; they read inngest process-liveness + open-issue metadata only. (GDPR Art. 33/34 not engaged; consistent with the #6374 postmortem.)
**Brand-survival threshold:** aggregate pattern. (A single false P1 harms no user directly; the aggregate harm is restart churn + operator-attention drain + a blind window that would equally hide a real outage. No per-user data exposure → no CPO sign-off gate.)

The specificity/sensitivity balance is the load-bearing risk: the corroboration must **preserve real-down detection** (a stopped `inngest-server.service` still returns `is-active != active` → real `inngest_down` → restart fires). See Risks.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

- [ ] Confirm the live cutover topology: which host serves `/hooks/inngest-liveness` and whether `inngest-server.service` is co-located there (post-#6178 dedicated-host vs web-host). The corroboration `systemctl is-active` MUST run on the same host as the functions query — it does (both are inside `inngest-inventory.sh` on the liveness host). Verify via the runbook `knowledge-base/engineering/operations/runbooks/inngest-server.md` §Dedicated-host cutover + a read-only `/hooks/deploy-status` GET showing `services.inngest_server`.
- [ ] Re-read `scripts/inngest-liveness-classify.sh` + `.test.sh` (mode vocabulary + `is_restart_family`) and `apps/web-platform/infra/inngest-inventory.sh:383-424` (the `run_inventory` FATAL guard + `LIVENESS_ONLY` block).
- [ ] Confirm `INVENTORY_INNGEST_ACTIVE` is not already a seam (`grep -n INVENTORY_INNGEST_ACTIVE apps/web-platform/infra/inngest-inventory.sh` → expect zero; mirror `INVENTORY_REDIS_ACTIVE` at `:370`).
- [ ] Confirm ci-deploy.sh delivery path is `apply-deploy-pipeline-fix.yml` paths (`:66`) + `infra-config-apply.sh` FILE_MAP `CI_DEPLOY_SH_B64` (`:34`) — host scripts land via `/hooks/infra-config`, no SSH.

### Phase 1 — Defect A: co-located corroboration before `inngest_down` (host)

**File: `apps/web-platform/infra/inngest-inventory.sh`**

- [ ] In `fetch_functions()` (`:326-339`): add **bounded retry** on the `/v0/gql functions` curl — retry up to `FUNCTIONS_FETCH_RETRIES` (default 2 extra, ~1-2s backoff) before falling back to the `__FETCH_FAILED__` envelope. Respect the ADR-106 wall-clock deadline (`PREFLIGHT_DEADLINE_S`); the retry budget must stay well inside it. Defense-in-depth: lowers the transient rate before it can ever become a FATAL body.
- [ ] In `run_inventory()` at the FATAL guard (`:398-408`), and ONLY when `LIVENESS_ONLY` is set: **before** emitting the `inngest-inventory: FATAL` sentinel + `exit 1`, corroborate process liveness:
  - `inngest_active="${INVENTORY_INNGEST_ACTIVE-$(systemctl is-active inngest-server.service 2>/dev/null || echo inactive)}"` (new seam, mirrors `derive_durability_state`'s `INVENTORY_REDIS_ACTIVE` at `:370`).
  - If `inngest_active == "active"` (process UP, GQL read transiently failing — the #6407 case): emit a **distinct soft sentinel** on stdout, e.g. `inngest-inventory: DEGRADED /v0/gql functions query transiently unreachable but inngest-server.service is active (errors=$fn_errs) — soft, no restart` and `exit 1` (still non-zero so the webhook surfaces the body, but the classifier maps it to a soft mode, NOT restart). Emit the `SOLEUR_INNGEST_LIVENESS_VERDICT` marker (Phase 3).
  - Else (`inngest_active != "active"` → genuine down): keep the existing `inngest-inventory: FATAL …` sentinel + `exit 1` (real `inngest_down` → restart preserved).
  - **Do NOT** rely on `derive_durability_state()` / ExecStart-readability as the liveness signal — `systemctl show -p ExecStart` returns the configured ExecStart even for a STOPPED unit (config, not runtime). Only `is-active`/`/health` proves the process is running. (Sharp Edge.)
- [ ] Keep the sentinel strings stable and grep-safe (no punctuation boundary issues — the classifier substring-matches `inngest-inventory: FATAL` and will substring-match a new `inngest-inventory: DEGRADED`).

**File: `apps/web-platform/infra/inngest-inventory.test.sh`**

- [ ] Add tests driving the new soft-path via `INVENTORY_INNGEST_ACTIVE=active` + a `FUNCTIONS_FIXTURE` that yields the `__FETCH_FAILED__`/non-array envelope → assert the DEGRADED sentinel is emitted (not FATAL) and exit is non-zero.
- [ ] Add a test with `INVENTORY_INNGEST_ACTIVE=inactive` + the same failed-fetch fixture → assert the FATAL sentinel is still emitted (real-down path preserved).
- [ ] Add a fetch-retry test if a seam permits (e.g. `FUNCTIONS_FETCH_RETRIES=0` reproduces the immediate-fail; a mocked transient-then-success is optional).

### Phase 2 — Defect A: classifier + watchdog soft-mode routing

**File: `scripts/inngest-liveness-classify.sh`** (contract-changing — edit BEFORE the workflow consumer)

- [ ] In `classify_liveness_mode`: before the `inngest-inventory: FATAL` → `inngest_down` branch (`:42-43`), add a branch matching the new `inngest-inventory: DEGRADED` sentinel → echo a new mode **`functions_query_degraded`**. (Order matters: DEGRADED and FATAL are distinct literals; match DEGRADED first.)
- [ ] Leave `is_restart_family` (`:51-53`) unchanged so `functions_query_degraded` is **excluded** from the restart family (only `inngest_down`/`inngest_unhealthy` restart). Add a comment documenting the new soft mode alongside the existing mode list (`:16-24`).

**File: `scripts/inngest-liveness-classify.test.sh`**

- [ ] Add assertions: `500 + inngest-inventory: DEGRADED … → functions_query_degraded`; `is_restart_family functions_query_degraded → no`. Keep the existing FATAL→inngest_down assertions intact (regression guard that a real down still restarts).

**File: `.github/workflows/scheduled-inngest-health.yml`**

- [ ] In the probe `case "$MODE"` block (`:115-129`), add a `functions_query_degraded)` arm: `last_mode="functions_query_degraded"; last_detail="attempt N/3: /v0/gql functions transiently unreachable but inngest-server active — soft, no restart"`. It is naturally excluded from the dispatch `if:` (`:327`, keys on `inngest_down`/`inngest_unhealthy`) and the age-gate `if:` (`:304`), so **no restart is dispatched and the age gate is not seeded**.
- [ ] In the file-issue step's `ISSUE_CLASS` routing (`:355-363`), route `functions_query_degraded` to its **own soft class** (distinct from `[ci/inngest-down]`, alongside `probe_unavailable|secret_unset → liveness-probe`) with an **evidence-based, non-claim comment** (per learning `2026-07-13-watchdog-excluded-mode-shares-issue-class-untruthful-comment.md`: assert what happened — "functions query transiently failed; inngest-server confirmed active; NO restart dispatched" — never claim a restart it didn't do). Title distinct so the Defect-3 age gate is never polluted.
- [ ] The Sentry heartbeat step: `functions_query_degraded` should check in `ok` (like `probe_unavailable`), NOT `error` — it is not a genuine down and must not page. Verify the heartbeat step (`~:585-600`) branch covers the new mode.

### Phase 3 — Defect C: observability markers

**File: `apps/web-platform/infra/inngest-inventory.sh`**

- [ ] Emit `SOLEUR_INNGEST_LIVENESS_VERDICT` via `logger -t "$LOG_TAG"` (tag `inngest-inventory` — in Vector Source 4 allowlist, `vector.toml:136`) at the functions-query decision point, with **discriminating structured fields** (per Phase 2.9.2 blind-surface rule): `mode=<degraded|down|healthy> inngest_active=<active|inactive> functions=<n> durability=<enum> fetch_retries=<n>`. One event must let the next occurrence be classified without SSH. Follow the ADR-106 marker convention (enum/count fields only, scrubbed of DSNs/creds via `_pf_scrub`; journald-only to preserve the pure-JSON webhook body per the #5503 purity contract).

**File: `apps/web-platform/infra/ci-deploy.sh`**

- [ ] At the flock-contention path (`:1263-1268`), add `logger -t "$LOG_TAG" "SOLEUR_INNGEST_RESTART_LOCK_CONTENTION action=$ACTION component=$COMPONENT outcome=deferred_to_in_flight"` (tag `ci-deploy` — in Vector Source 4, `vector.toml:132`). **Observability only — do NOT change the `final_write_state 1 "lock_contention"` stamp** (keep it consistent with the deploy path per ADR-079 #5960; the CONSUMER handles it, Phase 4). `ACTION`/`COMPONENT` are parsed at `:1175`, before the flock, so they are populated at contention time.

### Phase 4 — Defect B: restart poll treats `lock_contention` as non-terminal (ADR-079 #5960)

**File: `.github/workflows/restart-inngest-server.yml`**

- [ ] In the "Verify restart completion" poll (`:91-159`), in the `*)` (non-zero exit) case for `component=inngest` (`:143-153`): when `REASON == "lock_contention"`, do **NOT** `::error::Restart failed` + `exit 1`. Instead treat it as **non-terminal**: `echo "Attempt i/N: lock_contention — another inngest deploy/restart holds the lock; it will bring inngest current. Continuing to poll."` and `continue` the loop (mirror the web-platform-release deploy poll's ADR-079 #5960 treatment: keep polling for a fresh `component=inngest && start_ts>=FRESH_FLOOR` terminal success).
- [ ] At poll-budget expiry (`:158-159`): if the ONLY terminal reason seen was `lock_contention` (an in-flight op still running at budget end), emit a **benign** `::notice::restart superseded by an in-flight inngest deploy/restart (lock_contention throughout budget) — treating as already-in-progress, not a failure` and `exit 0` + a `SOLEUR_*` marker line in the Actions log. A genuine, non-contended failure (any other non-zero reason) still `exit 1`. (Deepen-plan: pin the exact terminal-vs-benign decision table; track whether any non-`lock_contention` failure was seen.)
- [ ] Preserve ADR-100 restart-purity: this is a CONSUMER-side (verify-poll) change only; the `ci-deploy.sh` `restart` handler is untouched.

### Phase 5 — ADR amendment + runbook + postmortem

- [ ] **Amend `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`** #6374 amendment log: add the #6407 decision — "the cheap `/v0/gql functions` liveness query can ITSELF transiently fail; the liveness verdict must corroborate an apparent down against `systemctl is-active inngest-server.service` before declaring `inngest_down` (new soft mode `functions_query_degraded`, no restart)." Note the cross-reference to ADR-079 #5960 for the restart-poll `lock_contention` non-terminal treatment. **No new ADR ordinal** (this refines the existing #6374 decision). **No C4 change** (see below).
- [ ] **Update `knowledge-base/engineering/operations/runbooks/inngest-server.md`**: document the new `functions_query_degraded` soft mode (what it means, that NO restart fires, how to query the `SOLEUR_INNGEST_LIVENESS_VERDICT` marker in Better Stack) and the restart `lock_contention`-benign behavior — all no-SSH (`hr-no-ssh-fallback-in-runbooks`).
- [ ] **Write `knowledge-base/engineering/operations/post-mortems/inngest-watchdog-functions-query-false-positive-6407-postmortem.md`** (recurrence #6 warrants a PIR): timeline, the functions-query transient → false `inngest_down` → restart `lock_contention` chain, and the corroboration + non-terminal-lock fixes. Mirror the #6374 postmortem frontmatter (art_33/34 not engaged; brand_survival_threshold: aggregate pattern).

## Sibling-Defect Note (scope decision)

`apps/web-platform/infra/inngest-registry-probe.sh` shares the identical `__FETCH_FAILED__` + FATAL-sentinel pattern (`:87`, `:103-115`). **Acknowledge, do not fix in this PR:** it targets the REMOTE dedicated host for cutover pre-flight, is NOT on the liveness/restart-dispatch path, and its transient failure cannot cause a false `[ci/inngest-down]` P1 restart. Per `hr-write-boundary-sentinel-sweep-all-write-sites` this sibling is enumerated and consciously scoped out (different consumer, no restart blast radius). If a future change routes registry-probe into a restart dispatcher, revisit.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `scripts/inngest-liveness-classify.test.sh` passes, including new assertions: `inngest-inventory: DEGRADED` body → `functions_query_degraded`; `is_restart_family functions_query_degraded` → no; existing `inngest-inventory: FATAL` → `inngest_down` (real-down regression) still passes. Run: `bash scripts/inngest-liveness-classify.test.sh`.
- [ ] AC2 — `apps/web-platform/infra/inngest-inventory.test.sh` passes: `INVENTORY_INNGEST_ACTIVE=active` + failed-fetch fixture → DEGRADED sentinel (not FATAL); `INVENTORY_INNGEST_ACTIVE=inactive` + same fixture → FATAL sentinel (real-down preserved). Run: `bash apps/web-platform/infra/inngest-inventory.test.sh`.
- [ ] AC3 — `grep -c 'functions_query_degraded' scripts/inngest-liveness-classify.sh .github/workflows/scheduled-inngest-health.yml` returns ≥1 in each: classifier emits it, workflow routes it (soft class, excluded from dispatch + age-gate `if:`).
- [ ] AC4 — `grep -n 'SOLEUR_INNGEST_LIVENESS_VERDICT' apps/web-platform/infra/inngest-inventory.sh` and `grep -n 'SOLEUR_INNGEST_RESTART_LOCK_CONTENTION' apps/web-platform/infra/ci-deploy.sh` each return ≥1; both tags (`inngest-inventory`, `ci-deploy`) confirmed present in `apps/web-platform/infra/vector.toml` Source 4 allowlist.
- [ ] AC5 — `restart-inngest-server.yml` verify poll: the `component=inngest` non-zero branch no longer emits `::error::Restart failed` for `reason=lock_contention` (`grep -A3 'lock_contention' .github/workflows/restart-inngest-server.yml` shows a `continue`/benign-notice path, not an immediate `exit 1`).
- [ ] AC6 — Any drift-guard tests for `inngest-inventory.sh` / `ci-deploy.sh` still pass (`inngest-inventory.test.sh`, `ci-deploy.test.sh`) — no durability-parser drift regression.
- [ ] AC7 — `shellcheck` clean on all edited `.sh` files; `actionlint` clean on both edited workflows.
- [ ] AC8 — PR body uses `Closes #6407`. ADR-030 amendment, runbook update, and #6407 postmortem present.

### Post-merge (auto, no operator step)
- [ ] AC9 — Merge to `main` auto-delivers `inngest-inventory.sh` + `ci-deploy.sh` to the host via `apply-deploy-pipeline-fix.yml` (`/hooks/infra-config` push); the workflows + classifier take effect on merge (GHA-consumed). No SSH, no manual apply. Verify via `/hooks/infra-config-status` FILE_MAP count in the workflow's post-apply verify step.
- [ ] AC10 — No `[ci/inngest-down]` P1 recurrence attributable to a transient functions-query failure across the next soak window (see Follow-Through).

## Observability

```yaml
liveness_signal:
  what: "Inngest process-liveness via /hooks/inngest-liveness (functions query + systemctl is-active corroboration); independent executor beacon scheduled-inngest-cron-watchdog (Sentry cron)."
  cadence: "*/15 (scheduled-inngest-health.yml); executor beacon per its cron cadence."
  alert_target: "Sentry Cron monitor scheduled_inngest_health (paging) + GitHub issue (soft classes: liveness-probe / functions_query_degraded)."
  configured_in: ".github/workflows/scheduled-inngest-health.yml; apply-sentry-infra.yml monitor; scripts/inngest-liveness-classify.sh."
error_reporting:
  destination: "journald (logger -t inngest-inventory | ci-deploy) → Vector Source 4 → Better Stack Logs source 2457081; Sentry Cron heartbeat."
  fail_loud: "Genuine down (systemctl is-active != active + functions-query fail) still emits FATAL → inngest_down → restart. Corroboration NEVER suppresses a real down."
failure_modes:
  - mode: "functions-query transient failure, process UP (the #6407 false positive)"
    detection: "SOLEUR_INNGEST_LIVENESS_VERDICT mode=degraded inngest_active=active fetch_retries=N (in-surface, from the liveness host, in Better Stack)"
    alert_route: "soft GitHub issue (functions_query_degraded class), NO restart, NO page"
  - mode: "genuine inngest down (process not active)"
    detection: "SOLEUR_INNGEST_LIVENESS_VERDICT mode=down inngest_active=inactive → classifier inngest_down"
    alert_route: "restart-inngest-server.yml dispatch (age-gated) + Sentry page"
  - mode: "restart lock_contention (deploy/restart already in progress)"
    detection: "SOLEUR_INNGEST_RESTART_LOCK_CONTENTION action=restart component=inngest (Better Stack, ci-deploy tag)"
    alert_route: "restart poll treats as non-terminal/benign; no P1; deferred to in-flight op"
logs:
  where: "Better Stack Logs source 2457081 (Vector Source 4 host_scripts_journald, tags inngest-inventory + ci-deploy); GitHub Actions run logs."
  retention: "Better Stack account retention (see betterstack-quota learning); journald on-host ring buffer."
discoverability_test:
  command: "Query Better Stack Logs for `SOLEUR_INNGEST_LIVENESS_VERDICT` and `SOLEUR_INNGEST_RESTART_LOCK_CONTENTION` (ClickHouse-SQL, no ssh); or GET https://deploy.soleur.ai/hooks/deploy-status (HMAC+CF-Access) for services.inngest_server."
  expected_output: "A degraded/down verdict event with mode + inngest_active + fetch_retries fields; a lock_contention marker with action/component; NO ssh required."
```

## Infrastructure (IaC)

No new Terraform resource, secret, vendor, or persistent process is introduced — this edits **existing** host scripts and CI workflows.

### Apply path
- **Host scripts** (`inngest-inventory.sh`, `ci-deploy.sh`): delivered by the existing **immutable-redeploy** mechanism — `apply-deploy-pipeline-fix.yml` fires on merge to `main` touching those paths (`:66`, `:89`) and pushes the base64 payload via `/hooks/infra-config` → `infra-config-apply.sh` FILE_MAP (`CI_DEPLOY_SH_B64`, `INNGEST_INVENTORY_SH_B64`). **No in-place SSH mutation** (`hr-prod-host-config-change-immutable-redeploy`). Post-apply verify: `/hooks/infra-config-status` FILE_MAP count parity (already in the workflow).
- **CI-consumed** (`scripts/inngest-liveness-classify.sh` + `.test.sh`, `scheduled-inngest-health.yml`, `restart-inngest-server.yml`): checked out at workflow runtime; effective on merge. No host delivery needed.
- **Blast radius / downtime:** none. Behavior change is guard-only (adds a corroboration branch + a non-terminal poll case + markers). Existing green paths (`healthy`, real `inngest_down`, `probe_unavailable`) unchanged.

### Distinctness / drift safeguards
- `dev != prd`: N/A (single prod inngest host; no dev inngest watchdog).
- Drift guards: `inngest-inventory.test.sh` durability-parser drift guard + `ci-deploy.test.sh` poll-window drift guard must stay green (AC6).

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-030** (`ADR-030-inngest-as-durable-trigger-layer.md`) — extend the 2026-07-13 #6374 amendment log with the #6407 decision: corroborate an apparent `inngest_down` against `systemctl is-active inngest-server.service` before declaring down; introduce the soft `functions_query_degraded` mode (no restart). Cross-reference **ADR-079 amendment #5960** (already-decided "treat `lock_contention` as non-terminal" for deploy polls) as the precedent applied to the restart verify poll. **No new ADR ordinal** — this refines an existing decision, avoiding the ordinal-collision footgun.

### C4 views
- **No C4 impact.** Enumerated against all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`):
  - **External human actors:** none new — the watchdog is internal GHA; no correspondent/reviewer/recipient added.
  - **External systems/vendors:** none new — Better Stack log sink is already modeled (`inngest -> betterstack` edge, `model.c4:376`); no new sub-processor.
  - **Containers / data stores:** `inngest` (`:184`), `inngestPostgres` (`:188`), `inngestRedis` (`:192`) all already modeled; none added or changed. (No redis change despite the issue title.)
  - **Access / ownership relationships:** none change — no tenancy or owner-sharing boundary moves.
  - The deploy webhook (`deploy.soleur.ai` / `/hooks/*`) is subsumed under the modeled Cloudflare-tunnel ingress (`tunnel`, `model.c4:176`); the watchdog and `restart-inngest-server.yml` are instances of already-modeled element types per the ADR-030/105/106 precedent ("watchdog changes = No C4 impact"). No element description is falsified by this change.

## Domain Review

**Domains relevant:** none — infrastructure / observability / CI-reliability change. No product/UI surface (no files under `components/**`, `app/**/page.tsx`, or the UI-surface glob). No marketing/sales/finance/legal/support implications. Engineering-only.

## Risks & Mitigations

- **R1 — corroboration masks a real down.** A stopped `inngest-server.service` returns `is-active != active`, so the FATAL/`inngest_down` path is preserved. Mitigation: AC2 explicitly asserts the `inactive` fixture still emits FATAL. The corroboration ONLY downgrades when the process is provably active. Do NOT use ExecStart-readability (a stopped-but-configured unit reads a valid ExecStart) — use `is-active`/`/health` only (Sharp Edge).
- **R2 — cross-host corroboration invalidity (cutover topology).** The corroboration `is-active` must run on the same host as the functions query. It does (both inside `inngest-inventory.sh` on the liveness host). Phase 0 verifies the cutover topology so the liveness host actually runs inngest-server.
- **R3 — deploy-race window (old ci-deploy on host, new workflow on merge).** The `restart-inngest-server.yml` non-terminal-lock treatment is tolerant of an old on-host `ci-deploy.sh` still stamping `lock_contention` exit 1 — the CONSUMER change makes it benign regardless of the host script version. Belt-and-suspenders with the host-side marker.
- **R4 — fetch retry inflating the liveness deadline.** Bounded retries must stay inside `PREFLIGHT_DEADLINE_S` (ADR-106). Keep retries small (≤2 extra, short backoff); AC7 shellcheck + the existing preflight-deadline guard.
- **R5 — untruthful soft-issue comment.** Per learning `2026-07-13-watchdog-excluded-mode-shares-issue-class-untruthful-comment.md`, the `functions_query_degraded` issue comment must assert evidence ("inngest-server confirmed active; NO restart dispatched"), never claim a restart. Enforced in Phase 2.

## Follow-Through Enrollment (soak)

AC10 is a post-deploy soak: "no `[ci/inngest-down]` P1 attributable to a transient functions-query failure for 7 days post-deploy."
- **Script:** `scripts/followthroughs/inngest-watchdog-functions-query-6407.sh` — exit 0 when no new `[ci/inngest-down]` issue with a functions-query/`__FETCH_FAILED__` root cause was filed since deploy (query GitHub issues + Better Stack `SOLEUR_INNGEST_LIVENESS_VERDICT mode=down` events; `start=` pinned strictly after deploy).
- **Tracker directive:** `<!-- soleur:followthrough script=inngest-watchdog-functions-query-6407.sh earliest=<deploy+7d> secrets=BETTERSTACK_QUERY_TOKEN,GH_TOKEN -->` + `follow-through` label on #6407 (or a fresh tracker).
- **Sweeper secrets:** wire any new `secrets=` into `.github/workflows/scheduled-followthrough-sweeper.yml`.

## Sharp Edges

- Corroboration MUST use `systemctl is-active` / loopback `/health`, NOT `derive_durability_state()` — ExecStart is readable for a STOPPED unit, so durability_state would false-corroborate "up" on a genuine down.
- The classifier substring-matches sentinels; `inngest-inventory: DEGRADED` and `inngest-inventory: FATAL` are distinct literals — match DEGRADED first, keep both grep-safe (no punctuation between the matched words).
- A plan whose `## User-Brand Impact` section is empty/TBD fails `deepen-plan` Phase 4.6 — this one is filled (threshold: aggregate pattern).
- Do NOT change `ci-deploy.sh`'s `lock_contention` STAMP (keep exit-1 lock_contention, consistent with the deploy path per ADR-079 #5960); fix the CONSUMER (restart verify poll). Changing the stamp would diverge from the deploy path and the decided model.
- The soft-issue comment must be evidence-based (assert, don't claim a restart) per the 2026-07-13 watchdog learning.
