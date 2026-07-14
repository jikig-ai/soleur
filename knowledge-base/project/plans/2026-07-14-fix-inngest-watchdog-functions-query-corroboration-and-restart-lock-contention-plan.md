<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix: Inngest watchdog functions-query false-positive (corroborate via /health before inngest_down) + restart lock_contention benign"
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

🐛 **6th recurrence of `[ci/inngest-down]` in ~2 days** (issues 2026-07-12 → 07-14). Each occurrence is a **false-positive P1** followed by a **failed auto-restart**. Closes #6407.

> Note: the `systemctl` references throughout this plan are (a) existing runtime behavior of `ci-deploy.sh`'s restart handler and (b) read-only `/health`/liveness diagnosis signals — NOT manual operator provisioning. All host-script changes ship via the existing immutable-redeploy delivery (`apply-deploy-pipeline-fix.yml` → `/hooks/infra-config`), never in-place SSH (`hr-prod-host-config-change-immutable-redeploy`). See `## Infrastructure (IaC)`.

## Enhancement Summary

**Deepened on:** 2026-07-14 (4 review agents: architecture-strategist, code-simplicity-reviewer, pattern-recognition/state-machine, verify-the-negative realism pass).

### Key improvements from review
1. **Corroboration signal corrected `systemctl is-active` → loopback `/health`** (architecture P1, load-bearing). `is-active` returns `active` for a *wedged-but-alive* server (process up, HTTP unresponsive) — it would BOTH mask a real outage AND suppress the restart that recovers a wedge. Loopback `/health` is the same-signal-class corroborator: a *transient* GQL blip returns `/health` 200 (→ soft); a *wedged/down* server fails `/health` too (→ stays `inngest_down` → restart fires).
2. **Persistence-escalation ceiling added** (architecture P1 + state-machine Q4-secondary). A sustained `functions_query_degraded` (the narrow health-ok-but-functions-permanently-wedged residual) must not be soft-masked forever — it escalates to `inngest_down` (page + restart) after a bounded window, mirroring the existing ~45-min GIVE_UP age-gate.
3. **Union-widening: two fail-*dangerous* consumers are MANDATORY edits, not "verify"** (architecture P1 + state-machine Q2/Q3). The `ISSUE_CLASS *) → down` default (`:363`) and the heartbeat `ok`-allowlist (`:597`) both default a new mode to the HARD path (false P1 / Sentry page). Both are explicit required edits with a `cq-union-widening-grep` sweep AC.
4. **New auto-close branch** (state-machine Q4 dead-end). The new soft issue class has no auto-close today → it would rot open forever. Added a close branch + AC.
5. **Down-branch `else` hardened to no-claim-on-empty** (state-machine Q2) — the 2026-07-13 learning's second defense layer was never landed.
6. **Restart-poll budget-expiry does a FINAL STATE re-read** (architecture P2), mirroring the deploy poll (`apply-deploy-pipeline-fix.yml:719-731`), not a blind `exit 0`.
7. **CUT the host-side `fetch_functions` retry** (simplicity + architecture concur — YAGNI: corroboration already fully kills the false positive; the retry duplicates the existing 3×8s outer loop and stacks timeouts against the ADR-106 deadline).
8. **Postmortem folded into the existing #6374 PIR** as a residual-vector section (simplicity — avoids a near-duplicate file).

### Verify-the-negative pass: all 5 factual claims CONFIRMED
Classifier uses `grep -qF` (FATAL/DEGRADED safely distinct); `INVENTORY_REDIS_ACTIVE` seam exists (`:370`); `ACTION` parsed (`:1175`) before flock (`:1263`); Vector Source 4 allowlist has both `ci-deploy` (`vector.toml:130`) and `inngest-inventory` (`:134`); both scripts in `apply-deploy-pipeline-fix.yml` paths + `infra-config-apply.sh` FILE_MAP.

## Overview

