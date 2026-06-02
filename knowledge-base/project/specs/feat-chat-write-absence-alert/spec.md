---
feature: chat-write-absence-alert
issue: 4849
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-06-03
brainstorm: knowledge-base/project/brainstorms/2026-06-03-chat-write-absence-alert-brainstorm.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All infrastructure in this spec is Terraform-routed: a single sentry_issue_alert
     resource in apps/web-platform/infra/sentry/issue-alerts.tf, applied via the
     existing .github/workflows/apply-sentry-infra.yml and gated by sentry-audit-gate.yml.
     There is no manual/operator-driven provisioning step. The deferred follow-up's
     prd-scoped Doppler service token is explicitly out of scope for this PR. -->

# Spec: Chat Write-Absence Liveness Alert

## Problem Statement

The interactive chat write path broke silently for ~3 weeks (migration 059 made
`messages.workspace_id` NOT-NULL + RLS-gated without sweeping the 4 INSERT sites;
a second layer made `template_id` NOT-NULL). No instrumentation fired on the
failure — the only signal was the user reporting a broken chat. The failure's
Sentry signature was present the whole time but buried under unrelated error-noise
and watched by no alert rule (PIR contributing factor 2). We need an alert that
catches a recurrence by instrumentation, not by a user report.

Source PIR: `knowledge-base/engineering/ops/post-mortems/chat-rls-workspace-id-outage-postmortem.md`.

## Goals

- Fire an operator-paging alert when interactive chat insert failures occur, so a
  write-path outage is caught within the alert window rather than after weeks.
- Reuse the existing code-managed Sentry alert substrate (`issue-alerts.tf`);
  no new prod-read infrastructure, no UI-only configuration.
- Guarantee no user content / raw `workspace_id` / email leaves the system in any
  alert payload.

## Non-Goals

- A scheduled prod write-absence probe querying `messages` (the issue's Option A).
  Deferred to a follow-up issue — needs a prd-scoped read token, a SECURITY
  DEFINER RPC, and an out-of-band attempt signal; not justified at 0–1 users.
- Per-workspace alerting / per-workspace baselines. Global aggregate only for MVP.
- Time-based silence detection ("zero writes in N hours"). Rejected in favor of
  the failure-signal approach (no idle false positives).

## Infrastructure (IaC)

This feature is delivered entirely as Infrastructure-as-Code — no manual steps:

- **Resource:** one new `sentry_issue_alert` in
  `apps/web-platform/infra/sentry/issue-alerts.tf`, modeled on the code-managed
  `byok_*` resources (full `filters_v2`, not the import-only `auth_*` shape).
- **Apply path:** `.github/workflows/apply-sentry-infra.yml` (the existing Sentry
  Terraform apply workflow); change must pass `.github/workflows/sentry-audit-gate.yml`.
- **No new credentials or servers.** The prd-scoped read-only Doppler service
  token (`prd_scheduled`) needed by the deferred probe is explicitly out of scope
  here and will be provisioned (as IaC + a separate-terminal `gh secret set`,
  per `hr-never-paste-secrets-via-bang-prefix`) only if/when that follow-up ships.

## Functional Requirements

- **FR1** — Add one `sentry_issue_alert` resource in
  `apps/web-platform/infra/sentry/issue-alerts.tf` that triggers on Sentry events
  tagged `op == "persist-user-message"` (the slug `CC_OP_SLUGS.persistUserMessage`
  emitted at `apps/web-platform/server/cc-dispatcher.ts:1502` via
  `reportSilentFallback`). Follow the code-managed `byok_*` pattern.
- **FR2** — The alert uses an `EventFrequencyCondition` window/count tuned to page
  on a sustained failure run while tolerating a single transient blip (plan-time
  tuning; see Open Question 1). It routes to the same operator-paging action
  target the existing `byok_*` / `auth_*` alerts use (reuse, do not invent).
- **FR3** — A regression test asserts that an interactive `messages` insert
  failure (`insertErr` set) emits a Sentry capture tagged `op:persist-user-message`.
  This pins the alert's only input against a future dispatch refactor that could
  silently drop the tag. Pairs with the #4831 grep-sweep guard test.
- **FR4** — No alert payload (Sentry event, any downstream channel) carries a raw
  `workspace_id` (== `owner_user_id` for solo workspaces, ADR-038 N2), message
  content, or user email. Rely on the existing Sentry userId pseudonymization
  path (PR #3696).

## Technical Requirements

- **TR1** — The alert change is applied via `apply-sentry-infra.yml` and must pass
  `sentry-audit-gate.yml`. No Sentry UI clicks.
- **TR2** — Discriminate the failure class by the `pg_code` Sentry tag where useful
  (`42501` = RLS reject, `23502` = NOT-NULL violation), both emitted by
  `reportSilentFallback` (`observability.ts:197`).
- **TR3** — Observability-as-plan-quality: the alert's firing path and the
  op-emission test must be reachable/verifiable without SSH
  (`hr-no-ssh-fallback-in-runbooks`, `hr-observability-layer-citation`).

## Deferred (follow-up issue)

Scheduled prod write-absence probe: a `scheduled-*` GHA + SECURITY DEFINER
aggregates-only RPC (`find_write_silent_workspaces`, returning `count` +
`max(created_at)` only, never the 13 `MESSAGE_REDACT_FIELDS` columns), gated on
out-of-band `user_concurrency_slots.last_heartbeat_at` to avoid idle false
positives, run with a dedicated prd-scoped read-only Doppler service token
(`prd_scheduled` config). Enumerate via `SELECT DISTINCT workspace_id FROM
conversations`; filter interactive rows via `role='user' AND source IS NULL`.
Mirror `scheduled-realtime-probe.yml`. Article 30 PA-2 TOM note (one line), not a
new processing-activity row.

## Acceptance Criteria

- AC1 — `terraform plan` on `issue-alerts.tf` shows exactly one new
  `sentry_issue_alert`; `sentry-audit-gate.yml` passes.
- AC2 — The op-emission regression test (FR3) fails if the `op:persist-user-message`
  tag is removed from the insert-failure path, and passes on `main`'s current
  dispatcher.
- AC3 — Review confirms no raw `workspace_id` / content / email in the alert
  definition or any payload template.
- AC4 — A follow-up issue exists for the deferred scheduled probe.
