---
title: "ADR-031 — Sentry alert and cron monitor configuration as IaC"
status: accepted
date: 2026-05-15
plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
spec: knowledge-base/project/specs/feat-sentry-monitors-alerts-adapt/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-15-sentry-monitors-alerts-adaptation-brainstorm.md
issue: 3814
supersedes: none
related:
  - ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md
  - ADR-029-rename-at-boundary-userid-pseudonymisation.md
  - ADR-030-multi-tenant-deploy-substrate.md
---

# ADR-031 — Sentry alert and cron monitor configuration as IaC

## Status

Accepted (2026-05-15).

## Context

Sentry split "Alerts" into **Monitors** (detection) and **Alerts** (routing) in
2026. Vendor's "no action required" advisory is rejected because:

1. **Auto-migration risk.** A pre-2026 Metric Alert and its routing rule may
   have decoupled, leaving threshold breaches with no paging path. Brand-survival
   threshold is `single-user incident` per the plan's User-Brand Impact section.
2. **Article 30 inventory drift.** New monitor classes (log-condition,
   custom-metric, span-attribute) push past the existing PA8 §(c) inventory
   unless explicitly enumerated and carved out.
3. **Scheduled-workflow detection gap.** 35 scheduled GitHub Actions workflows
   currently have zero "did this run?" detection. #3236 enumerates 5
   secret-touching workflows whose silent failure breaches the threshold.

The starting point is `apps/web-platform/scripts/configure-sentry-alerts.sh`
(176 lines, idempotent, env-var-driven) — a hand-rolled REST upserter for the
4 auth observability issue-alert rules. The script works but cannot model the
new monitor types and offers no drift detection for the rules it manages.

## Decision

Adopt Sentry as Infrastructure-as-Code via the `jianyuan/terraform-provider-sentry`
provider, scoped to:

- **Import** the 4 existing `auth-*` issue-alert rules into Terraform state
  using `terraform import` — names match `configure-sentry-alerts.sh`
  byte-for-byte to preserve operator dashboard queries.
