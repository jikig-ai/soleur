---
title: zot mirror-fallback alarm — unreachable threshold fix
issue: 6285
branch: feat-6285-zot-metric-alert
pr: 6424
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-15-zot-fallback-alarm-threshold-brainstorm.md
status: draft
created: 2026-07-15
---

# Spec — zot mirror-fallback alarm threshold fix (#6285, re-scoped)

## Problem Statement

`sentry_issue_alert.zot_mirror_fallback_rate` (`apps/web-platform/infra/sentry/issue-alerts.tf:1368`)
**cannot fire on its primary signal.**

- `ci-deploy.sh:607` embeds the unique deploy tag in the Sentry message
  (`"image pulled from " + $reg + " (" + $img + ":" + $t + ")"`), so **every deploy mints a fresh
  issue-group**.
- The pull fleet is **two hosts** (`var.web_hosts`: `web-1`/hel1, `web-2`/fsn1); the inngest image
  has one (`inngest-host.tf:181`).
- `event_frequency { comparison_type = "count", value = 3, interval = "1h" }` fires at **>=4
  events in one group**.
- **A total zot outage during a rolling deploy emits 2 events into a fresh group → no page.**

The resource comment justifies `value = 3` with *"a rolling-deploy zot miss drives many hosts onto
the SAME group"*. There are no "many hosts", and the group is not shared across deploys.

#6285 originally proposed upgrading to `sentry_metric_alert` at `alert_threshold=3`. That would be
**equally dead** (a total outage across web+inngest aggregates to 2), and its stated blocking
rationale is factually false (see Non-Goals / brainstorm Key Decisions 3-4).

## Goals

- **G1** — Make the alarm fire on **any** zot mirror fallback: `event_frequency.value` `3` → `0`.
- **G2** — Correct the false "many hosts" justification comment to state the real grouping and
  fleet arithmetic, so the next reader cannot re-derive the same wrong threshold.
- **G3** — Amend `ADR-096:103-106`, whose sensitivity note rests on the same false premise and
  defers to #6285.
- **G4** — Close the `sentry_metric_alert` upgrade idea on #6285 with the verified rationale.

## Non-Goals

- **NG1** — **No `sentry_metric_alert`.** Its selling point (fingerprint-independence) is what
  `value = 0` delivers. Re-opening requires new evidence.
- **NG2** — **No `data "sentry_team"`.** Empirically **403s at plan time** (verified this
  session); the `iac-terraform-prd` token has no `team:read`. It would wedge every future
  `apply-sentry-infra` run.
- **NG3** — **No `target_type = "Member"` pinning.** Blocked operationally (no `member:read`) and
  bounded legally (CLO: Art. 5(1)(c) — a member id is Art. 4(1) personal data; this repo is
  public; a Team target routes identically with zero personal data).
- **NG4** — **No migration to `sentry_alert`** (the deprecation `terraform validate` surfaces).
  ADR-031 **NG9** forbids it until provider GA.
- **NG5** — No roadmap `phase 4` drift fix here (routes through the `roadmap-review` cron).
- **NG6** — Spin-offs are **filed, not fixed**, in this change.

## Functional Requirements

- **FR1** — `event_frequency.value` = `0` on `sentry_issue_alert.zot_mirror_fallback_rate`, so any
  issue-group with >=1 matching event pages, independent of fingerprinting.
- **FR2** — The threshold comment states the **mechanism** (message embeds the unique deploy tag →
  fresh issue-group per deploy → the per-group count is bounded by fleet size, not a rate), the
  **invariant** (any `value > 0` is fleet-shape-dependent and silently unreachable whenever the
  per-group count cannot exceed it; `value = 0` is the only fleet-independent setting), the
  **sibling contrast** (`web_terminal_boot_fatal`'s `value = 1` works only on an always-hot group),
  and a **change-trigger**. It must contain **NO host count** — a count rots the day web-3 lands,
  which is exactly how the original comment rotted. *(Revised — v1 of this spec demanded "fleet = 2
  hosts → max 2 events/group", i.e. the very rot the plan forbids.)*
- **FR3** — `ADR-096` amended: the window **opens at task 1.8** (`ZOT_REGISTRY_URL` set in Doppler
  `prd`) for **3 of the 4 signals** — `zot-gate-degraded` fires where `ZOT_ACTIVE` stays 0, and the
  two cloud-init fresh-boot signals gate on `ZURL` + probe with no `ZOT_ACTIVE` at all; only
  `registry:ghcr-fallback` requires the flip. It **closes at task 5.3** for those three (5.3 deletes
  **three** fallback branches across two files); `zot-gate-degraded` survives, so 5.3 must **narrow**
  the alarm's `filters_v2`, never retire it. Also correct the false `betteruptime_heartbeat.registry_prd`
  zot-liveness claim (zero consumers, `paused = true`) and remove the "deferred to #6285" clause.
  *(Revised — v1 of this spec said the window is the `ZOT_ACTIVE=1` soak and that all four signals go
  dark at 5.3. Both false; see the plan's v2 header.)*
- **FR4** — #6285 updated + closed with the verified findings; four spin-off issues filed.

## Technical Requirements

- **TR1 (BLOCKING — verify before relying on FR1)** — **Confirm Sentry accepts
  `event_frequency.value = 0` server-side.** `terraform validate` passes (plain `number`, no
  minimum) but **there is no in-repo precedent**: the only fire-on-first rule
  (`web_terminal_boot_fatal`, `:1462`) uses `value = 1`, which works **only** because its group is
  always-hot; on a fresh group `value = 1` means ">1" and a single event does **not** fire.
  If Sentry rejects `0`, **stop and escalate** to the corrected metric alert (threshold 0, pinned
  literal team id `4511404939411536` + an audit-gate drift check, plus the `-target` artifact).
- **TR2** — Read-only verification uses `SENTRY_IAC_AUTH_TOKEN` from Doppler `prd_terraform`
  (**it is there** — ADR-031:185 mirrors it for exactly this). Scopes:
  `[alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write]`.
- **TR3** — **No new resource type**, so the 4 guard artifacts are untouched
  (`destroy-guard-filter-sentry.jq`, `test-destroy-guard-sentry-scope-guard.sh`,
  `test-destroy-guard-counter-sentry.sh`, `apply-sentry-infra.yml` `-target=`). An in-place
  attribute change is not a resource delete → no `[ack-destroy]` needed. **Verify** the existing
  `-target=sentry_issue_alert.zot_mirror_fallback_rate` line (`apply-sentry-infra.yml:265`) is
  present so the change actually applies.
- **TR4** — **Any synthetic live-fire verification MUST run pre-cutover.** A burst carrying
  `registry:"ghcr-fallback"` is counted by `zot-soak-6122.sh:57,71-73`, which FAILs on >=1 — it
  would manufacture a false FAIL on the gate that decides GHCR retirement.
- **TR5** — Preserve `frequency = 23` (re-notification throttle) and the `lifecycle.ignore_changes`
  block (`:1428`).

## Acceptance Criteria

- [ ] TR1 verified: Sentry accepts `value = 0` (or escalation triggered).
- [ ] FR1 applied; `terraform plan` clean; the live rule reflects the new threshold.
- [ ] FR2 comment replaces the false "many hosts" justification.
- [ ] FR3 ADR-096 amended.
- [ ] FR4 #6285 closed with rationale; 4 spin-offs filed.
- [ ] No guard artifact regressions.
