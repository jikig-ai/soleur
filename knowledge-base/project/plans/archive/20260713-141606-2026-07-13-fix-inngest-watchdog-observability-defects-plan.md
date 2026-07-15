---
title: "fix: Inngest health-watchdog observability defects (paging gap + false-positive probe + restart churn)"
date: 2026-07-13
type: fix
status: draft
branch: feat-one-shot-inngest-watchdog-observability-6374
lane: cross-domain
brand_survival_threshold: aggregate pattern
tracks:
  - "#6374"   # the P1 [ci/inngest-down] incident that ran unseen ~14h
related:
  - "#6178"   # counterpart cutover blocker (extract inngest to its own HA host)
  - "#5542"   # the original ~3.5h silent crash-loop this watchdog was built to close
---

# fix: Inngest health-watchdog observability defects 🐛

## Overview

On 2026-07-12/13, a P1 `[ci/inngest-down]` alarm (#6374) ran **unseen for ~14h**. The external Inngest health watchdog (`.github/workflows/scheduled-inngest-health.yml`, built for the #5542 silent-crash-loop incident) detected a probe failure, filed a GitHub issue, and auto-dispatched hourly restarts — but **nothing pushed the alarm to the operator**, the probe likely **false-positived** (the read path 500'd while crons kept firing), and the restart loop **churned a healthy scheduler ~14×** with no give-up.

This plan fixes three distinct, code-verified defects and closes the readiness-gate blind spot that let the operator start a `/soleur:go` turn without being told inngest was down.

**The three defects (all verified against the code — see Research Reconciliation):**

1. **Delivery gap (root cause of the 14h).** The workflow's *intended* operator-facing signal is a Sentry Crons heartbeat (`scheduled-inngest-health.yml:475-484`, `?status=error` on failure). But **there is no `sentry_cron_monitor` resource named `scheduled-inngest-health`** in `cron-monitors.tf` — Sentry silently drops check-ins for unknown slugs (the exact gap documented at `cron-monitors.tf:708-716`), so the error heartbeat pages nowhere. The only surviving signal was the GitHub issue, which no non-technical operator watches. The existing IaC parity guard (`sentry-monitor-iac-parity.test.ts`) is one-way (Inngest-function slugs → IaC) and **explicitly excludes GHA-workflow heartbeat slugs**, so nothing caught the gap.

2. **False-positive probe.** The watchdog's SOLE liveness signal is the `inngest-inventory` hook, whose script (`inngest-inventory.sh`) runs a **heavy, paginated `eventsV2` scan over a 365-day window** (22s deadline, page ceiling, MAX_ARG_STRLEN spool) *in addition to* the lightweight `/v0/gql functions` query. Any non-liveness failure of that read path — deadline abort, page-ceiling abort, `EMAXCONNSESSION` pool pressure, malformed-GraphQL — returns non-200 and is declared `inngest_down`, even when the cron **executor is healthy and firing crons**. The inventory hook is a *cutover baseline* tool, not a liveness probe. The true process-liveness gate already exists on-host: `curl 127.0.0.1:8288/health` (ci-deploy.sh's HARD gate, `ci-deploy.sh:944-973`), but it is loopback-only and the watchdog never uses it.

3. **Restart churn.** `scheduled-inngest-health.yml:279-288` dispatches `restart-inngest-server.yml` on **every** `*/15` probe run that sees `inngest_down`/`inngest_unhealthy`, with **no cap and no give-up**. `restart-inngest-server.yml` itself has no dedup. A probe fault a restart cannot fix (Defect 2) bounces the scheduler indefinitely (~14× over the incident).

**Plus:** the `/soleur:go` turn-1 readiness gate (`commands/go.md:21-34`) probes **git-repo usability only** — it does not check inngest liveness or open `[ci/inngest-down]` issues, so an operator can start a turn while inngest is down. This plan adds a cheap inngest-awareness check to the readiness surface.

## Research Reconciliation — Spec vs. Codebase

| Feature-description claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| Defect 1: "alerts by GitHub issue ONLY — no Sentry page" | **Partially stale.** A Sentry heartbeat step *exists* (`scheduled-inngest-health.yml:475-484`) but posts to slug `scheduled-inngest-health` which has **no `sentry_cron_monitor` resource** (`cron-monitors.tf` — grep confirms only `scheduled-inngest-cron-watchdog`). Sentry silently drops unknown-slug check-ins → pages nowhere. | Reframe Defect 1 to its true root cause: **add the missing monitor resource** + a structural parity guard for GHA-workflow heartbeat slugs. Do NOT "add a heartbeat" (it exists). |
| Defect 1: reach operator via "Sentry alert-rule → phone, or Better Stack" | Repo paging convention is **`sentry_issue_alert` → `notify_email` → IssueOwners/ActiveMembers → founder email** (14 sibling rules in `issue-alerts.tf`); cron-monitor failures page via Sentry's built-in monitor-failure notifications (40+ sibling `sentry_cron_monitor`s rely on this — e.g. `cron-egress-resolve`, `scheduled-realtime-probe`). | Use the **existing, proven** channels: the cron monitor (dead-man's-switch + `?status=error`) as primary; verify it pages; belt-and-suspenders `sentry_issue_alert` only if cron-monitor paging is insufficient (decide in deepen-plan). No new vendor. |
| Defect 2: "sole liveness = `/v0/gql` query; 500 == down" | **Confirmed.** `inngest-inventory.sh` liveness = `/v0/gql functions` **+ a 365-day `eventsV2` scan**; any non-200 (incl. deadline/ceiling/pool/GraphQL-error) → `inngest_down`. | Replace liveness signal with a **true, lightweight probe** (`/health` process-liveness + optional lightweight functions query), decoupled from the eventsV2 read path. |
| Defect 2: use "inngest `/health` endpoint or recent `function.finished` check" | `/health` exists at `127.0.0.1:8288/health` (`ci-deploy.sh:944-973`, `:1085`, `:1791`) but is **loopback-only**; `/v1/functions` is a **404** (unregistered) in v1.19.4. | Add a small on-host `/hooks/inngest-health` webhook (mirrors the 8 existing inngest hooks) that curls loopback `/health`; watchdog probes it externally. |
| Defect 3: restarts dispatched "hourly ~14×" | **Confirmed** *no cap*; cadence is `*/15` (every 15 min, up to 4×/h), not hourly — "~14×" is the incident total, not the rate. | Cap consecutive failed restarts + escalate; correct the "hourly" framing in the plan (does not change the fix). |
| "The `/soleur:go` turn-1 readiness pass checked app health, not inngest health" | **Imprecise.** `commands/go.md:21-34`'s turn-1 gate checks **git-repo usability** (`git-repo-readiness-diag.sh`), not app/prod health. `postmerge/SKILL.md` has a separate prod-health check. No existing gate checks inngest liveness. | Treat as a *new* check to add. Enumerate insertion-point candidates (go preamble / one-shot Step 0 / postmerge prod-health); DECIDE the surface in deepen-plan. Flag: `commands/go.md` routing block is **eval-gated** (`eval-gate:block:go-routing`) — an additive readiness line must not trip it. |
| "close #6374 if the probe confirms it's a false positive" | #6374 OPEN, P1, detail = "inventory hook HTTP 500". Created 2026-07-12 20:43Z. Consistent with a heavy-read false-positive while crons fired. | In-scope work item: cross-check inngest liveness at incident time (Sentry `scheduled-inngest-cron-watchdog` check-ins / function fires around 20:43Z); close #6374 as false-positive if confirmed. |

