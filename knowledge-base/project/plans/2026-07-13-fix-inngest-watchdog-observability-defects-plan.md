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
2. **Structural guard (fold-in, do not defer):** add a parity test asserting every `sentry-heartbeat` `monitor-slug:` used by a `.github/workflows/*.yml` has a matching `sentry_cron_monitor.name` in `cron-monitors.tf`. This is the GHA-workflow counterpart to `sentry-monitor-iac-parity.test.ts` (which covers only `server/inngest/functions/`). Makes "heartbeat into the void" structurally impossible for future workflows.
3. Confirm the failure path pages: cron-monitor failures notify project members by default (same mechanism 40+ sibling monitors rely on). If deepen-plan finds cron-monitor paging is insufficient in this project's config, add a belt-and-suspenders `sentry_issue_alert` (a tagged Sentry EVENT from the workflow via the ingest API + a `feature=inngest-watchdog`/`op=inngest-down` `notify_email` rule) — decided in deepen-plan, not pre-committed.

### Phase 2 — Defect 2: true liveness probe (decouple from the eventsV2 read path)
1. Add on-host `apps/web-platform/infra/inngest-health.sh` (mirrors `inngest-registry-probe.sh` structure + `#5503` journald-only purity): curl `http://127.0.0.1:8288/health` (the ci-deploy HARD gate) with a short `--max-time`; optionally the lightweight `/v0/gql { functions { id } }` query (NOT the eventsV2 scan) to distinguish "process up but API degraded"; emit a small pure-JSON body `{ healthy: bool, functions_count: int, durability_state: <enum> }` (reuse `derive_durability_state` — a cheap `systemctl` read). Enum/count only; never ExecStart/URI/raw error text.
2. Register a `/hooks/inngest-health` webhook in `hooks.json.tmpl` + wire its `inngest_health_sh_b64` payload through the infra-config push (mirrors the 8 existing inngest hooks). Delivered via the immutable infra-config path (`hr-prod-host-config-change-immutable-redeploy`) — no SSH.
3. Repoint the watchdog's **liveness** verdict (`scheduled-inngest-health.yml` probe step) from `/hooks/inngest-inventory` to `/hooks/inngest-health`. Keep the 3× retry resilience. `healthy=false`/non-200 → `inngest_down`; `functions_count==0` on a live server → `inngest_unhealthy`. Move the `durability_state` read to the health hook (or keep both — deepen-plan decides). The heavy `inngest-inventory` hook reverts to **cutover-baseline only** and is no longer a liveness gate.
4. Update `inngest-inventory.test.sh`/add `inngest-health.test.sh` fixtures for the new script.

### Phase 3 — Defect 3: cap the restart loop + escalate
1. Persist a restart counter across stateless `*/15` runs using the open `[ci/inngest-down]` tracking issue as the store: a `<!-- restart-dispatch-count: N -->` marker in the issue body (or count restart-dispatch comments), incremented each dispatch.
2. Gate the "Auto-dispatch inngest restart" step on `N < RESTART_CAP` (e.g. 3). At/after the cap, **stop dispatching** and escalate: post a loud "restarts exhausted — manual/root-cause needed" comment, keep the Sentry error heartbeat firing (Phase 1 keeps paging), and label the issue for human attention. Reset is automatic — recovery auto-closes the issue (`:378-405`), so the next incident opens a fresh issue with N=0.
3. Ensure `restart-inngest-server.yml` dispatch remains excluded for pool modes (already correct, `:275-278`) — do NOT widen.

### Phase 4 — Readiness-gate inngest awareness
1. Add a cheap `[ci/inngest-down]`-open-issue awareness check to the readiness surface the operator's turn-1 actually hits. Concrete candidates (deepen-plan DECIDES; default target = the surface that already runs a prod-facing check): (a) `postmerge/SKILL.md` prod-health verification; (b) an additive advisory in `commands/go.md` / `one-shot` Step 0 readiness preamble. Check = `gh issue list --label ci/inngest-down --state open` (+ optionally probe `/hooks/inngest-health`) → surface a one-line advisory, do NOT hard-block the turn.
2. **Eval-gate guard:** if the insertion point is `commands/go.md`, keep the addition OUTSIDE the eval-gated routing block (`eval-gate:block:go-routing`) — an additive readiness advisory, not a routing change.

