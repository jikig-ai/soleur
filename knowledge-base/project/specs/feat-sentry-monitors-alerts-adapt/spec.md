---
feature: sentry-monitors-alerts-adapt
date: 2026-05-15
status: draft
brand_survival_threshold: single-user incident
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-05-15-sentry-monitors-alerts-adaptation-brainstorm.md
related_issues: [3814, 3815]
---

# Feature: Adapt Sentry Integration to Monitors/Alerts Split

## Problem Statement

Sentry (2026) split "Alerts" into **Monitors** (detection across span attributes, logs, custom metrics, crons, uptime — creates issues automatically) and **Alerts** (routing only — Slack/email/PagerDuty; one alert connects to many monitors). Existing Metric Alerts auto-migrated; existing alert rules preserved as routing-only. Vendor claim is "no action required."

Soleur cannot accept that claim at face value:

- **Trip-wire.** Auto-migration may have orphaned a pre-2026 Metric Alert from its paired routing rule. Threshold breaches would stop paging on-call. Cannot be confirmed from a dashboard skim — silent until a P1 issue stops paging. Single-user incident threshold breached on first miss.
- **PII boundary.** New monitor types (log-condition monitors, custom-metric monitors) would materially expand data classes ingested into Sentry, breaching the current Article 30 §(c) inventory and the multi-layer scrub posture (`apps/web-platform/server/sentry-scrub.ts`, `apps/web-platform/sentry.client.config.ts` `stripUserContextFromEvent`).
- **Detection gap.** Scheduled GitHub Actions (daily community digest, scheduled triage) have no "did this run?" detection. Sentry Crons now lives in the Monitors tab and unlocks this cheaply.
- **Drift posture.** Today the 4 alert rules are provisioned by `apps/web-platform/scripts/configure-sentry-alerts.sh`, a bash script with hardcoded thresholds. Rules themselves live in the Sentry dashboard — script-as-code but not IaC. No drift detection, no peer review on threshold changes, no ADR-anchored history.

## Goals

- **G1.** Verify Sentry's auto-migration left every Metric Alert with a paired routing rule. Snapshot evidence retained as Article 30 audit artifact.
- **G2.** Update the legal corpus (Art. 30 register §(c), DPD §2.3(m), Privacy Policy §5.10, GDPR Policy operational-telemetry entry) to explicitly disclose what new monitor classes do — and do not — process. Carve-out: **we do not enable Sentry log ingestion.**
- **G3.** Wire Sentry cron monitors to the scheduled GitHub Actions workflows currently lacking "did this run?" detection (daily community digest, scheduled triage, any other `cron:` workflow under `.github/workflows/`).
- **G4.** Migrate alert-rule provisioning from `configure-sentry-alerts.sh` to a `terraform/sentry/` root using the `getsentry/sentry` provider. **Import existing rules — do not recreate.**
- **G5.** Land an ADR per `hr-every-new-terraform-root-must-include-an` for the Sentry IaC adoption.
- **G6.** Pass `/soleur:gdpr-gate` on the implementation diff.

## Non-Goals

- **NG1.** Productizing observability for Soleur users (`/soleur:monitor` skill, multi-tenant alert delivery, Soleur-hosted dashboard). CPO assessment: zero demand-signal; roadmap row 4.9 already gates on 10+ users. Revisit trigger: 3+ Phase 4 founders pull for it.
- **NG2.** Enabling Sentry **log-condition monitors.** Requires extending `apps/web-platform/server/sentry-scrub.ts` to cover the `logs` event channel; out of this scope. Tracked separately if pulled for.
- **NG3.** Enabling **span-attribute or custom-metric monitors** speculatively. Let real incident pressure pull new types.
- **NG4.** Refactoring `reportSilentFallback` / `warnSilentFallback` / `mirrorP0Deduped` / `mirrorCrossTenantViolation` helpers. The Monitors/Alerts split is server-side; application emit code is unaffected. Touching these risks regressing dashboard-keyed message strings (see `helper-migration-must-preserve-operator-dashboard-message-strings` learning).
- **NG5.** Migrating `qa` / `postmerge` skill Sentry API queries pre-emptively. Wait for concrete breakage.
- **NG6.** Adding Sentry source-map upload to CI. Separate gap surfaced by repo-research; not Monitors-related.
- **NG7.** Adopting a single shared Sentry org for multiple Soleur-managed tenants. Multi-tenant DPA clause (CLO M-delta) is tracked separately.
- **NG8.** Adopting Sentry releases tagging or performance tracing. Out of scope for this brainstorm's framing.