## User-Brand Impact

**If this lands broken, the user experiences:** the next real Inngest outage (armed reminders + all `server/inngest/functions/` crons silently stop firing) runs **unseen** again — the exact #6374 recurrence — because the operator is never paged. A user's scheduled action (a reminder, a KB sync, a triage) silently never happens.

**If this leaks, the user's data is exposed via:** N/A — this change touches CI workflows, Terraform monitors, and on-host health scripts only. It reads inngest process-liveness (`/health`) and open-issue metadata; it moves no user content. The new on-host script emits **enum/count only** (mirroring `inngest-inventory.sh`'s `#5503` purity: never the ExecStart string, never a connection URI, never a raw GraphQL `errors[].message`).

**Brand-survival threshold:** aggregate pattern — the failure mode is "outages go undetected," an operational/observability pattern. (The *underlying* inngest outage it guards is single-user-incident severity; this change is the detection layer, which exposes no user data.)

## Implementation Phases

### Phase 0 — Preconditions & premise verification (no code)
- Confirm (live, read-only) that **no** Sentry monitor `scheduled-inngest-health` exists: `sentry_cron_monitor` grep already shows absence; deepen-plan/work verifies against the live Sentry via the Management/monitor list if a token is available (idempotent either way — adding the resource is safe).
- Read the two most-recent `sentry_cron_monitor` blocks in `cron-monitors.tf` and adopt their field conventions verbatim (org, project, schedule shape, margin/runtime/threshold, timezone).
- Confirm the `apply-sentry-infra.yml` path filter includes `cron-monitors.tf` (it does — `:46`) so the new monitor auto-applies on merge with **no operator step**.
- Read `hooks.json.tmpl` + one sibling inngest hook script (`inngest-registry-probe.sh`) + the infra-config payload wiring to mirror the delivery pattern for the new `inngest-health` hook.
- **False-positive determination for #6374:** pull inngest liveness evidence around 2026-07-12 20:43Z (Sentry `scheduled-inngest-cron-watchdog` check-in continuity; any `function.finished`/cron fire in that window). Record verdict for the post-merge close step.

