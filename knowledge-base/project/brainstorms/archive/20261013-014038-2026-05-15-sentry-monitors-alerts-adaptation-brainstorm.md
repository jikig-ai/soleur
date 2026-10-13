---
date: 2026-05-15
topic: sentry-monitors-alerts-adaptation
status: complete
brand_survival_threshold: single-user incident
lane: cross-domain
---

# Sentry Monitors/Alerts Split — Adaptation Brainstorm

## Context

Sentry split their "Alerts" product into two concepts in 2026:

- **Monitors** detect problems and create issues. Conditions span attributes, logs, custom metrics. Crons and Uptime now live under Monitors.
- **Alerts** are routing only — Slack, email, PagerDuty. One alert connects to many monitors.

Existing Metric Alerts auto-migrated to Metric Monitors; existing alert rules preserved as routing-only. Vendor says "no action required" but recommends a review.

Two questions framed the brainstorm:

1. Does Soleur's current Sentry integration need to adapt?
2. Can Monitors+Alerts be leveraged as a capability we expose to Soleur users?

## User-Brand Impact

- **Artifact:** Sentry integration (error capture, silent-fallback mirroring, auth-regression alert rules, Article 30 register PA8).
- **Vector 1:** PII leak via Sentry payloads if new monitor types (especially log-condition monitors) ingest data beyond the current scrub-boundary.
- **Vector 2:** Silent production incident if Sentry's auto-migration orphaned a Metric Alert from its paired routing rule — threshold breaches stop paging.
- **Threshold:** Single-user incident. A single missed page on a production auth burst or a single PII-leaking log breaches the threshold.

## What We're Building

Adopt Sentry's new Monitors+Alerts model deliberately, in this order:

