---
adr: 035
title: messages.source_ref composite-unique for multi-source dedup
status: accepted
date: 2026-05-19
related: [3244, 4066]
related_adrs: [ADR-034]
related_plans:
  - knowledge-base/project/plans/2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md
brand_survival_threshold: single-user incident
---

# ADR-035: messages.source_ref composite-unique for multi-source dedup

> Note on numbering: the plan provisionally named this ADR-032 to pair with ADR-031. Between plan-time and /work, ADR-031 / ADR-032 / ADR-033 slots were consumed by unrelated PRs. This ADR adopts the next free number (035) after ADR-034.

## Status

**Accepted** (2026-05-19, PR-H #4066).

Flipped from `proposed` at Phase 3 of `2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md` after migration 051 landed.

## Context

PR-H introduces two new ingress sources (GitHub webhook, KB-drift walker) on top of PR-F's Stripe ingress. Each source produces autonomous-draft `messages` rows. A naive INSERT-per-event leaks two failure shapes:

1. **Webhook redelivery doubles a draft.** GitHub redelivers on 5xx (and occasionally on 2xx with transient infrastructure flakes). Without a DB-level dedup, the same PR-review event lands as two cards.
2. **KB-drift walker re-runs.** Nightly cron + ad-hoc operator runs both POST to `/api/internal/kb-drift-ingest`. Same broken-link finding → two cards on consecutive runs.

The processed_github_events / processed_stripe_events dedup tables gate the WEBHOOK at the ingress boundary — but the KB-drift walker has no equivalent delivery_id and the Inngest dispatcher (Phase 4) writes the `messages` row on a separate Inngest event from the webhook's processed-events row. The dedup gate that load-bears at the `messages` table itself MUST be a per-row uniqueness constraint.

`ON CONFLICT DO NOTHING` is the textbook idiom but is unreliable under supabase-js: `.insert()` returns `data: null` (not `[]`, not affected-row-count) when the conflict-do-nothing path fires without an explicit `.select()`. The empty-result gate at the caller is not load-bearing under this idiom. The Stripe webhook learned this in PR #2772 and the canonical idiom there is: plain `.insert()` + catch `PG_UNIQUE_VIOLATION (23505)` → 200 duplicate.

Brand-survival threshold for PR-H: `single-user incident`. A duplicate Today card is a low-severity nuisance for one founder, but it compounds across founders and across event volume.

## Decision

**Adopt `messages.source_ref` (nullable text column) + `messages_active_draft_dedup_idx` (partial-unique index on `(user_id, source, source_ref)` WHERE `status = 'draft'` AND `source_ref IS NOT NULL`). Webhook + Inngest + KB-drift ingest all INSERT without `ON CONFLICT`; supabase-js error.code === `23505` (PG_UNIQUE_VIOLATION) → 200 duplicate; mirror of Stripe's `processed_stripe_events` pattern (route.ts:117-127). Retention of `processed_github_events` is natural via Postgres autovacuum + 30-day partition rotation — no explicit TTL daemon; self-hosted Inngest's 24h `event.id` dedup window is FIXED (not configurable), so the DB-side dedup is the load-bearing replay defense beyond the Inngest window.**

`source_ref` shapes:
- GitHub PR review: `pr-<repo>-<number>` (e.g., `pr-jikig-ai-soleur-4066`)
- GitHub CI failure: `ci-<workflow_run_id>`
- GitHub issue triage: `issue-<repo>-<number>`
- GitHub CVE: `cve-<advisory_id>` or `secret-scan-<alert_id>`
- KB-drift broken link: `link-<sha256(source_path + target_path)[:16]>`
- KB-drift broken anchor: `anchor-<sha256(source_file + anchor_path)[:16]>`

## Rejected alternatives

- **ON CONFLICT DO NOTHING (no caller-side detection).** Unreliable under supabase-js — discussed above.
- **Single-source-ref-per-table.** Adding a separate dedup table per source (`processed_github_events`, `processed_kb_drift_findings`, …) inverts the audit shape: the `messages` row would be the proxy-of-record while the dedup table holds the canonical id. The partial-unique index on `messages` itself keeps `messages` as the canonical row and lets autovacuum reclaim space without coordinating a sibling table.
- **Explicit TTL daemon for `processed_github_events`.** Cron-based cleanup adds an Inngest function to the schedule with no load-bearing data integrity payoff: the table is small (delivery_id text + received_at timestamptz), autovacuum is sufficient, and a 30-day partition rotation is the future-proof path if volume warrants it.

## Consequences

- The webhook handler MUST run the release-on-error pattern (`releaseDedupRow()` mirror of Stripe) — without it, a transient `inngest.send` failure leaves the dedup row, GitHub redelivers, the redelivery 200s as "duplicate", and the event is silently dropped. ADR-034 documents the ordering invariant.
- The Inngest dispatcher (Phase 4) catches the same `23505` on `messages.insert()` and returns a non-throwing step result so Inngest does not retry. Phase 4 ADR-030 invariants I1 (BYOK lease scope) + I2 (per-tenant client) + I3 (verify-state outside step.run) all still apply.
- The KB-drift ingest route catches the same `23505` and returns 200 for any (link or anchor) finding already present as an open draft — idempotent re-runs are free.