### Phase 1 — Defect 1: close the delivery gap (page the operator)
1. Add `resource "sentry_cron_monitor" "scheduled_inngest_health"` to `cron-monitors.tf` — `name = "scheduled-inngest-health"` (matches the heartbeat slug at `scheduled-inngest-health.yml:480`), `schedule = { crontab = "*/15 * * * *" }`, `checkin_margin_minutes` sized for a 15-min cadence (deepen-plan picks the exact value from the file's cohort conventions; a tight margin is correct — inngest-down is a brand-survival outage), `max_runtime_minutes` = 8 (matches the job's `timeout-minutes`), `failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`. With `threshold=1`, a single `?status=error` OR a missed check-in opens a Sentry monitor-failure issue → pages the operator within ~15-30 min (vs 14h).
2. **Add `-target=sentry_cron_monitor.scheduled_inngest_health` to `.github/workflows/apply-sentry-infra.yml`** (see Infrastructure → Apply path — without this the monitor is declared but never applied).
3. **Structural guard (fold-in, do not defer):** extend a parity test to assert every `sentry-heartbeat` `monitor-slug:` used by a `.github/workflows/*.yml` has (a) a matching `sentry_cron_monitor.name` in `cron-monitors.tf` AND (b) that resource name in the `apply-sentry-infra.yml` `-target=` allowlist. This is the GHA-workflow counterpart to `sentry-monitor-iac-parity.test.ts` (which covers only `server/inngest/functions/`). [SIMPLIFICATION per review] Population today is ONE workflow — prefer extending the existing `sentry-monitor-iac-parity.test.ts` with the workflow-slug + `-target` clauses over a whole new test file; only create a separate file if that proves awkward. Makes "heartbeat into the void" (and "applied nowhere") structurally impossible.
4. **Paging is confirmed sufficient — do NOT add a `sentry_issue_alert` [deepen-plan resolved].** The verification agent confirmed against `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md:476-480` that `sentry_cron_monitor` failures page **on their own** via `failure_issue_threshold` (this is how the #4650 missed-check-in regression was caught) — identical posture to all 20+ siblings; no cron-monitor-failure `sentry_issue_alert` exists or is needed. **De-risk (pre-merge, not post-merge):** because the default project notification path is not itself in IaC, pull one piece of live evidence that a sibling cron-monitor failure actually notified `ops@jikigai.com` (Sentry monitor-notification history via `scripts/sentry-issue.sh`) BEFORE relying on it. If that evidence cannot be obtained, THEN add the `sentry_issue_alert` fallback (tagged Sentry event from the workflow + `feature=inngest-watchdog`/`op=inngest-down` `notify_email` rule). Default path: monitor-only.

### Phase 2 — Defect 2: true liveness probe (decouple from the eventsV2 read path)

**[DESIGN — deepen-plan] Two options; DEFAULT to Option A (smaller surface, preserves durability wiring).**

- **Option A (default, per simplicity + spec-flow review): a liveness-only mode inside the existing `inngest-inventory.sh`.** That script (`:124,314-398`) ALREADY runs the lightweight `/v0/gql { functions { id name slug } }` loopback query, already fails LOUD on a non-array, and already emits `durability_state` via `derive_durability_state` — Defect 2 is *solely* that this cheap path is bundled with the heavy paginated `eventsV2` scan (`:227-296`). Add an `INVENTORY_LIVENESS_ONLY` guard that skips the eventsV2 scan (emit `event_names:[]`, `armed_reminders:[]`) and returns `{ functions, functions_count, durability_state }`. Repoint the watchdog to invoke that mode (a query param on the existing hook, or one small `inngest-liveness` hook id in `hooks.json.tmpl` that runs the **already-staged** `inngest-inventory.sh` with the env flag — reusing `INNGEST_INVENTORY_SH_B64`, **no new payload, no `push-infra-config.sh`/`FILE_MAP`/`vector.toml` edits**). The heavy inventory path stays intact for cutover baseline. **This naturally preserves `durability_state` and the `steps.probe.outputs.durability_state` wiring (see C-invariants below) and keeps the `inngest-inventory` journald tag that is already Better Stack-allowlisted.** Optionally add a `curl 127.0.0.1:8288/health` line inside this mode as a marginal upgrade — not required to close Defect 2 (the root cause was eventsV2, not the functions query).
- **Option B (SRP-cleaner, more surface): a new `apps/web-platform/infra/inngest-health.sh` + `/hooks/inngest-health` webhook** mirroring the 8 existing inngest hooks. If chosen, it MUST also emit `durability_state` in the exact enum, AND Files-to-Edit MUST additionally include `push-infra-config.sh` (payload key), `infra-config-apply.sh` (FILE_MAP row), `apps/web-platform/infra/vector.toml` (add `inngest-health` to the `SYSLOG_IDENTIFIER` allowlist `:127-153`), and `apps/web-platform/test/infra/vector-pii-scrub.test.sh` (drift fixture) — otherwise the Better Stack journald destination is silently dropped (observability P1).

**Invariants BOTH options MUST satisfy:**
1. **[C-invariant, spec-flow C1-C5] Preserve `durability_state`.** The liveness verdict body MUST still emit `durability_state` in the exact enum `durable|degraded|sqlite_only|unknown|absent`, and `steps.probe.outputs.durability_state` (read at `scheduled-inngest-health.yml:111-113`, gated at `:414` advisory-open and `:460` auto-close) MUST still resolve — else the #5553 between-deploy detector silently dies AND open `[ci/inngest-degraded-durability]` issues never auto-close. Emit `durability_state` whenever the process is live, independent of the functions-query outcome. Add fixtures: a `degraded` body still opens the advisory; a `durable` body still auto-closes it.
2. **[Deploy-race tolerance, architecture Hazard 2 + observability P1] Distinguish a broken/undeployed probe path from a real down.** The consumer (repointed workflow) goes live at merge; the producer (on-host mode/hook) lands async via `apply-deploy-pipeline-fix.yml`. A `*/15` tick in that window (or a CF-Access/`webhook.service` degrade) returns 404/000/non-200 → must be classified `probe_unavailable` (a soft alert, **NO restart**), NOT `inngest_down`. Only a **well-formed body with `healthy:false`/missing `.functions`** declares `inngest_down`. Gate the restart dispatch on a well-formed down body, never on a bare non-200.
3. **[functions_count==0 grace, observability P2] Cold-start churn guard.** A live-but-empty registry (`{functions:[]}`) is legitimate transiently after a restart; add a short grace/retry before declaring `inngest_unhealthy` so a post-restart cold start doesn't self-perpetuate. Note the Defect-3 cap is the backstop.

Keep the 3× in-run retry resilience. Update the relevant test (`inngest-inventory.test.sh` for Option A; new `inngest-health.test.sh` for Option B) with the liveness-only + durability + probe-unavailable fixtures.

### Phase 3 — Defect 3: cap the restart loop + escalate

**[REDESIGN — deepen-plan] Use an issue-AGE gate, NOT a body counter.** The spec-flow review (A1-A7) found the counter approach has an ordering hazard: the auto-dispatch step (`scheduled-inngest-health.yml:279-288`) runs BEFORE the tracking issue is created (`:290-376`), so there is no store to read/write on the first failure, and a `gh issue edit --body` marker RMW risks clobber + races. An age gate sidesteps all of it (one read, zero writes, no chicken-and-egg):

1. **Insert a count-free gate step BEFORE the dispatch step.** Read the open `[ci/inngest-down]` issue's `createdAt` (`gh issue list --label ci/inngest-down --state open --json number,createdAt`). Emit a `restart_ok` output:
   - Issue absent (first failure of the episode) → `restart_ok=true` (dispatch once).
   - Issue present AND age < GIVE_UP_WINDOW (≈45 min ≈ 3 `*/15` cycles) → `restart_ok=true`.
   - Issue present AND age ≥ GIVE_UP_WINDOW → `restart_ok=false` (give up).
2. Gate the dispatch step `if:` on `restart_ok == 'true'` AND the existing down-family predicate. At/after give-up: **stop dispatching** and escalate — the file-issue step's down-branch (`:361-375`) must, when `restart_ok=false`, **replace** its hardcoded "Restart re-dispatched" comment (`:371`) with a loud "restarts exhausted (>N min) — inngest still down, human root-cause needed" comment (thread `restart_ok` through as a step output so the comment text is truthful — spec-flow A3/B2) and add a human-attention label (idempotent; escalate the comment once at the boundary, not every cycle — B3).
3. **Paging continues at give-up:** the Sentry heartbeat status keys off `failure_mode` (`:481`), not off whether a dispatch happened, so Phase 1's monitor keeps paging — state this as the explicit reason (B1).
4. **Reset:** recovery auto-closes the issue (`:378-405`) → next episode opens a fresh issue → age resets naturally. Add resilience for a failed `gh issue close` (spec-flow B4): the age gate is self-correcting (a stale-open capped issue that recovers still auto-closes on the next healthy run), so no marker-reset step is needed — an advantage over the counter.
5. **[Contingency, spec-flow B5]** The age gate bounds churn per-episode; it only prevents the ~14× churn when **Phase 2's stable probe is in place** (a flapping false-positive re-opens/re-closes the issue, resetting the age). State that Phase 3's effectiveness is contingent on Phase 2.
6. **[Write-boundary sweep, architecture (b)]** `restart-inngest-server.yml` is also dispatched from a SECOND site — `inngest-watchdog-restart-dispatch.yml:49` (the #4650 D1-B label path). Phase 3 caps only the `*/15` loop site (the churn source). Document the label path as explicitly out-of-churn-scope (`hr-write-boundary-sentinel-sweep-all-write-sites`).
7. Ensure `restart-inngest-server.yml` dispatch remains excluded for pool modes (already correct, `:275-278`) — do NOT widen.

### Phase 4 — Readiness-gate inngest awareness
1. Add a cheap `[ci/inngest-down]`-open-issue awareness check to the readiness surface the operator's turn-1 actually hits. Concrete candidates (deepen-plan DECIDES; default target = the surface that already runs a prod-facing check): (a) `postmerge/SKILL.md` prod-health verification; (b) an additive advisory in `commands/go.md` / `one-shot` Step 0 readiness preamble. Check = `gh issue list --label ci/inngest-down --state open` (+ optionally probe `/hooks/inngest-health`) → surface a one-line advisory, do NOT hard-block the turn.
2. **Eval-gate guard:** if the insertion point is `commands/go.md`, keep the addition OUTSIDE the eval-gated routing block (`eval-gate:block:go-routing`) — an additive readiness advisory, not a routing change.

### Phase 5 — Tracking issues & #6374 disposition
- Reference #6374 with `Ref #6374` in the PR body (NOT `Closes` — the monitor + health hook apply **post-merge** via `apply-sentry-infra.yml` + the infra-config push; `Closes` would false-resolve at merge before the fix is live — `wg-use-closes-n-in-pr-body-not-title-to` / ops-remediation Sharp Edge).
- Post-merge: after the monitor is applied and the health hook is live, close #6374 with the false-positive verdict from Phase 0 (or leave open with a note if inngest was genuinely down).
- File a tracking issue only for any sub-scope deepen-plan/plan-review defers (none anticipated; the parity guard and readiness check are folded in). #6178 (extract inngest to HA host) already exists — this plan is its observability counterpart, not the extraction.

## Files to Edit
*(Option A = reuse inventory liveness mode, the default; Option B = new health hook. Option A has the smaller list.)*
- `.github/workflows/scheduled-inngest-health.yml` — repoint liveness to the liveness-only probe with probe-unavailable/deploy-race tolerance (Defect 2); add the age-gate + escalate logic (Defect 3).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `scheduled_inngest_health` monitor (Defect 1).
- **`.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_cron_monitor.scheduled_inngest_health` to the allowlist (Defect 1 BLOCKER; without it the monitor never applies).**
- `apps/web-platform/infra/inngest-inventory.sh` (+ `inngest-inventory.test.sh`) — **Option A:** add `INVENTORY_LIVENESS_ONLY` mode (skip eventsV2; keep functions + durability_state) + fixtures.
- `apps/web-platform/infra/hooks.json.tmpl` — **Option A:** add one small `inngest-liveness` hook id running the already-staged `inngest-inventory.sh` with the env flag (reuse `INNGEST_INVENTORY_SH_B64` — no new payload); **Option B:** register `/hooks/inngest-health` + payload.
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` — extend to cover GHA-workflow heartbeat slugs + the `apply-sentry-infra.yml` `-target=` allowlist (Phase 1.3; prefer extending over a new file since the workflow-heartbeat population is one).
- `plugins/soleur/skills/postmerge/SKILL.md` **or** `plugins/soleur/commands/go.md` / `plugins/soleur/skills/one-shot/SKILL.md` — readiness inngest-awareness check (Phase 4; surface decided in deepen-plan/work).
- **Option B ONLY (if the new-hook route is chosen):** `apps/web-platform/infra/push-infra-config.sh` (payload key), `apps/web-platform/infra/infra-config-apply.sh` (FILE_MAP row), `apps/web-platform/infra/vector.toml` (add `inngest-health` to the `SYSLOG_IDENTIFIER` allowlist), `apps/web-platform/test/infra/vector-pii-scrub.test.sh` (drift fixture).

## Files to Create
- **Option B ONLY:** `apps/web-platform/infra/inngest-health.sh` + `apps/web-platform/infra/inngest-health.test.sh`.
- *(No new parity-test file — fold the workflow-slug guard into the existing `sentry-monitor-iac-parity.test.ts`. No new inngest-health.sh under Option A.)*

## Open Code-Review Overlap
None. (`gh issue list --label code-review --state open` scanned against the file list at plan time; no open scope-out touches these files. `/work` re-verifies the final list.)

## Domain Review

**Domains relevant:** none

No cross-domain (product/marketing/sales/finance/legal/ops/support) implications — this is an infrastructure/observability change (CI workflows, Terraform monitor, on-host health script, a readiness-skill edit). Engineering/CTO concerns are captured inline in Risks and the Architecture Decision section. No UI surface (no files under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`) → Product/UX Gate = NONE.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf`: add one `sentry_cron_monitor "scheduled_inngest_health"`. Provider `jianyuan/sentry` (pinned, existing). No new sensitive variables — uses existing `var.sentry_org` + `data.sentry_project.web_platform`.

### Apply path
- **[CORRECTED — deepen-plan BLOCKER]** `apply-sentry-infra.yml` does NOT apply an untargeted monitor scope. It builds a **saved plan against an explicit `-target=` allowlist** (`apply-sentry-infra.yml:196-265`, `-out=tfplan`; apply consumes `tfplan`, so plan-targets == apply-targets — ADR-031's 2026-05-29 amendment). A new `sentry_cron_monitor.scheduled_inngest_health` that is **not** added to that `-target=` list will **never be applied** — the monitor never materializes and Defect 1 ships unfixed while CI stays green. **Therefore `.github/workflows/apply-sentry-infra.yml` is a required Files-to-Edit: add `-target=sentry_cron_monitor.scheduled_inngest_health` next to the existing `scheduled_inngest_cron_watchdog` target (`:219`).** Additive/create-only → no `[ack-destroy]` needed. With that, the monitor applies on merge — no operator step.
- The health-liveness change lands via the **infra-config push** (immutable-redeploy path, `hr-prod-host-config-change-immutable-redeploy`) — no SSH. Delivery wiring (verified): the script's base64 payload key goes in `push-infra-config.sh`, and the on-host `FILE_MAP` row goes in `infra-config-apply.sh` (format `ENV_VAR|dest|mode|owner:group`); `apply-deploy-pipeline-fix.yml:407` derives `EXPECTED_COUNT` from the FILE_MAP `_B64|` rows and fails LOUD if the script doesn't land (the #6178 false-green guard) — so no separate count edit, but the FILE_MAP row is mandatory. A new HTTP-exposed hook also needs a `hooks.json.tmpl` block (the orphan-hook self-check `infra-config-apply.sh:203-226` fails LOUD if hooks.json advertises a script not written this push — hooks.json + FILE_MAP must land together).

### Distinctness / drift safeguards
- New monitor is apply-created (not import-only), so it needs no `lifecycle.ignore_changes` beyond sibling convention; adopt whatever the two most-recent cron-monitor blocks use.
- **[CORRECTED — deepen-plan BLOCKER]** The Phase-1.2 parity guard must assert the workflow heartbeat slug is present in `cron-monitors.tf` **AND in the `apply-sentry-infra.yml` `-target=` allowlist** — a guard that checks only `cron-monitors.tf` passes green while the monitor is never applied (the exact `-target`-allowlist-sweep Sharp Edge). Guard both, or the structural fix does not close the gap.

### Vendor-tier reality check
- Sentry Crons monitors are in-tier (40+ already provisioned). No paid-tier gate. `notify_email` (the repo's paging convention) is in-tier.

## Observability

> **As-shipped correction (post-implementation):** this block was authored before the Option A/B fork was resolved. The shipped fix uses **Option A** — `inngest-inventory.sh` `INVENTORY_LIVENESS_ONLY` mode (the cheap `/v0/gql functions` query + `durability_state`, no eventsV2) exposed via the new `/hooks/inngest-liveness` GET hook — NOT a new `inngest-health.sh` / `curl /health` script. The liveness verdict rides the functions-query path; the on-host `curl 127.0.0.1:8288/health` HARD gate remains ci-deploy's boot gate. Heartbeat step is at `scheduled-inngest-health.yml` final step (`monitor-slug: scheduled-inngest-health`); the journald tag reuses the already-Better-Stack-allowlisted `inngest-inventory` tag (no vector.toml change). The `inngest-health.sh` / `/health` references below reflect the pre-decision Option-B draft.

```yaml
liveness_signal:
  what: "scheduled-inngest-health.yml posts a Sentry Crons heartbeat (ok|error) each */15 run to the scheduled-inngest-health monitor"
  cadence: "every 15 min"
  alert_target: "Sentry cron-monitor failure notification → operator (email, IssueOwners→ActiveMembers) on a single ?status=error OR a missed check-in (failure_issue_threshold=1)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (scheduled_inngest_health) — NEW; heartbeat step scheduled-inngest-health.yml:475-484 (existing)"
error_reporting:
  destination: "Sentry cron monitor scheduled-inngest-health (error check-in) + the existing [ci/inngest-down] tracking issue"
  fail_loud: "yes — a missed check-in (workflow disabled / GHA outage) ALSO pages; the health hook + inventory hook fail LOUD (non-200) rather than emit a false-clean body"
failure_modes:
  - mode: "inngest process down (/health non-200)"
    detection: "inngest-health.sh curl 127.0.0.1:8288/health fails → healthy=false → hook non-200 → workflow ?status=error"
    alert_route: "scheduled-inngest-health monitor error check-in → operator email; [ci/inngest-down] issue"
  - mode: "inngest process up but API degraded (functions query fails / count 0)"
    detection: "inngest-health.sh lightweight /v0/gql functions probe → inngest_unhealthy"
    alert_route: "same monitor error check-in + [ci/inngest-down] issue (NO longer conflated with the heavy eventsV2 read path)"
  - mode: "health-probe path broken / not-yet-deployed (404/000/CF-Access) — NOT inngest-down"
    detection: "liveness probe returns non-200 / non-well-formed body → classified probe_unavailable (deploy-race window or webhook.service degrade)"
    alert_route: "soft probe-unavailable alert; NO restart dispatched (distinguishes broken probe from real down — closes the relocated false-positive)"
  - mode: "restart give-up reached (inngest still down after GIVE_UP_WINDOW)"
    detection: "open [ci/inngest-down] issue age >= ~45 min at the age-gate step (single gh read, no counter/marker)"
    alert_route: "loud 'restarts exhausted' comment replaces the 're-dispatched' text + human-attention label; Sentry error heartbeat keeps paging (status keys off failure_mode, not dispatch)"
  - mode: "post-restart cold start (live-but-empty registry)"
    detection: "functions_count==0 with a short grace/retry before declaring inngest_unhealthy"
    alert_route: "grace absorbs the transient; the age gate is the churn backstop"
  - mode: "watchdog itself stops running (workflow disabled / dropped)"
    detection: "missed Sentry check-in on scheduled-inngest-health (margin window)"
    alert_route: "Sentry missed-check-in notification → operator"
  - mode: "workflow heartbeats to a non-existent monitor slug (the #6374 root cause)"
    detection: "sentry-workflow-heartbeat-iac-parity test fails in CI"
    alert_route: "CI red on the PR — structural, pre-merge"
logs:
  where: "GitHub Actions run log (workflow, incl. the hook response body dumped into ::error:: at scheduled-inngest-health.yml:84,91,122 — no SSH); on-host journald: Option A keeps the inngest-inventory tag (ALREADY Better Stack-allowlisted in vector.toml, #5526 — no vector change); Option B MUST add inngest-health to vector.toml SYSLOG_IDENTIFIER + drift fixture or the Better Stack destination is silently dropped; Sentry monitor history"
  retention: "GHA default; Better Stack per retention tier; Sentry monitor check-in history"
discoverability_test:
  command: "gh workflow run scheduled-inngest-health.yml && gh run watch  # then confirm the scheduled-inngest-health monitor shows the check-in in Sentry — NO ssh"
  expected_output: "monitor status transitions ok/error; on inngest_down the operator receives a Sentry email + a [ci/inngest-down] issue within one cadence"
```

## Architecture Decision (ADR/C4)

This is a **monitoring-policy refinement within the existing inngest observability architecture** (ADR-030 self-hosted inngest, ADR-031 Sentry-as-IaC, ADR-033 Inngest-cron substrate) — not a new substrate, tenancy, resolver, or trust boundary. It does not reverse a recorded decision.

- **ADR:** No NEW ADR required (confirmed by architecture review — no new substrate/vendor/trust-boundary/tenancy, reverses no decision). Add a short **amendment note to `ADR-031-sentry-as-iac.md`** recording the GHA-workflow-heartbeat-slug + `-target`-allowlist parity guard (Phase 1.3) — ADR-031 already carries 6+ amendment entries for exactly this class. **ALSO add a one-line amendment to `ADR-030-inngest-as-durable-trigger-layer.md`** recording that the external watchdog now rides the same `/health`/loopback liveness signal ADR-030 defines (Defect 2 moves the authoritative liveness signal onto ADR-030 territory). **Cite ADRs by filename slug, not bare number** — the decisions dir has colliding ordinals (two ADR-030/031/033).
- **C4 views:** No C4 impact. Checked all three model files (`model.c4`, `views.c4`, `spec.c4`) for the external actors/systems/relationships this change could touch: (a) external human actors — none new (operator already modeled as the alert recipient); (b) external systems — Sentry + Better Stack + Inngest-server are already modeled as the observability edge; this change adds no new vendor/integration, only a new monitor resource + a new loopback health probe *inside* the already-modeled host boundary; (c) data stores — none; (d) access relationships — unchanged. A new `sentry_cron_monitor` and an on-host `/health` curl are instances of already-modeled element types, so no `.c4` element/edge/view is added. (Verified at plan time; deepen-plan re-reads the three `.c4` files to confirm before freezing "no C4 impact.")

## Acceptance Criteria

### Pre-merge (PR / CI)
- [ ] `cron-monitors.tf` contains `sentry_cron_monitor "scheduled_inngest_health"` with `name = "scheduled-inngest-health"` matching `scheduled-inngest-health.yml`'s heartbeat `monitor-slug`. (`grep` both; assert equality.)
- [ ] **`apply-sentry-infra.yml` `-target=` allowlist contains `sentry_cron_monitor.scheduled_inngest_health`** (BLOCKER — else the monitor is declared but never applied). `grep` the workflow.
- [ ] Parity test fails when a `.github/workflows/*.yml` heartbeat `monitor-slug` lacks EITHER a matching `sentry_cron_monitor.name` in `cron-monitors.tf` OR an entry in the `apply-sentry-infra.yml` `-target=` list; passes on the current tree. (Verify with a deliberately-broken fixture for each clause.)
- [ ] **Live evidence pulled pre-merge** that a sibling `sentry_cron_monitor` failure actually notified `ops@jikigai.com` (Sentry monitor-notification history) — OR the `sentry_issue_alert` fallback is added. Do not treat "monitor applied" as "operator paged".
- [ ] Liveness probe no longer rides the heavy `eventsV2` read: Option A `INVENTORY_LIVENESS_ONLY` skips eventsV2 (fixture asserts no eventsV2 call) / Option B `inngest-health.sh` exists; either emits pure JSON, enum/count only (no ExecStart/URI/raw GraphQL error). Relevant `.test.sh` green.
- [ ] **`durability_state` preserved:** the liveness body emits the exact enum `durable|degraded|sqlite_only|unknown|absent`; a `degraded` fixture still opens the `[ci/inngest-degraded-durability]` advisory (`:414`) and a `durable` fixture still auto-closes it (`:460`).
- [ ] **Deploy-race tolerance:** a 404/000/non-well-formed probe response classifies `probe_unavailable` and does NOT dispatch a restart; only a well-formed `healthy:false`/missing-`.functions` body → `inngest_down`. (Unit-test with fixtures.)
- [ ] **Restart give-up is age-gated:** dispatch suppressed when the open `[ci/inngest-down]` issue age ≥ GIVE_UP_WINDOW; at give-up the escalation comment REPLACES the "re-dispatched" text and adds the human-attention label. First-failure (no issue) still dispatches once. (Unit-test the age-gate branches — LLM/network out of the assertion path.)
- [ ] Option B ONLY: `push-infra-config.sh` payload + `infra-config-apply.sh` FILE_MAP row + `vector.toml` allowlist + `vector-pii-scrub.test.sh` fixture all updated; `infra-config-apply.test.sh` + vector drift test green.
- [ ] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`). Tests via the package's actual runner (`vitest` for `.ts`; `.test.sh` for shell).
- [ ] Readiness inngest-awareness check added at the deepen-plan-chosen surface; if in `commands/go.md`, it is OUTSIDE the eval-gated routing block.
- [ ] ADR-031 + ADR-030 amendment-log entries added (by filename slug).
- [ ] PR body uses `Ref #6374` (not `Closes`).

### Post-merge (operator/automated)
- [ ] `apply-sentry-infra.yml` auto-applies the new monitor on merge; confirm the `scheduled-inngest-health` monitor exists in Sentry (via monitor list / next heartbeat landing) — automated read, no SSH.
- [ ] The infra-config push delivers `inngest-health.sh` + the `/hooks/inngest-health` hook to prod; confirm `curl https://deploy.soleur.ai/hooks/inngest-health` (HMAC+CF-Access) returns the health JSON — no SSH.
- [ ] Force one `?status=error` (or wait for a genuine miss) and confirm the operator receives the Sentry notification — closes the 14h paging gap.
- [ ] Close #6374 with the Phase-0 false-positive verdict (or annotate if genuinely down).

## Test Scenarios
- **Delivery:** heartbeat slug ↔ monitor parity test red on a broken fixture, green on the tree; monitor error check-in opens a Sentry issue (verified post-merge).
- **False-positive resistance:** `inngest-health.sh` returns `healthy=true` when `/health` is 200 even if a simulated eventsV2 read would fail (fixture: `/health` 200, functions query 200, no eventsV2 call) → watchdog stays green. Contrast: `/health` non-200 → `inngest_down`.
- **Restart cap:** counter increments across simulated runs; dispatch fires for N < CAP, is suppressed + escalates at N == CAP; resets when the issue closes.
- **Readiness:** with a synthetic open `[ci/inngest-down]` issue, the readiness surface emits the advisory; with none, it is silent; the turn is never hard-blocked.

## Alternative Approaches Considered
| Approach | Why not |
| --- | --- |
| Defect 1 via a brand-new Better Stack alert | Reinvents a channel; repo already pages via Sentry (cron monitors + `notify_email`). Root cause is a *missing monitor resource*, not a missing channel. |
| Defect 2 by splitting the inventory hook's liveness out in-place | Invasive to a load-bearing cutover tool (`#6258`/`#5503` invariants). A small dedicated `/health` hook is lower-risk and mirrors 8 sibling hooks. |
| Defect 3 counter in a repo file / GHA cache | GHA is stateless and caches are unreliable/racy; the tracking issue is the natural, already-present, human-visible store. |
| Hard-block the turn on inngest-down (Phase 4) | Over-aggressive — inngest-down doesn't block all work; an advisory respects operator agency. |

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold will fail `deepen-plan` Phase 4.6. (Present and filled above.)
- `commands/go.md` routing block is **eval-gated** (`eval-gate:block:go-routing`); a readiness *advisory* must be additive and outside that block, or CI eval-gate blocks the PR.
- Sentry cron-monitor **paging semantics**: a monitor error/missed check-in pages via the project's monitor-failure notification settings (what 40+ sibling monitors rely on), NOT via the `feature=`-tagged `sentry_issue_alert` rules. Deepen-plan must confirm the operator actually receives the notification; if not, add the tagged-event `sentry_issue_alert` fallback.
- `checkin_margin_minutes` on a `*/15` monitor: too tight false-pages on GHA scheduler jitter (see `scheduled-realtime-probe`'s 1440-min widening for a dropped run), too loose delays detection. Size it from the file's cohort conventions and the 15-min inter-fire gap.
- Test path/runner: verify `apps/web-platform/vitest.config.ts` include globs before placing the parity `.test.ts` (co-located component-style paths are silently skipped); shell tests use the `.test.sh` convention. Typecheck is in-package `tsc`, never `npm run -w`.
- New on-host script MUST honor the inventory hook's webhook-body purity: pure JSON to stdout on success, markers/summary to journald only, enum/count only (no ExecStart/URI/raw GraphQL error).

## Enhancement Summary

**Deepened on:** 2026-07-13
**Sections enhanced:** Infrastructure/Apply-path, Phases 1-3, Files to Edit, Observability, Architecture Decision, Acceptance Criteria
**Review agents used:** observability-coverage-reviewer, architecture-strategist (×2, incl. flow analysis), code-simplicity-reviewer, verification/Explore. All findings code-verified.

### Key improvements (from convergent review)
1. **BLOCKER fixed — apply-target allowlist.** `apply-sentry-infra.yml` uses a `-target=` saved-plan allowlist, NOT an untargeted apply — a new monitor is declared-but-never-applied unless added there. Corrected the false "auto-created" claim; added `apply-sentry-infra.yml` to Files-to-Edit; extended the parity guard to assert the `-target` membership too (else the guard is green while the monitor never applies).
2. **BLOCKER fixed — deploy-race false-positive.** Consumer (repointed workflow) goes live at merge; producer (on-host probe) lands async — a tick in the window would 404 → false `inngest_down` → false restart. Phase 2 now classifies 404/000/non-well-formed as `probe_unavailable` (no restart); only a well-formed down body → `inngest_down`.
3. **Paging path resolved (not deferred).** Verification confirmed (runbook `cloud-scheduled-tasks.md:476-480` + the #4650 precedent) that `sentry_cron_monitor` failures page on their own via `failure_issue_threshold` — no `sentry_issue_alert` needed. Dropped it from default scope; added a PRE-merge live-evidence check that a sibling monitor failure actually emailed the operator.
4. **Defect 2 simplified + durability preserved.** Default is now Option A: an `INVENTORY_LIVENESS_ONLY` mode inside the existing `inngest-inventory.sh` (skip eventsV2, keep functions + `durability_state`) — no new script/hook/payload/vector.toml churn, and it naturally preserves the `steps.probe.outputs.durability_state` wiring the #5553 between-deploy detector + `[ci/inngest-degraded-durability]` auto-close depend on (spec-flow C1-C5). Option B (new hook) retained with its full wiring cost (incl. vector.toml + drift fixture) documented.
5. **Defect 3 redesigned — age gate, not counter.** The body-marker counter had an ordering hazard (dispatch step runs before the issue exists) + RMW clobber/race (spec-flow A1-A7). Replaced with a single-read issue-AGE gate (give up after ~45 min), which sidesteps all of it and self-corrects on recovery.

### New considerations discovered
- Phase 3's churn-cap is contingent on Phase 2's stable probe (a flapping false-positive resets the per-episode age).
- Second restart-dispatch site (`inngest-watchdog-restart-dispatch.yml:49`, #4650 label path) documented as out-of-churn-scope per `hr-write-boundary-sentinel-sweep-all-write-sites`.
- `functions_count==0` needs a cold-start grace/retry before `inngest_unhealthy` to avoid self-perpetuating churn.
- ADRs cited by filename slug (decisions dir has colliding ordinals); add a one-line ADR-030 amendment (liveness now rides `/health`) in addition to the ADR-031 amendment.
- Delivery wiring corrected: `push-infra-config.sh` (payload) + `infra-config-apply.sh` (FILE_MAP) — NOT `infra-config-install.sh`; `apply-deploy-pipeline-fix.yml:407` count guard auto-adjusts.

## Enhancement Summary (deepen-plan)

**Deepened:** 2026-07-13. **Review panel (5 parallel agents):** observability-coverage-reviewer, architecture-strategist (×2: design + workflow-flow), code-simplicity-reviewer, verify-negatives/Sentry-paging researcher. All findings code-verified.

### Blockers fixed inline
1. **`apply-sentry-infra.yml` uses a `-target=` allowlist, not an untargeted apply** — the new monitor would have been declared but NEVER applied (Defect 1 ships unfixed while CI stays green). Added the workflow to Files-to-Edit + required the `-target=` entry AND extended the parity guard to assert allowlist membership. (Architecture Hazard 1.)
2. **Contract-before-consumer deploy race** — the repointed workflow goes live at merge but the on-host probe lands async; a `*/15` tick in the window would 404 → false `inngest_down` → false restart (relocating the very false-positive Defect 2 fixes). Added the `probe_unavailable` classification + "gate restart on a well-formed down body, never a bare non-200" invariant. (Architecture Hazard 2 + observability P1.)

### Simplifications adopted
- **Defect 2 defaults to a liveness-only mode inside the existing `inngest-inventory.sh`** (skip eventsV2, keep functions + `durability_state`) rather than a whole new script/hook/payload/vector.toml/2-test stack. Preserves the `durability_state` wiring for free and needs no Better Stack allowlist change. New-hook route retained as Option B with its full wiring cost made explicit. (Simplicity Q1; the SRP tradeoff from architecture (a) is noted.)
- **Defect 3 uses an issue-AGE gate, not a body-marker counter** — sidesteps the ordering hazard (dispatch step runs before the issue exists), the `gh issue edit --body` RMW clobber/race, and the corrupt-marker fail-safe. One `gh` read, zero writes. (Simplicity Q3 + spec-flow A1-A7.)
- **No belt-and-suspenders `sentry_issue_alert`** — cron-monitor `failure_issue_threshold` paging is documented-to-work (runbook `cloud-scheduled-tasks.md:476-480`; caught the #4650 regression). Kept as a fallback only if pre-merge live evidence can't confirm the notification reaches `ops@`. (Simplicity Q4 + verify agent.)
- **No new parity-test file** — fold the workflow-slug guard into the existing `sentry-monitor-iac-parity.test.ts` (workflow-heartbeat population is one). (Simplicity Q2.)

### New considerations surfaced
- **Durability-surface regression risk (spec-flow C1-C5):** repointing liveness away from the inventory hook silently kills the #5553 between-deploy detector and orphans `[ci/inngest-degraded-durability]` issues unless `durability_state` is preserved in the exact enum and the `:414`/`:460` gates still resolve. Now an explicit invariant + AC.
- **Second restart-dispatch site** (`inngest-watchdog-restart-dispatch.yml:49`, the #4650 label path) documented as out-of-churn-scope (`hr-write-boundary-sentinel-sweep-all-write-sites`).
- **Phase 3 is contingent on Phase 2:** a flapping false-positive defeats a per-episode age gate; only the stable probe truly ends the churn.
- **ADR:** add amendment-log entries to BOTH `ADR-031-sentry-as-iac.md` (parity guard) and `ADR-030-inngest-as-durable-trigger-layer.md` (liveness now rides `/health`); cite by filename slug (ordinal collisions exist).
- **Vendor doc note:** Sentry cron-monitor default-notification routing is NOT in IaC — hence the pre-merge live-evidence AC rather than a blind trust.