1. **Verify the auto-migration** with a one-shot audit script. Retain the snapshot as Article 30 evidence.
2. **Update the legal corpus** (Art. 30 §(c), DPD §2.3(m), Privacy Policy §5.10) to explicitly disclose the carve-out: span-attribute and custom-metric monitors are in scope; log ingestion is *not* enabled.
3. **Wire Sentry cron monitors** to the scheduled GitHub Actions workflows that currently have no "did this run?" detection (daily community digest, scheduled triage).
4. **Migrate `configure-sentry-alerts.sh` to Terraform** using the `getsentry/sentry` provider, with an ADR. **Import existing rules — do not recreate** (the script's hardcoded thresholds and dashboard-keyed message strings are load-bearing per `helper-migration-must-preserve-operator-dashboard-message-strings` learning).

We explicitly **do not** productize this for Soleur users in this brainstorm. CPO assessment confirms zero demand-signal, and roadmap row 4.9 already gates the productization on "10+ users." A separate issue captures the multi-tenant DPA clause as a forward-looking dependency.

## Why This Approach

- **CTO trip-wire is real.** The auto-migration cannot be confirmed from a dashboard skim — orphan detection requires API enumeration. Skipping the audit means a silent paging-gap that surfaces only when a P1 issue stops paging on-call.
- **Cron monitors are free leverage.** Scheduled GH Actions silently stopping is currently undetected. The Sentry Crons feature is the cheapest possible fix and aligns with the existing `cq-silent-fallback-must-mirror-to-sentry` posture.
- **Terraform is the right long-term home** for alert thresholds (today hardcoded in a bash script) — drift detection, peer review, ADR-anchored history.
- **Sequencing matters.** Audit first, then Terraform import, prevents the failure mode where IaC declares the wrong state as source-of-truth.
- **CPO defer-to-demand is right.** Reacting to a vendor refactor with a new product surface is feature-looking-for-customer; zero beta users today.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Scope | Audit + cron monitors + Terraform onramp | Captures verification, free-leverage detection, and IaC home in one bundle |
| Productize for Soleur users? | No (defer) | Zero demand-signal; roadmap 4.9 already gates on 10+ users |
| Multi-tenant DPA clause (CLO M-delta) | Separate tracking issue | Forward-looking; depends on multi-tenant substrate (#3744 area) |
| Terraform strategy | Import existing rules, do not recreate | Threshold values and message strings are operationally load-bearing |
| Log-condition monitors | Not enabled | Requires extending `sentry-scrub.ts` to cover `logs` channel first; out of scope |
| Span-attribute / custom-metric monitors | Not enabled by default | Speculative; let real incident pressure pull new types |
| Source-map upload | Not adopted in this scope | Separate gap surfaced by repo-research; not Monitors-related |
| GDPR-gate trigger | Required | Diff touches monitor configuration + potentially `sentry-scrub.ts` |
| ADR required | Yes | New Terraform root per `hr-every-new-terraform-root-must-include-an` |

## Non-Goals

- Productizing Sentry-style observability for Soleur users (defer to 10+ users pulling for it).
- Enabling Sentry log-condition monitors (requires scrubber extension first).
- Adopting span-attribute or custom-metric monitors speculatively.
- Adding source-map upload to CI (separate gap, not Monitors-related).
- Refactoring `reportSilentFallback` / `mirrorP0Deduped` / `mirrorCrossTenantViolation` helpers — Monitors/Alerts split is server-side, application emit code is unaffected.
- Migrating `qa` / `postmerge` skill Sentry API queries pre-emptively — wait for concrete breakage.
- Single-shared Sentry org serving multiple Soleur-managed tenants (multi-tenant DPA clause is a separate issue).

## Open Questions

- Does the new Sentry API expose Monitors and Alerts under new endpoints, or does it route through the existing `/api/0/projects/.../rules/` contract that `configure-sentry-alerts.sh` calls? The Terraform provider docs are the authoritative answer; until verified, assume the script will need an upgrade.
- For cron monitors, do we ping `Sentry.checkIn()` from inside the workflow step or via a separate HTTP call? Both are documented; the in-workflow ping is simpler but requires the SDK.
- Should the audit script live in `apps/web-platform/scripts/` next to `configure-sentry-alerts.sh`, or in `plugins/soleur/skills/preflight/scripts/`? Preflight is closer to the "verify the world is sane" intent.

## Domain Assessments

**Assessed:** Marketing (skipped), Engineering, Operations (folded into Engineering), Product, Legal, Sales (skipped), Finance (skipped), Support (skipped)

### Engineering (CTO)

**Summary:** Adapt now, narrow scope. Codebase is Sentry-load-bearing in three non-trivial ways (dashboard-keyed message strings, postmerge skill uses Sentry API as canonical prod-debug surface, qa skill has EU-region/statsPeriod assumptions). Trip-wire: an auto-migrated Metric Alert whose paired routing rule didn't survive — silent until a P1 issue stops paging. Cron monitors for scheduled GH Actions is genuine net-new value. Terraform onramp is the right IaC home. Do not refactor silent-fallback helpers (split is server-side). Do not adopt span/log monitors speculatively. Do not migrate qa/postmerge API queries pre-emptively.

### Product (CPO)

**Summary:** Defer to demand-signal. Zero beta users, zero pricing gates passed, Phase 4 recruitment not started. Roadmap row 4.9 (error tracking) is P2 and already gated on "10+ users." Sentry's split is a vendor refactor of an internal dependency. Reacting now is CTO-territory tuning dressed as product. If ever pulled for, smallest first-cut is `/soleur:monitor` skill that emits a Sentry Monitor config from a PIR or English description — hours of work when triggered. Trigger to revisit: 3+ Phase 4 founders independently ask "can Soleur watch my production app?"

### Legal (CLO)

**Summary:** Adapt with new safeguards — not pure "document only." The new Monitors capability, especially log-condition monitors, would silently broaden ingested data classes beyond current RoPA §(c) inventory. Three concrete legal deltas: (1) document auto-migration verification as Art. 30 evidence (XS), (2) update Art. 30 + DPD + Privacy Policy + GDPR Policy with explicit "we do NOT enable Sentry log ingestion" carve-out (S), (3) tenant-cross-blast DPA clause for multi-tenant substrate (M, deferred to separate issue). Do not enable log-condition monitors before extending `sentry-scrub.ts` to cover the `logs` event channel. GDPR-gate required on the implementation diff.

## Capability Gaps

None — existing `architecture`, `plan`, `work`, `compound`, `preflight`, `ship`, `gdpr-gate` skills cover this scope. Terraform work routes through `hr-all-infrastructure-provisioning-servers`. ADR routes through `/soleur:architecture create`.

**Evidence:** Repo-research enumerated the integration surface (SDK init, scrub layers, observability helpers, `configure-sentry-alerts.sh`, Art. 30 PA8, vendor DPA table). CTO confirmed no new agent or skill is needed. CLO confirmed the existing scrub-boundary pattern and Art. 30 register are the right home for the carve-out documentation.