The self-hosted Inngest health watchdog (`.github/workflows/scheduled-inngest-health.yml`, `*/15`) filed a P1 `[ci/inngest-down]` and dispatched `restart-inngest-server.yml` **while inngest was UP and processing events**, and the dispatched restart then **failed on a deploy-lock collision**. Two independent defects compound into a self-inflicted false alarm + failed remediation. (Backend is SQLite + Postgres, NO redis in the live ExecStart — the issue body's redis hypothesis is stale/wrong; trust the observability diagnosis.)

**Defect A — liveness over-sensitivity (the false positive).** The liveness hook (`/hooks/inngest-liveness` → `inngest-inventory.sh` `LIVENESS_ONLY`) runs a single `/v0/gql functions` curl. On a **transient curl transport failure** it emits `{"errors":[{"message":"__FETCH_FAILED__"}],"data":null}` (`inngest-inventory.sh:337-338`), tripping the fail-loud FATAL guard (`:398-408`) → prints `inngest-inventory: FATAL … refusing to emit a false-clean empty functions baseline`. The webhook wraps that as HTTP 500 + FATAL body; `classify_liveness_mode` maps any `inngest-inventory: FATAL` body → **`inngest_down`** (`scripts/inngest-liveness-classify.sh:42-43`) → restart family. The watchdog already retries the whole probe 3× (8s apart, `scheduled-inngest-health.yml:94-131`), but a transient persisting ~24s still yields `inngest_down` on all 3. **The FATAL exit (`:408`) happens BEFORE any process-liveness check** — the independent "is the HTTP server serving?" signal that would falsify the down verdict is never consulted. During run 29334263944 the deploy-status payload showed `services.inngest_server="active"`, `restart_count:0`, `sandbox_canary.verdict="pass"`, and Better Stack showed inngest live-processing events throughout — healthy process, transient GQL read.

**Defect B — restart `lock_contention` → hard P1 (the failed remediation).** The dispatched restart sends `restart inngest _ latest` to `ci-deploy.sh`, whose FD-200 advisory `flock -n 200` (`:1263`) is non-blocking: a loser writes `final_write_state 1 "lock_contention"` exit 1. The restart-verify poll reads `exit_code≠0, reason=lock_contention` and **latches it as terminal failure** → `::error::Restart failed` → RED (run 29334263944, 12:53:50 UTC). But `lock_contention` on a restart means **another deploy/restart already holds the critical section and will bring inngest current** — benign, not a failure. The sibling **web-platform-release deploy poll already treats `lock_contention` as non-terminal per ADR-079 amendment #5960** (`apply-deploy-pipeline-fix.yml:693-698`); the restart poll never got that treatment.

**The fix:**
- **(A)** Before emitting the FATAL sentinel on a functions-query failure, corroborate against the **loopback `/health` endpoint** (same-signal-class process-liveness). `/health`=200 → the HTTP server is serving; the GQL read transiently failed → downgrade to a new **soft** mode `functions_query_degraded` (no restart, no `[ci/inngest-down]` P1, own soft issue class). `/health`≠200 → wedged or down → keep FATAL → `inngest_down` → restart (recovers a wedge). Plus a **persistence-escalation ceiling** so a sustained degraded state still pages. Extends the ADR-030 #6374 liveness decision.
- **(B)** Give `restart-inngest-server.yml`'s verify poll the **ADR-079 #5960 non-terminal-`lock_contention`** treatment (keep polling for a fresh `component=inngest` terminal; final STATE re-read at budget expiry; treat a lock loss as "restart already in progress", never an immediate `::error` P1).
- **(C)** Both decisions self-report via monitored `SOLEUR_*` journald markers (tags `inngest-inventory`, `ci-deploy` already in Vector Source 4 → Better Stack).

## Research Reconciliation — Diagnosis vs. Codebase

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Issue body: redis loss / crash-loop | Live ExecStart is SQLite + Postgres (`--postgres-max-open-conns`), NO `--redis-uri`; `restart_count:0`, `oom_killed:false` | Ignore redis hypothesis; no redis re-staging. |
| "watchdog `/v0/gql` `__FETCH_FAILED__` on all 3 attempts → inngest_down" | `fetch_functions()` single curl → `__FETCH_FAILED__` envelope (`inngest-inventory.sh:337-338`) → FATAL (`:398-408`) → classifier `inngest_down` (`inngest-liveness-classify.sh:42`). Watchdog 3× retry (`scheduled-inngest-health.yml:94-131`). | Defect A: corroborate via `/health` before FATAL. |
| "restart failed reason=lock_contention" | `flock -n 200` loser → `final_write_state 1 "lock_contention"` exit 1 (`ci-deploy.sh:1263-1268`); restart verify latches it (`restart-inngest-server.yml:143-153`). | Defect B: non-terminal + final STATE re-read (ADR-079 #5960). |
| "host was HEALTHY (`services.inngest_server=active`)" | `is-active` proves the *process* runs, NOT that HTTP is serving. A wedged-but-alive server is `active` yet fails `/v0/gql` AND `/health`. Loopback `/health` (used by `ci-deploy.sh verify_inngest_health`, ~`:1019`) is the specificity-correct signal. | Corroborate via loopback `/health` (seam `INVENTORY_INNGEST_HEALTH_CODE`), NOT `is-active`. |
| Prior fix #6384 (2026-07-13) "resolved" the class | #6384 decoupled liveness from the heavy eventsV2 read + added `probe_unavailable` + the age-gate. It did NOT anticipate the cheap functions query ITSELF transiently failing. | #6407 completes #6384: the functions-query fault is the residual false-positive vector. |

## User-Brand Impact

**If this lands broken, the user experiences:** a **real** inngest outage going unactioned — a mis-scoped corroboration could mask a genuine down (wedged/stopped server), silently dropping a user's scheduled action (armed reminder, KB sync, triage); or a genuine restart failure swallowed as benign.
**If this leaks, the user's data/workflow is exposed via:** N/A — the watchdog and restart path move no user content (inngest process-liveness + open-issue metadata only). GDPR Art. 33/34 not engaged (consistent with the #6374 postmortem).
**Brand-survival threshold:** aggregate pattern. (A single false P1 harms no user directly; the aggregate harm is restart churn + operator-attention drain + a blind window that would equally hide a real outage. No per-user data exposure → no CPO sign-off gate.)

The load-bearing risk is specificity: the corroboration MUST preserve real-down/wedged detection. `/health` (not `is-active`) is the signal that distinguishes a transient GQL blip from a wedged server; the persistence ceiling backstops the residual case. See R1/R6.

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)
- [ ] 0.1 Confirm cutover topology: the host serving `/hooks/inngest-liveness` runs `inngest-server.service` and answers `/health` on the loopback (`--host 0.0.0.0 --port 8288`). Both the functions query and `/health` hit the SAME loopback server (co-located inside `inngest-inventory.sh`). Verify via runbook §Dedicated-host cutover + a read-only `/hooks/deploy-status` GET.
- [ ] 0.2 Re-read `scripts/inngest-liveness-classify.sh` + `.test.sh` (mode vocabulary + `is_restart_family`) and `inngest-inventory.sh:383-424` (the FATAL guard + `LIVENESS_ONLY` block); confirm `verify_inngest_health`'s `/health` form in `ci-deploy.sh` (~`:1019`) to reuse the exact endpoint.
- [ ] 0.3 Confirm seam `INVENTORY_INNGEST_HEALTH_CODE` is new (`grep -n INVENTORY_INNGEST_HEALTH inngest-inventory.sh` → zero; mirror the `INVENTORY_REDIS_ACTIVE` seam pattern at `:370`).
- [ ] 0.4 Confirm host-script delivery: `apply-deploy-pipeline-fix.yml` paths (`:66`, `:89`) + `infra-config-apply.sh` FILE_MAP (`CI_DEPLOY_SH_B64:34`, `INNGEST_INVENTORY_SH_B64:45`).

### Phase 1 — Defect A: `/health` corroboration before `inngest_down` (host)

**File: `apps/web-platform/infra/inngest-inventory.sh`**
- [ ] 1.1 In `run_inventory()` at the FATAL guard (`:398-408`), ONLY when `LIVENESS_ONLY` is set: **before** emitting the `inngest-inventory: FATAL` sentinel + `exit 1`, probe loopback `/health`:
  - `health_code="${INVENTORY_INNGEST_HEALTH_CODE-$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8288/health 2>/dev/null || echo 000)}"` (new seam, mirrors `derive_durability_state`'s `INVENTORY_REDIS_ACTIVE` at `:370`). Use the exact `/health` path `ci-deploy.sh verify_inngest_health` uses.
  - If `health_code == 200` (HTTP server serving; GQL read transiently failed — the #6407 case): emit a **distinct soft sentinel** `inngest-inventory: DEGRADED /v0/gql functions query transiently unreachable but /health=200 (errors=$fn_errs) — soft, no restart` + `exit 1` (non-zero so the webhook surfaces the body; the classifier maps it to a soft mode). Emit `SOLEUR_INNGEST_LIVENESS_VERDICT` (Phase 3).
  - Else (`health_code != 200` → wedged/down): keep the existing `inngest-inventory: FATAL …` sentinel + `exit 1` (real `inngest_down` → restart preserved; a restart recovers a wedge).
  - **Rationale (do NOT substitute `systemctl is-active` or `derive_durability_state`/ExecStart):** `is-active` returns `active` for a wedged-but-alive server and `systemctl show -p ExecStart` is readable for a STOPPED unit — neither proves HTTP is serving. `/health` is the only specificity-correct corroborator (same loopback server as the failing GQL query). (Sharp Edge.)
  - Keep sentinel literals grep-safe: the classifier substring-matches `inngest-inventory: FATAL` / `inngest-inventory: DEGRADED` (distinct prefixes, no shared-boundary collision — verified `grep -qF`).

**File: `apps/web-platform/infra/inngest-inventory.test.sh`**
- [ ] 1.2 `INVENTORY_INNGEST_HEALTH_CODE=200` + a functions-fixture yielding the `__FETCH_FAILED__`/non-array envelope → assert DEGRADED sentinel (not FATAL), exit non-zero.
- [ ] 1.3 `INVENTORY_INNGEST_HEALTH_CODE=000` (and `503`) + same fixture → assert FATAL sentinel (real-down/wedged path preserved).

### Phase 2 — Defect A: classifier + watchdog soft-mode routing (union-widening — all consumers MANDATORY)

**File: `scripts/inngest-liveness-classify.sh`** (contract edit — BEFORE the workflow consumer)
- [ ] 2.1 In `classify_liveness_mode`: add a branch matching `inngest-inventory: DEGRADED` → new mode **`functions_query_degraded`**, placed BEFORE the `inngest-inventory: FATAL` → `inngest_down` branch (`:42-43`). Leave `is_restart_family` (`:51-53`) unchanged → the new mode is excluded from the restart family. Document the mode in the header list (`:16-24`).

**File: `scripts/inngest-liveness-classify.test.sh`**
- [ ] 2.2 Assert `… DEGRADED … → functions_query_degraded`; `is_restart_family functions_query_degraded → no`; keep the FATAL→inngest_down regression assertions (a real down still restarts).

**File: `.github/workflows/scheduled-inngest-health.yml`** — FOUR consumer edits (two allowlists default DANGEROUSLY):
- [ ] 2.3 Probe `case "$MODE"` (`:115-129`): add `functions_query_degraded)` arm setting `last_mode="functions_query_degraded"` + evidence-based detail. (Auto-excluded from the dispatch `if:` `:327` and age-gate `if:` `:304`, which key on `inngest_down`/`inngest_unhealthy` — verified by state-machine review Q1.)
- [ ] 2.4 **MANDATORY** — `ISSUE_CLASS` `case "$FAIL_MODE"` (`:359-364`): add an explicit `functions_query_degraded)` arm BEFORE the `*) ISSUE_CLASS="down"` default, routing to its **own** soft class (e.g. `functions-degraded`, title `[ci/inngest-functions-degraded]`) with its **own accurate** body: "`/v0/gql functions` transiently unreachable; **/health=200 (inngest-server serving)**; NO restart dispatched." Do NOT reuse the `liveness-probe` class — its "probe path unavailable / deploy-race / CF-Access" body is inaccurate for this mode. Omitting this arm → falls through to `down` → false `[ci/inngest-down]` P1 (the exact regression this PR closes).
- [ ] 2.5 **MANDATORY** — Sentry heartbeat `status:` (`:597`): add `|| steps.poolprobe.outputs.failure_mode == 'functions_query_degraded'` to the `ok` allowlist (currently only `'' || probe_unavailable`). Without it the soft mode evaluates to `error` → Sentry monitor-failure **page** every `*/15`.
- [ ] 2.6 **Auto-close (Q4 dead-end fix)** — add a close block in the "Auto-close tracking issue (healthy)" step (`:481-515`) mirroring the `[ci/inngest-probe-unavailable]` close (`:511-515`) but searching the new `[ci/inngest-functions-degraded]` title, so the soft issue auto-closes on recovery instead of rotting open.
- [ ] 2.7 **No-claim `else` hardening (defense-in-depth)** — the down-branch `else` (`:472-474`) unconditionally says "Restart re-dispatched"; harden to no-claim-on-empty per `2026-07-13-watchdog-excluded-mode-shares-issue-class-untruthful-comment.md` (assert-on-`true`, escalate-on-`false`, never claim on empty `RESTART_OK`) so the next excluded mode can't emit an untruthful restart claim.
- [ ] 2.8 **Persistence-escalation ceiling (R6)** — a sustained `functions_query_degraded` (health-ok but functions permanently wedged) must not soft-mask forever. Gate on the `[ci/inngest-functions-degraded]` issue age (reuse `scripts/inngest-restart-age-gate.sh` timestamp logic against the new title): once age ≥ a bounded window (~45 min ≈ 3 `*/15` cycles, matching the existing GIVE_UP_WINDOW at `:298`), the workflow reclassifies the cycle's verdict to `inngest_down` (dispatch restart + heartbeat `error` → page). First occurrence = soft; sustained = escalates. Bounds the mask to ~45 min.

### Phase 3 — Defect C: observability markers
- [ ] 3.1 `inngest-inventory.sh`: `logger -t "$LOG_TAG" "SOLEUR_INNGEST_LIVENESS_VERDICT mode=<degraded|down> health_code=<NNN> functions=<n> durability=<enum>"` at the functions-query decision (tag `inngest-inventory` → Vector Source 4, `vector.toml:134`). Discriminating fields per Phase 2.9.2 blind-surface rule; enum/count only, scrubbed via `_pf_scrub`; journald-only (preserve the pure-JSON webhook body, #5503 purity).
- [ ] 3.2 `ci-deploy.sh`: `logger -t "$LOG_TAG" "SOLEUR_INNGEST_RESTART_LOCK_CONTENTION action=$ACTION component=$COMPONENT outcome=deferred_to_in_flight"` at the flock-contention path (`:1263-1268`; tag `ci-deploy` → `vector.toml:130`). **Observability only — do NOT change the `final_write_state 1 "lock_contention"` stamp** (keep consistent with the deploy path per ADR-079 #5960; the consumer handles it). `ACTION`/`COMPONENT` parsed at `:1175` (verified) → populated at contention.

### Phase 4 — Defect B: restart poll non-terminal `lock_contention` + final STATE re-read (ADR-079 #5960)

**File: `.github/workflows/restart-inngest-server.yml`**
- [ ] 4.1 In the verify poll (`:91-159`), for `component=inngest` (`:143-153`), when `REASON == "lock_contention"`: do NOT `::error::Restart failed` + `exit 1`. Instead `echo` a non-terminal notice and `continue` the loop (mirror `apply-deploy-pipeline-fix.yml:693-698`), keeping the poll running for a fresh `component=inngest && start_ts>=FRESH_FLOOR` terminal success. Track a flag that only `lock_contention` (no other failure reason) was seen.
- [ ] 4.2 At poll-budget expiry (`:158-159`): if only `lock_contention` was seen, do ONE **final STATE re-read** (mirror `apply-deploy-pipeline-fix.yml:719-731`): GET `/hooks/deploy-status` for a fresh `component=inngest` success OR the `/hooks/inngest-liveness` mode `healthy`. If confirmed current → benign `::notice::restart superseded by in-flight deploy/restart (inngest confirmed current)` + `exit 0` + a `SOLEUR_*` marker. If NOT confirmed → `::error::` UNVERIFIED + `exit 1`. A non-`lock_contention` failure at any point still `exit 1`.
- [ ] 4.3 Preserve ADR-100 restart-purity: consumer-side (verify-poll) change only; `ci-deploy.sh` restart handler + the shared `lock_contention` stamp untouched.

### Phase 5 — ADR amendment + runbook + postmortem
- [ ] 5.1 **Amend `ADR-030-inngest-as-durable-trigger-layer.md`** #6374 log with the #6407 decision: corroborate an apparent `inngest_down` against loopback `/health` before declaring down; soft `functions_query_degraded` (no restart) + persistence-escalation ceiling. Cross-ref **ADR-079 #5960** for the restart-poll treatment. **No new ADR ordinal** (refines the existing #6374 decision). **No C4 change** (see below).
- [ ] 5.2 **Update `runbooks/inngest-server.md`**: the `functions_query_degraded` soft mode (meaning, `/health`-corroboration, the ~45-min escalation ceiling, how to query `SOLEUR_INNGEST_LIVENESS_VERDICT` in Better Stack) + the restart `lock_contention`-benign behavior — all no-SSH (`hr-no-ssh-fallback-in-runbooks`).
- [ ] 5.3 **Amend the existing `post-mortems/inngest-watchdog-false-positive-unseen-6374-postmortem.md`** with a `## Residual vector — #6407 (functions-query transient)` section (per simplicity review — fold in, do NOT mint a near-duplicate PIR): the functions-query transient → false `inngest_down` → restart `lock_contention` chain, and the `/health`-corroboration + non-terminal-lock fixes.

## Sibling-Defect Note (scope decision)
`inngest-registry-probe.sh` shares the identical `__FETCH_FAILED__` + FATAL pattern (`:87`, `:103-115`). **Acknowledge, do not fix here:** it targets the REMOTE dedicated host for cutover pre-flight, is NOT on the liveness/restart-dispatch path, and its transient failure cannot cause a false `[ci/inngest-down]` P1 restart (`hr-write-boundary-sentinel-sweep-all-write-sites` — enumerated + consciously scoped out; architecture review concurs).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `bash scripts/inngest-liveness-classify.test.sh` passes incl.: `DEGRADED`→`functions_query_degraded`; `is_restart_family functions_query_degraded`→no; existing `FATAL`→`inngest_down` regression.
- [ ] AC2 — `bash apps/web-platform/infra/inngest-inventory.test.sh` passes: `INVENTORY_INNGEST_HEALTH_CODE=200`+failed-fetch → DEGRADED (not FATAL); `=000` and `=503`+failed-fetch → FATAL (real-down/wedged preserved).
- [ ] AC3 — **Union-widening sweep** (`cq-union-widening-grep`): `grep -n "failure_mode ==" .github/workflows/scheduled-inngest-health.yml` enumerates every consumer, and each of the four soft-mode edits is present: (a) `functions_query_degraded)` arm in the `ISSUE_CLASS` `case` BEFORE `*)`, (b) `functions_query_degraded` in the heartbeat `:597` `ok` allowlist, (c) a `[ci/inngest-functions-degraded]` auto-close branch, (d) the persistence-escalation age-gate reference. A bare token-count grep is INSUFFICIENT.
- [ ] AC4 — Down-branch `else` (`:472-474`) is no-claim-on-empty (no unconditional "Restart re-dispatched"; asserts on `RESTART_OK==true`, escalates on `false`).
- [ ] AC5 — `grep -n 'SOLEUR_INNGEST_LIVENESS_VERDICT' inngest-inventory.sh` and `grep -n 'SOLEUR_INNGEST_RESTART_LOCK_CONTENTION' ci-deploy.sh` each ≥1; both tags present in `vector.toml` Source 4 allowlist.
- [ ] AC6 — `restart-inngest-server.yml` verify poll: `reason=lock_contention` for `component=inngest` → `continue` (non-terminal), NOT immediate `exit 1`; budget-expiry does a final STATE re-read before any `exit 0` (grep-verify a `deploy-status`/`inngest-liveness` re-read after the poll loop).
- [ ] AC7 — Drift-guards still pass (`inngest-inventory.test.sh` durability-parser, `ci-deploy.test.sh` poll-window); `shellcheck` clean on edited `.sh`; `actionlint` clean on both workflows.
- [ ] AC8 — ADR-030 amended; runbook updated; #6374 postmortem gains the #6407 residual-vector section. PR body `Closes #6407`.

### Post-merge (auto, no operator step)
- [ ] AC9 — Merge auto-delivers `inngest-inventory.sh` + `ci-deploy.sh` via `apply-deploy-pipeline-fix.yml` (`/hooks/infra-config`); workflows + classifier effective on merge. No SSH. Verify via `/hooks/infra-config-status` FILE_MAP-count parity (existing workflow step).
- [ ] AC10 — No `[ci/inngest-down]` P1 attributable to a transient functions-query failure across the 7-day soak (Follow-Through).

## Observability

```yaml
liveness_signal:
  what: "Inngest liveness via /hooks/inngest-liveness (functions query CORROBORATED by loopback /health); independent executor beacon scheduled-inngest-cron-watchdog (Sentry cron)."
  cadence: "*/15 (scheduled-inngest-health.yml); executor beacon per its cron cadence."
  alert_target: "Sentry Cron monitor scheduled_inngest_health (paging) + GitHub issues (soft: [ci/inngest-functions-degraded] / [ci/inngest-probe-unavailable]; hard: [ci/inngest-down])."
  configured_in: ".github/workflows/scheduled-inngest-health.yml; scripts/inngest-liveness-classify.sh; apply-sentry-infra.yml monitor."
error_reporting:
  destination: "journald (logger -t inngest-inventory | ci-deploy) -> Vector Source 4 -> Better Stack Logs source 2457081; Sentry Cron heartbeat."
  fail_loud: "A wedged/stopped server (/health != 200) still emits FATAL -> inngest_down -> restart; a sustained functions_query_degraded escalates to inngest_down after ~45min. Corroboration never silently masks a real outage."
failure_modes:
  - mode: "functions-query transient failure, /health=200 (the #6407 false positive)"
    detection: "SOLEUR_INNGEST_LIVENESS_VERDICT mode=degraded health_code=200 (Better Stack, inngest-inventory tag)"
    alert_route: "soft [ci/inngest-functions-degraded] issue, NO restart, NO page; auto-closes on recovery"
  - mode: "genuine down / wedged-but-alive (/health != 200)"
    detection: "SOLEUR_INNGEST_LIVENESS_VERDICT mode=down health_code=<000|5xx> -> classifier inngest_down"
    alert_route: "restart-inngest-server.yml (age-gated) + Sentry page"
  - mode: "sustained functions_query_degraded (health-ok but functions wedged >45min)"
    detection: "[ci/inngest-functions-degraded] issue age >= GIVE_UP_WINDOW; escalated to inngest_down"
    alert_route: "reclassify -> restart + Sentry page (no indefinite soft-mask)"
  - mode: "restart lock_contention (deploy/restart already in progress)"
    detection: "SOLEUR_INNGEST_RESTART_LOCK_CONTENTION action=restart component=inngest (Better Stack, ci-deploy tag)"
    alert_route: "restart poll non-terminal; final STATE re-read confirms current; benign; no P1"
logs:
  where: "Better Stack Logs source 2457081 (Vector Source 4, tags inngest-inventory + ci-deploy); GitHub Actions run logs."
  retention: "Better Stack account retention; journald on-host ring buffer."
discoverability_test:
  command: "Query Better Stack Logs for SOLEUR_INNGEST_LIVENESS_VERDICT and SOLEUR_INNGEST_RESTART_LOCK_CONTENTION (ClickHouse-SQL, no ssh); or GET https://deploy.soleur.ai/hooks/deploy-status (HMAC+CF-Access) for services.inngest_server."
  expected_output: "A degraded/down verdict event with mode + health_code + functions fields; a lock_contention marker with action/component; NO ssh required."
```

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

No new Terraform resource, secret, vendor, or persistent process — edits **existing** host scripts + CI workflows. The `systemctl` references in this plan are (a) existing runtime behavior of `ci-deploy.sh`'s restart handler and (b) read-only `/health`/liveness diagnosis — NOT manual operator provisioning.

### Apply path
- **Host scripts** (`inngest-inventory.sh`, `ci-deploy.sh`): the existing **immutable-redeploy** mechanism — `apply-deploy-pipeline-fix.yml` fires on merge touching those paths (`:66`, `:89`) → base64 payload via `/hooks/infra-config` → `infra-config-apply.sh` FILE_MAP (`CI_DEPLOY_SH_B64`, `INNGEST_INVENTORY_SH_B64`). **No in-place SSH** (`hr-prod-host-config-change-immutable-redeploy`). Post-apply verify: `/hooks/infra-config-status` FILE_MAP count parity (existing step).
- **CI-consumed** (`inngest-liveness-classify.sh` + `.test.sh`, `scheduled-inngest-health.yml`, `restart-inngest-server.yml`): checked out at runtime; effective on merge. No host delivery.
- **Blast radius / downtime:** none. Guard-only additions (a corroboration branch, a non-terminal poll case, markers, soft-mode routing). Existing green paths (`healthy`, real `inngest_down`, `probe_unavailable`) unchanged.

### Distinctness / drift safeguards
- `dev != prd`: N/A (single prod inngest host; no dev watchdog).
- Drift guards: `inngest-inventory.test.sh` durability-parser + `ci-deploy.test.sh` poll-window must stay green (AC7).

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-030** — extend the 2026-07-13 #6374 amendment log with the #6407 decision (corroborate apparent `inngest_down` against loopback `/health`; soft `functions_query_degraded`; persistence-escalation ceiling). Cross-reference **ADR-079 amendment #5960** as the precedent applied to the restart poll. **No new ADR ordinal** (refines an existing decision — avoids the ordinal-collision footgun).

### C4 views
- **No C4 impact.** Enumerated against all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`):
  - **External human actors:** none new (watchdog is internal GHA).
  - **External systems/vendors:** none new — Better Stack log sink already modeled (`inngest -> betterstack` edge, `model.c4:376`).
  - **Containers / data stores:** `inngest` (`:184`), `inngestPostgres` (`:188`), `inngestRedis` (`:192`) all modeled; none added/changed (no redis change despite the issue title).
  - **Access / ownership relationships:** none change (no tenancy/owner boundary moves).
  - A new soft *mode* + issue *class* is a new observable state, not a C4 element (ADR-030/105/106 watchdog precedent: "No C4 impact"). No element description is falsified. (Architecture review confirmed.)

## Domain Review
**Domains relevant:** none — infrastructure / observability / CI-reliability change. No product/UI surface (Files-to-Edit are `.sh`/`.yml`/`.md` only). Engineering-only.

## Risks & Mitigations
- **R1 — corroboration masks a real down/wedge.** Solved by choosing `/health` (not `is-active`): a wedged-but-alive server (`active` yet HTTP-unresponsive) fails `/health` → stays `inngest_down` → restart fires (and a restart recovers a wedge). AC2 asserts the `health_code=000/503` fixtures still emit FATAL.
- **R2 — cross-host corroboration invalidity.** `/health` runs on the SAME loopback server as the functions query (both inside `inngest-inventory.sh` on the liveness host). Phase 0.1 verifies the liveness host runs inngest-server.
- **R3 — deploy-race window (old on-host `inngest-inventory.sh` during infra-config push).** After merge the CI-consumed classifier knows the new mode, but the host keeps emitting the old `FATAL` sentinel until the push lands — a transient still maps `FATAL→inngest_down→restart` in that window, but Defect B (live on merge) prevents the restart from RED-failing on `lock_contention`. Expected; matches ADR-079 precedent.
- **R4 — union-widening: the two fail-dangerous consumers.** `ISSUE_CLASS *) → down` and heartbeat `:597` default a new mode to the HARD path. Phase 2.4/2.5 make both mandatory edits; AC3 sweeps `failure_mode ==`.
- **R5 — untruthful soft-issue comment.** The new class gets its OWN accurate body (`/health=200; NO restart`), NOT the reused `liveness-probe` "probe path unavailable" wording; the down-branch `else` is hardened no-claim (2.7). Per `2026-07-13-watchdog-excluded-mode-shares-issue-class-untruthful-comment.md`.
- **R6 — up-but-wedged masking (health-ok, functions permanently wedged).** The narrow residual where `/health`=200 but the GQL functions path is deadlocked. Bounded by the Phase 2.8 persistence-escalation ceiling (~45 min → reclassify to `inngest_down`, page + restart). Not silently soft-masked forever.
- **R7 — restart-poll false-clean at budget expiry.** Phase 4.2 does a final STATE re-read (mirror `apply-deploy-pipeline-fix.yml:719-731`) before `exit 0`; an unconfirmed state fails loud, so a concurrent op that ALSO failed doesn't produce a false-clean restart.

## Precedent Diff (deepen Phase 4.4)
- **Non-terminal `lock_contention` (Defect B).** Precedent: `apply-deploy-pipeline-fix.yml:693-698` — `case "$REASON" in lock_contention|adr027_prod_already_running) … continue ;;`, then final STATE re-read at `:719-731`. Plan Phase 4 applies the SAME shape to the restart poll (component=inngest). ADR-079 amendment #5960 (2026-07-03) is the decision of record.
- **Age-gate reuse (persistence escalation).** Precedent: `scripts/inngest-restart-age-gate.sh` (`restart_ok_from_age`) + GIVE_UP_WINDOW at `scheduled-inngest-health.yml:298`. Phase 2.8 reuses the timestamp logic against the new issue title (inverted: escalate when age ≥ window). No novel locking primitive introduced.
- **`/health` liveness signal.** Precedent: `ci-deploy.sh verify_inngest_health` gates on `/health` (~`:1019`). Phase 1 reuses the same endpoint. No novel probe.

## Follow-Through Enrollment (soak)
AC10 soak: "no `[ci/inngest-down]` P1 attributable to a transient functions-query failure for 7 days post-deploy."
- **Script:** `scripts/followthroughs/inngest-watchdog-functions-query-6407.sh` — exit 0 when no new `[ci/inngest-down]` issue with a functions-query/`__FETCH_FAILED__` root cause since deploy (query GitHub issues + Better Stack `SOLEUR_INNGEST_LIVENESS_VERDICT mode=down` events; `start=` pinned strictly after deploy).
- **Tracker directive:** `<!-- soleur:followthrough script=inngest-watchdog-functions-query-6407.sh earliest=<deploy+7d> secrets=BETTERSTACK_QUERY_TOKEN,GH_TOKEN -->` + `follow-through` label on #6407.
- **Sweeper secrets:** wire any new `secrets=` into `.github/workflows/scheduled-followthrough-sweeper.yml`.

## Sharp Edges
- Corroboration MUST use loopback `/health`, NOT `systemctl is-active` (returns `active` for a wedged server) NOR `derive_durability_state()`/ExecStart (readable for a stopped unit). `/health` is the only same-signal-class liveness corroborator.
- `functions_query_degraded` is a new `failure_mode` value → hits FOUR consumers; two (`ISSUE_CLASS *)→down` at `:363`, heartbeat `ok`-list at `:597`) default to the HARD path. Both are mandatory edits, not "verify" — omitting either re-creates a false P1 / a Sentry page. Run the `failure_mode ==` sweep (AC3).
- The new soft class needs an auto-close branch (`:481-515`) or the issue rots open forever (state-machine Q4).
- Do NOT change `ci-deploy.sh`'s `lock_contention` STAMP (keep exit-1, consistent with the deploy path per ADR-079 #5960); fix the CONSUMER (restart verify poll) + add the observability marker only.
- Restart-poll budget-expiry must do a final STATE re-read before `exit 0` (mirror the deploy poll) — a blind benign exit false-cleans if the in-flight op also failed.
- A plan whose `## User-Brand Impact` is empty/TBD fails deepen-plan Phase 4.6 — filled here (aggregate pattern).
