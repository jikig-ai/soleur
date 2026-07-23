---
title: GitHub App webhook as second multi-source ingress
status: accepted
date: 2026-05-19
related: [3244, 4066]
related_adrs: [ADR-030, ADR-033]
related_plans:
  - knowledge-base/project/plans/2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md
brand_survival_threshold: single-user incident
---

# ADR-036: GitHub App webhook as second multi-source ingress

> Note on numbering: the **filename ordinal is authoritative** (#6800). The plan provisionally named this ADR-031; between plan-time and /work the 031–033 slots were consumed by unrelated PRs, so the file was created as `ADR-036-*` while an earlier draft frontmatter/heading read `034`. That disagreeing ordinal has been reconciled to the filename. Related ADRs link to ADR-030 (the Inngest substrate this ingress feeds) and ADR-033 (`per-tenant-scope-grants`, the gate this ingress checks).

## Status

**Accepted** (2026-05-19, PR-H #4066).

Flipped from `proposed` at Phase 3 of `2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md` after the substrate landed: migration 051 (`processed_github_events`, `audit_github_token_use`, `messages_active_draft_dedup_idx`); server modules at `apps/web-platform/server/github/app-client.ts`; webhook handler at `apps/web-platform/app/api/webhooks/github/route.ts`.

## Context

PR-F (ADR-030, #3940) shipped the Inngest durable-trigger substrate and the first ingress (Stripe webhook → `finance.payment_failed`). PR-G (ADR-033, #3947) added per-tenant scope grants as the deny-by-default gate at every ingress.

Umbrella #3244's outstanding acceptance criterion calls for "≥3 signal sources." With Stripe (PR-F) as the first source, the second can be polled (cron walks GitHub) or pushed (webhook). Three concrete failure modes the polling alternative cannot prevent:

1. **Latency drift.** Polling at 5-minute intervals lets a P0 CVE alert age 5 minutes before the founder sees the Today card. Webhooks land within seconds of GitHub's emit.
2. **Idle-tenant cost.** A polling walker that runs per-founder per-5-min wastes BYOK budget against zero-event windows. Webhooks fire only when there is an event.
3. **Audit-trail completeness.** Polling depends on the walker's lease; a missed lease window silently drops events. Webhooks carry an authoritative `x-github-delivery` id that gives an exactly-once-with-redelivery dispatch contract under the same `processed_*_events` dedup primitive used for Stripe.

Brand-survival threshold for PR-H: `single-user incident`. The webhook + Inngest dispatcher path matches the audit shape PR-G already demands of the Stripe path; polling would have required a parallel audit primitive.

## Decision

**Adopt the GitHub App webhook as the second multi-source ingress. The App's installation token (auto-refreshed by `@octokit/auth-app` v8+ at `expires_at - 60s`) is the per-request authentication primitive; a PAT is rejected on two counts (operator-level scope; no per-installation revoke). The route at `apps/web-platform/app/api/webhooks/github/route.ts` mirrors the Stripe webhook's 8-step ordering exactly (verify-FIRST, dedup-SECOND via `processed_github_events.delivery_id` PRIMARY KEY catching `PG_UNIQUE_VIOLATION`, scope-grant-THIRD via PR-G's `isGranted`, send-FOURTH via Inngest, release-on-error via `releaseDedupRow()` mirror). Octokit App instantiation is per-request (NO module-scope singleton — vercel/next.js#65350 race; `@octokit/auth-app` already auto-refreshes — a manual cache layered on top double-caches and risks mid-request expiry).**

## Rejected alternatives

- **GitHub PAT (personal access token) instead of App.** PAT carries operator-level scope; a leak grants org-wide read. App installation tokens are per-installation, short-lived, and revocable from the GitHub App admin UI without code changes. PAT off-table.
- **Polling walker on Inngest cron.** Latency drift + idle-tenant cost + parallel audit primitive — listed above as the three failure modes the webhook avoids.
- **Module-scope `App` singleton.** Reuse-the-instance pattern is a documented Next.js App Router cross-worker hazard (vercel/next.js#65350) and double-caches the token-refresh primitive that `@octokit/auth-app` already owns. The factory `createGitHubAppClient(installationId)` is the load-bearing primitive; tests assert "no module-scope state" via fresh-import-per-test.
- **ON CONFLICT DO NOTHING for dedup.** supabase-js `.insert()` returns `data: null` (not `[]`, not affected-row-count) on the no-op path; the resulting empty-result gate is unreliable. The Stripe path catches `PG_UNIQUE_VIOLATION (23505)` instead and we mirror that idiom (see ADR-035).

## Consequences

- Webhook 4xx/5xx surface lives behind Better Stack monitors (paid-tier gated via `var.betterstack_paid_tier`); free-tier paths fall back to Sentry mirror per `cq-silent-fallback-must-mirror-to-sentry`.
- Operator owns the GitHub App creation step at `https://github.com/settings/apps/new` (single manual gate per `hr-never-label-any-step-as-manual-without`; deferred-automation issue tracks future Terraform-provider availability).
- `audit_github_token_use` ledger gives Art. 5(2) accountability for every installation-token use; the `record_github_token_use` `SECURITY DEFINER` RPC is the sole write path.
- Webhook secret is `random_id`-derived in Terraform (rotation = `terraform apply -replace=random_id.github_webhook_secret`); the 4 operator-supplied App secrets carry `lifecycle.ignore_changes = [value]` to keep ad-hoc dashboard rotations from causing Terraform plan churn.

## Amendment 2026-06-30 — drop-before-dedup reorder (WAL reduction)

The Decision above states the route "mirrors the Stripe webhook's 8-step ordering exactly (verify-FIRST, dedup-SECOND … send-FOURTH)." That ordering claim is **superseded for the dedup step only**.

**What changed.** The `processed_github_events` dedup `INSERT` no longer runs second (immediately after signature verify, before parse + drop-filters). It now runs **drop-before-dedup**: inside a `claimDedupRow()` closure invoked immediately before EACH dispatch site (push-reconcile + non-push `inngest.send`), AFTER every drop-filter. Deliveries that drop (`workflow_run` non-failure, no installation, non-reconcilable push, no founder / ambiguous / db-error, unmapped event, no grant) return their existing 200/4xx and write NO dedup row.

**Why.** Per `pg_stat_statements.wal_bytes` on production project `ifsccnjhymdmidffkzhl`, the dedup-first `INSERT` was **63% of the database's total WAL** — the dominant Supabase Disk-IO-budget consumer (the warning that prompted this work). The GitHub stream is dominated by a guaranteed no-op (`workflow_run` with `conclusion !== 'failure'`); dedup-first wrote (and migration 094 later auto-deleted) a useless row for every one. WAL is per-write, not per-retained-row, so the only lever is to stop writing rows that never gated a dispatch. Stripe has no equivalent high-frequency no-op (every Stripe event type is actioned; ~1 row/day), so dedup-first costs Stripe nothing — the divergence is a deliberate, measured response to GitHub's **volume + actioned-ratio**, NOT "Stripe doesn't dispatch" (Stripe's `invoice.payment_failed` branch also dispatches to Inngest and relies on dedup-first).

**Stripe idioms preserved.** Two load-bearing parity properties are kept verbatim in `claimDedupRow()` / the dispatch try-catches:

1. `PG_UNIQUE_VIOLATION (23505) → 200 {received:true}` replay short-circuit — concurrency-safe via the `delivery_id` unique constraint, the serialization point for concurrent redeliveries.
2. `releaseDedupRow()` on dispatch failure (both push and non-push paths) so a transient `inngest.send` failure is re-driven by GitHub's redelivery rather than silently swallowed.

The surviving invariant is "INSERT strictly before side-effect dispatch." Do NOT "restore Stripe ordering parity" by moving the INSERT back to second — that re-introduces the 63%-WAL regression. See plan `knowledge-base/project/plans/2026-06-30-fix-webhook-dedup-drop-before-insert-plan.md` and the route header at `apps/web-platform/app/api/webhooks/github/route.ts`.

**Behavioral note.** One intentional behavioral change falls out of the reorder: a no-grant (`isGranted` = false) non-push event no longer writes a dedup row, so if the founder later grants the scope, a GitHub redelivery of that `delivery_id` WILL dispatch. This is strictly more correct — the signal is delivered once consent exists — and is never a double-dispatch, since the no-grant path never dispatched in the first place.