### Phase 5 — Tracking issues & #6374 disposition
- Reference #6374 with `Ref #6374` in the PR body (NOT `Closes` — the monitor + health hook apply **post-merge** via `apply-sentry-infra.yml` + the infra-config push; `Closes` would false-resolve at merge before the fix is live — `wg-use-closes-n-in-pr-body-not-title-to` / ops-remediation Sharp Edge).
- Post-merge: after the monitor is applied and the health hook is live, close #6374 with the false-positive verdict from Phase 0 (or leave open with a note if inngest was genuinely down).
- File a tracking issue only for any sub-scope deepen-plan/plan-review defers (none anticipated; the parity guard and readiness check are folded in). #6178 (extract inngest to HA host) already exists — this plan is its observability counterpart, not the extraction.

## Files to Edit
- `.github/workflows/scheduled-inngest-health.yml` — repoint liveness to `/hooks/inngest-health` (Defect 2); add restart-cap + escalate logic (Defect 3).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `scheduled_inngest_health` monitor (Defect 1).
- `apps/web-platform/infra/hooks.json.tmpl` — register `/hooks/inngest-health` + `inngest_health_sh_b64` payload (Defect 2).
- `apps/web-platform/infra/infra-config-apply.sh` (+ `.test.sh`) — wire the new script's base64 payload delivery (mirror existing inngest hooks).
- `apps/web-platform/infra/infra-config-install.sh` (if it installs hook scripts) — install `inngest-health.sh`.
- `plugins/soleur/skills/postmerge/SKILL.md` **or** `plugins/soleur/commands/go.md` / `plugins/soleur/skills/one-shot/SKILL.md` — readiness inngest-awareness check (Phase 4; surface decided in deepen-plan).

## Files to Create
- `apps/web-platform/infra/inngest-health.sh` — lightweight on-host `/health` liveness probe (Defect 2).
- `apps/web-platform/infra/inngest-health.test.sh` — unit fixtures for the health script.
- `apps/web-platform/test/server/inngest/sentry-workflow-heartbeat-iac-parity.test.ts` (or a `.test.sh` under `apps/web-platform/test/`) — GHA-workflow-heartbeat-slug ↔ monitor parity guard (Phase 1.2). Runner/path per the repo's discovery globs (verify `vitest.config.ts` include globs before choosing the path).

## Open Code-Review Overlap
None. (`gh issue list --label code-review --state open` scanned against the file list above at plan time; no open scope-out touches these files. Re-verify at Step 2 of deepen-plan.)

## Domain Review

**Domains relevant:** none