## Functional Requirements

### FR1: Migration audit script

A one-shot script (location: `plugins/soleur/skills/preflight/scripts/sentry-monitors-audit.sh` — preflight is the closest "verify the world is sane" home) that:

- Lists every Sentry Monitor in the org via API.
- Lists every Sentry Alert via API.
- Joins on monitor-id, flags **orphan monitors** (detection without routing) and **orphan alerts** (routing referencing a missing monitor).
- Detects region (US `sentry.io` vs EU `de.sentry.io`) the same way `configure-sentry-alerts.sh` does today.
- Writes a Markdown report to `knowledge-base/engineering/ops/sentry-migration-audit-<YYYY-MM-DD>.md` with: monitor/alert inventory, orphan list, routing-destination table, region, timestamp. Idempotent — re-running produces a new dated file, never mutates state.

### FR2: Cron monitors for scheduled workflows

Wire `Sentry.checkIn()` (or equivalent HTTP ping) at job start + success ping at end for every workflow under `.github/workflows/` that has a `schedule:` (cron) trigger. At minimum: daily community digest, scheduled triage. Each gets a unique `monitorSlug`. Failure to ping or late ping produces an issue via the Monitor.

### FR3: Terraform Sentry root

New `terraform/sentry/` root:

- Uses `getsentry/sentry` provider, pinned.
- **Imports** the 4 existing issue-alert rules (auth-exchange-code-burst, auth-callback-no-code-burst, auth-per-user-loop, auth-signout-burst) via `terraform import` against state — does not recreate them.
- Imports the cron monitors created in FR2 (after they exist).
- Imports auto-migrated Metric Monitors + paired Alerts found in FR1.
- Per-environment workspaces if needed (dev/prd). Per `hr-dev-prd-distinct-supabase-projects` spirit: distinct Sentry projects per env.
- ADR at `knowledge-base/engineering/architecture/adr-NNN-sentry-as-iac.md` documenting decision, provider choice, import strategy, rollback.

### FR4: Legal corpus update

Mechanical edits, no semantic restructure:

- `knowledge-base/legal/article-30-register.md` PA8 §(c): add carve-out paragraph naming span-attribute and custom-metric monitors as in-scope (aggregated metric values; low PII risk); explicit "log ingestion is **not** enabled" line.
- `docs/legal/data-protection-disclosure.md` §2.3(m): mirror the carve-out.
- `docs/legal/privacy-policy.md` §5.10: mirror the carve-out.
- `docs/legal/gdpr-policy.md` operational-telemetry entry: mirror the carve-out.
- `knowledge-base/legal/compliance-posture.md` Active Compliance Items table: add a row referencing the audit artifact from FR1.

### FR5: `configure-sentry-alerts.sh` deprecation

Once Terraform owns the 4 alert rules (FR3), `apps/web-platform/scripts/configure-sentry-alerts.sh` is moved to `apps/web-platform/scripts/archive/` with a header comment pointing to `terraform/sentry/`. The release workflow step that invokes it (per `.github/workflows/reusable-release.yml`) is removed.

### FR6: GDPR-gate enforcement

`plan` Phase 2.6 carries the `brand_survival_threshold: single-user incident` forward. The implementation phase MUST run `/soleur:gdpr-gate` on the diff and pass before PR is marked ready. Gate specifically checks that no diff enables `logs` ingestion in `sentry.client.config.ts` / `sentry.server.config.ts` / Terraform monitor type.

## Technical Requirements

### TR1: Region detection consistency