- **Create** 9 net-new `sentry_cron_monitor` resources, one per scoped
  scheduled workflow, with vendor-hosted heartbeat via the existing Sentry
  trust boundary (closes #3236).
- **Defer** migration from `sentry_issue_alert` (deprecated in v0.15-beta) to
  the new unified `sentry_alert` resource until provider GA.
- **Defer** enabling new monitor classes (log-condition, custom-metric) until
  `apps/web-platform/server/sentry-scrub.ts` is extended to cover their event
  channels — enforced by Phase 6 GDPR-gate + AC9.

### Provider source

`jianyuan/sentry` v0.15.0-beta2 (released 2026-05-06). The competing
`getsentry/sentry` is a stale fork (last push 2024-06-24). Pinned to the exact
beta version; re-evaluate on first stable v0.15.0 release. **If the PR sits
open for >2 weeks, re-run Phase 0.1 of the plan** before merge.

### Per-app root

New Terraform root at `apps/web-platform/infra/sentry/`, sibling to the main
`apps/web-platform/infra/` root. Same R2 backend bucket, distinct state key
`web-platform/sentry/terraform.tfstate`. `use_lockfile = false` per R2's lack
of S3 conditional writes — same posture as the main root.

### Authentication / secret-store divergence

Sentry secrets stay in **GitHub repository secrets**, not Doppler:

- `SENTRY_AUTH_TOKEN` — provider auth, used by `terraform plan|apply`.
- `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` —
  DSN-derived (see plan Phase 0.8), consumed by the per-workflow check-in
  steps. Not read by Terraform.

This diverges from spec TR2 (which assumed Doppler). Rationale: keeping the
Sentry vendor's existing wiring contract uniform with the GitHub-Actions
runtime where the workflows execute reduces moving parts. R2 backend creds
remain in Doppler `prd_terraform` per the existing pattern in
`scheduled-terraform-drift.yml:54-65`.

### Local-token source for operator runs

GitHub Actions exposes secret VALUES only inside workflow steps. For local
execution (Phase 2.1 audit, Phase 5 import), the operator uses a personal
**Sentry user token** from `https://de.sentry.io/settings/account/api/auth-tokens/`
with scope `project:read` + `monitor:read` (audit) and `project:write` (import).
The token is never persisted to Doppler or committed.

### DE region support

Provider docs do not enumerate `de.sentry.io`; base_url override is inferred.
Phase 0.1.5 of the plan validates DE region support against a scratch project
**before** committing the provider config. If it fails, the escape hatch
below applies.

### Auto-apply on push-to-main (cron monitors only)

`.github/workflows/apply-sentry-infra.yml` fires on push to `main` when
`apps/web-platform/infra/sentry/cron-monitors.tf` changes. It runs
`terraform apply -target=sentry_cron_monitor.* -auto-approve` so the 9
monitors exist within ~2 minutes of merge, closing the window where check-in
curls would 404. Issue-alert resources stay import-only post-merge per AC13.

## Consequences

### Positive

- **Deterministic state.** The 4 issue-alert rules' configuration is now
  expressible in code; drift is detectable via `terraform plan` and routable
  through the existing `scheduled-terraform-drift.yml` matrix (follow-up).
- **Vendor-hosted heartbeat.** Closes #3236 without standing up a separate
  cron-pinger service or changing CI infrastructure.
- **Import-not-recreate posture.** Imports preserve operator-keyed names
  byte-for-byte; Phase 0.5 grep verifies post-merge invariance.

### Negative

- **Beta-provider risk.** v0.15.0-beta2 may yank or change `*_v2` attribute
  shapes. Mitigated by exact-version pin + `lifecycle.ignore_changes` on
  `[conditions_v2, filters_v2, actions_v2, environment, frequency]` for the
  4 imported rules. Re-evaluate at first stable v0.15.0.
- **Dual secret-store posture.** Operators must remember Sentry secrets are
  in GH Actions, not Doppler. Mitigated by README.md cheatsheet at the root.
- **Scope leakage risk.** Future "while we're here" PRs may try to migrate to
  `sentry_alert` (the new beta unified resource) prematurely. NG9 of the plan
  explicitly forbids this until provider GA.

## Escape hatches

If any of the following triggers fire, revert Phase 5 of #3814:

- **DE region smoke test fails.** Phase 0.1.5 does not return a non-empty
  `data.sentry_organization.this.internal_id` against the scratch project.
- **terraform plan shows non-trivial drift on >1 of 4 imported rules.**
  v2-attribute drift is expected and handled by `ignore_changes`; novel
  drift (e.g., the provider rejecting our `name` field) is not.
- **3+ retries fail on `terraform import`** — the provider's import handler
  is incompatible with our rule shape.

Escape-hatch action: leave `configure-sentry-alerts.sh` as source of truth,
mark this ADR `status: rejected`, revert the `apps/web-platform/infra/sentry/`
directory and `.github/workflows/apply-sentry-infra.yml`, and re-evaluate
on next provider release.

## Validation gate

This ADR is validated by:

- **AC7:** `terraform fmt -check` clean; `terraform init -backend=false &&
  terraform validate` passes.
- **AC13:** First `terraform import` of all 4 rules followed by `terraform plan`
  is no-op (modulo lifecycle-ignored v2 drift).
- **AC14/AC15:** API-GET (per `hr-no-dashboard-eyeball-pull-data-yourself`)
  confirms the 9 cron monitors exist and the first scheduled run of each
  workflow produces a recognized check-in.
- **AC16:** One full `reusable-release.yml` cycle ships under Terraform
  management with the audit artifact uploaded.

## DHH dissent (kept for re-evaluation)

DHH-style review at plan time argued for cutting Phase 5 entirely: leave the
working 176-line script alone for 4 unchanging rules; wait for a second
Sentry change before paying IaC ceremony. The decision rejected this for the
current PR because (a) #3815 multi-tenant DPA work assumes the IaC foundation,
(b) the 9-workflow Crons scope closes #3236 independently. **Re-evaluate
trigger:** if the escape-hatch criteria above fire, the dissent becomes the
operative reframe.

See plan §"Open Questions" OQ4 for the full dissent text and re-evaluation
criteria.