No cross-domain (product/marketing/sales/finance/legal/ops/support) implications — this is an infrastructure/observability change (CI workflows, Terraform monitor, on-host health script, a readiness-skill edit). Engineering/CTO concerns are captured inline in Risks and the Architecture Decision section. No UI surface (no files under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`) → Product/UX Gate = NONE.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf`: add one `sentry_cron_monitor "scheduled_inngest_health"`. Provider `jianyuan/sentry` (pinned, existing). No new sensitive variables — uses existing `var.sentry_org` + `data.sentry_project.web_platform`.

### Apply path
- **cloud-init + auto-apply.** `apply-sentry-infra.yml` fires on merge to `main` touching `cron-monitors.tf` (`:46`) and applies the untargeted cron+uptime monitor scope — the new monitor is created automatically, **no operator step**. Blast radius: additive (one new monitor); zero downtime.
- The `/hooks/inngest-health` hook + `inngest-health.sh` land via the **infra-config push** (immutable-redeploy path, `hr-prod-host-config-change-immutable-redeploy`) — base64 payload → `hooks.json` + on-host script, no SSH. Same delivery as the 8 existing inngest hooks.

### Distinctness / drift safeguards
- New monitor is apply-created (not import-only), so it needs no `lifecycle.ignore_changes` beyond sibling convention; adopt whatever the two most-recent cron-monitor blocks use.
- The GHA-workflow-heartbeat parity test (Phase 1.2) is the drift safeguard: a workflow heartbeat slug without a monitor fails CI.

### Vendor-tier reality check
- Sentry Crons monitors are in-tier (40+ already provisioned). No paid-tier gate. `notify_email` (the repo's paging convention) is in-tier.

## Observability

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
  - mode: "restart loop exhausted (N failed restarts didn't clear)"
    detection: "restart-dispatch counter on the tracking issue >= RESTART_CAP"
    alert_route: "loud escalation comment + human-attention label; Sentry error heartbeat keeps paging"
  - mode: "watchdog itself stops running (workflow disabled / dropped)"
    detection: "missed Sentry check-in on scheduled-inngest-health (margin window)"
    alert_route: "Sentry missed-check-in notification → operator"
  - mode: "workflow heartbeats to a non-existent monitor slug (the #6374 root cause)"
    detection: "sentry-workflow-heartbeat-iac-parity test fails in CI"
    alert_route: "CI red on the PR — structural, pre-merge"
logs:
  where: "GitHub Actions run log (workflow); on-host journald tag inngest-health (→ Better Stack via Vector allowlist, mirror inngest-inventory's #5526 allowlisting); Sentry monitor history"
  retention: "GHA default; Better Stack per retention tier; Sentry monitor check-in history"
discoverability_test:
  command: "gh workflow run scheduled-inngest-health.yml && gh run watch  # then confirm the scheduled-inngest-health monitor shows the check-in in Sentry — NO ssh"
  expected_output: "monitor status transitions ok/error; on inngest_down the operator receives a Sentry email + a [ci/inngest-down] issue within one cadence"
```

## Architecture Decision (ADR/C4)

This is a **monitoring-policy refinement within the existing inngest observability architecture** (ADR-030 self-hosted inngest, ADR-031 Sentry-as-IaC, ADR-033 Inngest-cron substrate) — not a new substrate, tenancy, resolver, or trust boundary. It does not reverse a recorded decision.

- **ADR:** No NEW ADR required. Add a short **amendment note to ADR-031 (Sentry-as-IaC)** recording that GHA-workflow heartbeat slugs are now parity-guarded (Phase 1.2) — the same "silent unknown-slug drop" class ADR-031 already governs for Inngest functions. Deepen-plan/plan-review confirms whether an amendment vs. a one-line ADR reference is warranted.
- **C4 views:** No C4 impact. Checked all three model files (`model.c4`, `views.c4`, `spec.c4`) for the external actors/systems/relationships this change could touch: (a) external human actors — none new (operator already modeled as the alert recipient); (b) external systems — Sentry + Better Stack + Inngest-server are already modeled as the observability edge; this change adds no new vendor/integration, only a new monitor resource + a new loopback health probe *inside* the already-modeled host boundary; (c) data stores — none; (d) access relationships — unchanged. A new `sentry_cron_monitor` and an on-host `/health` curl are instances of already-modeled element types, so no `.c4` element/edge/view is added. (Verified at plan time; deepen-plan re-reads the three `.c4` files to confirm before freezing "no C4 impact.")

## Acceptance Criteria

### Pre-merge (PR / CI)
- [ ] `cron-monitors.tf` contains `sentry_cron_monitor "scheduled_inngest_health"` with `name = "scheduled-inngest-health"` matching `scheduled-inngest-health.yml`'s heartbeat `monitor-slug`. (`grep` both; assert equality.)
- [ ] New parity test fails when a `.github/workflows/*.yml` `sentry-heartbeat` `monitor-slug` has no matching `sentry_cron_monitor.name`; passes on the current tree. (Verify with a deliberately-broken fixture.)
- [ ] `inngest-health.sh` exists, is executable, emits pure JSON on the success path (no non-JSON to stdout/stderr — mirror the inventory-hook webhook-body contract), and emits enum/count only (no ExecStart string, no URI, no raw GraphQL error). `inngest-health.test.sh` green.
- [ ] `scheduled-inngest-health.yml` liveness probe targets `/hooks/inngest-health` (not `/hooks/inngest-inventory`); the heavy `eventsV2` read path is no longer on the liveness verdict.
- [ ] Restart-dispatch step is gated on a restart counter `< RESTART_CAP`; at the cap it escalates (loud comment + human-attention label) and does NOT dispatch. (Unit-test the counter parse/increment + the cap branch with fixtures — the LLM/network is out of the assertion path.)
- [ ] `hooks.json.tmpl` + infra-config payload wiring register `inngest-health` following the existing inngest-hook pattern; `infra-config-apply.test.sh` green.
- [ ] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`). Tests via the package's actual runner (`vitest` for `.ts`; `.test.sh` for shell).
- [ ] Readiness inngest-awareness check added at the deepen-plan-chosen surface; if in `commands/go.md`, it is OUTSIDE the eval-gated routing block.
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