The audit script (FR1) and Terraform provider config (FR3) must both detect Sentry region the same way the existing `configure-sentry-alerts.sh` does (probe `/users/me/` against `sentry.io` and `de.sentry.io`). Hardcoding the region in either place creates drift risk on org-level reconfigurations.

### TR2: Secret management

`SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` continue to flow through Doppler (per `hr-dev-prd-distinct-supabase-projects` discipline applied to Sentry: dev and prd tokens are distinct, never shared). Terraform reads these via env vars from Doppler in CI; locally via `doppler run`.

### TR3: Idempotent imports

The Terraform import step must be re-runnable without state corruption. Use `terraform import` against an explicit address; do not `terraform apply` until the import has been reviewed and the plan is a no-op against current Sentry state.

### TR4: No-op on read paths

The `postmerge` skill (`plugins/soleur/skills/postmerge/SKILL.md:188`) and `qa` skill (`plugins/soleur/skills/qa/SKILL.md:98`) query Sentry API. Spec changes MUST NOT touch these unless an empirical breakage is observed against the new Monitors API.

### TR5: Source-of-truth lock

After FR3 lands, the Sentry dashboard is read-only for managed rules (operational practice, not enforced by Sentry). Any dashboard-only edit is drift detected on next `terraform plan` in CI.

## Acceptance Criteria

- **AC1.** `sentry-monitors-audit.sh` runs against prd Sentry org with `SENTRY_AUTH_TOKEN` and produces a dated report under `knowledge-base/engineering/ops/`. Report shows zero orphan monitors **or** documents each orphan with a remediation note.
- **AC2.** Scheduled GH Actions workflows (daily community digest, scheduled triage) emit Sentry check-ins; a deliberate skip produces a Sentry issue within the monitor's grace window.
- **AC3.** `terraform plan` in `terraform/sentry/` shows a no-op against prd state after import. ADR is committed.
- **AC4.** Legal corpus diffs reviewed by CLO; `/soleur:gdpr-gate` passes on the diff. Article 30 register has the audit artifact linked.
- **AC5.** `configure-sentry-alerts.sh` is archived; release workflow no longer invokes it; one full release cycle has shipped using the Terraform-managed rules.
- **AC6.** No regression in dashboard-keyed message strings (the existing 4 auth alert message strings render identically in operator-facing dashboards).

## Open Questions

- **OQ1.** Does Sentry's new API expose Monitors and Alerts under new endpoints, or stay backward-compatible on `/api/0/projects/.../rules/`? Resolution: read `getsentry/sentry` Terraform provider docs as authoritative; if backward-compat, the audit script can reuse the existing `configure-sentry-alerts.sh` API helpers.
- **OQ2.** Cron check-in mechanism inside GH Actions: in-workflow SDK call vs. raw HTTP ping. SDK is simpler in Node-based workflows; HTTP is portable. Decide per workflow's existing language.
- **OQ3.** Audit-script home: `plugins/soleur/skills/preflight/scripts/` (spec default) vs. `apps/web-platform/scripts/` (co-located with `configure-sentry-alerts.sh`). Preflight wins on intent; co-location wins on shared API-helper reuse. Resolve at plan time.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-15-sentry-monitors-alerts-adaptation-brainstorm.md`
- AGENTS.md rules: `cq-silent-fallback-must-mirror-to-sentry`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-every-new-terraform-root-must-include-an`, `hr-all-infrastructure-provisioning-servers`, `hr-weigh-every-decision-against-target-user-impact`.
- Code: `apps/web-platform/sentry.server.config.ts`, `apps/web-platform/sentry.client.config.ts`, `apps/web-platform/server/sentry-scrub.ts`, `apps/web-platform/lib/client-observability.ts`, `apps/web-platform/server/observability.ts`, `apps/web-platform/scripts/configure-sentry-alerts.sh`.
- Legal: `knowledge-base/legal/article-30-register.md` PA8, `knowledge-base/legal/compliance-posture.md`, `docs/legal/data-protection-disclosure.md` §2.3(m), `docs/legal/privacy-policy.md` §5.10, `docs/legal/gdpr-policy.md`.
- Related: multi-tenant DPA clause for Sentry sharing (separate tracking issue, references #3744 area).
