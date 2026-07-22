---
title: messages.source_ref composite-unique for multi-source dedup
status: accepted
date: 2026-05-19
related: [3244, 4066]
related_adrs: [ADR-034]
related_plans:
  - knowledge-base/project/plans/2026-05-19-feat-daily-priorities-multi-source-pr-h-plan.md
brand_survival_threshold: single-user incident
---

# ADR-037: messages.source_ref composite-unique for multi-source dedup

> Note on numbering: the **filename ordinal is authoritative** (#6800). The plan provisionally named this ADR-032; between plan-time and /work the 031–033 slots were consumed by unrelated PRs, so the file was created as `ADR-037-*` while an earlier draft frontmatter/heading read `035`. That disagreeing ordinal has been reconciled to the filename — `ADR-035` unambiguously refers to the template-registry ADR, and this decision (the `plain-insert`/catch-`23505` dedup idiom and its #6781 send-boundary extension) is `ADR-037`.

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

---

## Amendment (2026-07-20, #6781) — extension from ingest-dedup to send-dedup

**Status:** accepted. Amends this ADR's scope; does not supersede any decision above.

### What changed

The plain-insert-catch-`23505` idiom decided here was, until now, applied only at
**ingest** boundaries: "have we already *received* this event?" (`processed_github_events`,
`messages.source_ref`, the KB-drift route). This amendment extends the same idiom to a
**send** boundary: "have we already *sent* this notification?"

The concrete instance is `statutory_repin_send` (migration 135), which guards the
statutory-deadline repin cron. Before it, that send path carried no idempotency key, no
sent-marker, and no Inngest `idempotency`/`concurrency` config, so a double-fired scheduler
sent duplicate statutory-deadline email per user **per tick, indefinitely** — not a one-off
duplicate.

The idiom transfers cleanly, but three properties differ from the ingest case and are
decided here rather than inherited.

### 1. The key is branch-derived, not a single column

Ingest dedup keys on an identifier the *upstream* supplies (a delivery id, a source ref).
A send boundary has no such gift — the "logical tick" must be constructed, and constructing
it wrong fails in one of two opposite directions:

| Candidate key | Failure |
| --- | --- |
| "have we ever pinged this item" | Silences the entire daily danger band after day one |
| `daysUntilDue` | `due` inherits `received_at`'s time-of-day, so a cron run and a manual trigger minutes apart compute different values → same-day duplicate |
| UTC calendar date | Correct for the daily band; **wrong** for the one-shot heads-up, whose `floor()` window spans 24h and therefore straddles two dates |

**Decision:** the key is `'headsup'` (a constant, for the one-shot T-7) or
`'daily:YYYY-MM-DD'` (for the T-2-through-overdue band), CHECK-pinned to exactly those two
shapes. **Cadence-shape rule:** a send-dedup key must model *every* cadence the sender has,
and a sender with N cadences needs N key shapes — not one key that happens to work for the
common case.

### 2. Fail open, not fail closed

Ingest dedup can safely fail closed: dropping a duplicate webhook costs nothing, and the
upstream will usually redeliver. A send boundary is asymmetric in the other direction. Here
the marker table guards a **statutory deadline**, so suppressing a send the user needed is
strictly worse than sending twice.

**Decision:** only a clean `23505` suppresses. Every other outcome — an `{error}` return
*or* a thrown rejection — dispatches anyway. This is deliberately weaker than the ingest
sites, and it is weaker on purpose.

Two reinforcing reasons, both specific to this sender: the T-7 arm is a **structural
one-shot**, so a suppressed send is not delayed but *deleted* (the next tick no longer
satisfies the equality); and the likeliest fail-open trigger — a `42P01` during the deploy
window — is **correlated**, hitting every item in the band at once rather than one unlucky row.

A thrown rejection must also not escape the iteration: the enclosing Inngest function runs
under `retries: 0`, so an escape would kill the run and take the ingress liveness probe
(steps 3–5) down with it.

#### Residual: marker-before-dispatch reopens the asymmetry for one case

The fail-open argument above is not a complete discharge, and presenting it as
one would be dishonest.

The marker is written immediately **before** dispatch, because sending first
means a crash in between re-sends forever. But that ordering reintroduces the
exact outcome the T-7 reasoning calls unacceptable: if the marker insert
succeeds and the dispatch then fails — a pod kill, an unhandled throw, an
`await` that never resolves — the `headsup` marker persists, the next tick sees
`daysUntilDue !== 7`, and the heads-up is **deleted, not delayed**. Under
`retries: 0` nothing retries it.

The trade is deliberate and the blast radius is one item per crash (the marker
lands immediately before that item's own dispatch, so at most one item is in
flight). The daily band self-heals on tomorrow's key; only the one-shot arm
does not. Two things carry this residual:

- the operator **release verb** (`purge_statutory_repin_send(p_item_id)`),
  reachable via the manual-trigger event, which re-arms the item — subject to
  the dead-zone caveat below;
- `statutory-notify-zero-delivery`, which covers the zero-device case but
  **not** the crash-after-marker case, which currently emits nothing per-item.

**The release verb re-arms; it does not force a send.** The repin predicate
fires at exactly T-7, then daily from T-2 through overdue, so days 6..3 fire
nothing at all. A release inside that dead zone does nothing until T-2 — which
on a 72-hour `breach-art33` clock is most of the remaining time.

### 3. Recipient-grain constraint (the 1:N rebuttal)

The "Single-source-ref-per-table" alternative rejected above argued against per-source dedup
tables. That reasoning does **not** transfer to the send side, and the difference is worth
stating because it looks superficially like the same shape.

Ingest dedup is 1:1 — one upstream event, one row. Send dedup is potentially **1:N** — one
item, N recipients. `statutory_repin_send` is keyed `(item_id, tick_key)`, i.e. **item
grain**, which equals **recipient grain** only because this send path pings `row.user_id`
and nobody else.

That is a property of the send path, **not a structural guarantee**. Migration 111 already
makes an item visible to every workspace Owner. If a future change fans the repin out to
multiple Owners, the first Owner's marker would suppress every other Owner: N−1 people get
**silence** on a statutory deadline while the step reports success. This is the same collapse
class the sibling `notifyInboxItem` comment warns about for its workspace-scoped
`(workspace_id, dedup_key)` index.

**Constraint:** before any fan-out of a send path guarded by this idiom, re-key its marker
table to recipient grain. This constraint is enforced by an automated tripwire (test T12 in
`cron-email-ingress-probe-repin-idempotency.test.ts`), not by this paragraph — documentation
does not fail, and an invariant that currently holds only by accident of an unrelated code
path needs something that does.

### 4. TTL-daemon rejection: honored, with one exception

The "Explicit TTL daemon" rejection above is honored — no new Inngest function was added.
But its premise ("autovacuum is sufficient") assumes rows become garbage on their own. For
`statutory_repin_send` that is false in an instructive way: its `ON DELETE CASCADE` hangs off
`email_triage_items`, and **statutory parent rows are accountability evidence that is never
purged**, so the cascade in practice never fires.

**Decision:** retention is an explicit 90-day sweep (`purge_statutory_repin_send`) called
from the cron's **existing** `retention-purge` step — a new SQL function, not a new schedule.
The general rule: "the cascade will clean it up" must be checked against whether the *parent*
is ever actually deleted, not merely against whether a cascade is declared.

### Consequences

- The send-marker removes an accidental self-heal. `sendPushNotifications` prunes HTTP-410
  subscriptions, so before this change a failed push retried on the next tick. With a marker
  written, nothing retries — so `notifyOfflineUser` now emits `statutory-notify-zero-delivery`
  when a statutory notification reaches zero devices. Adding a dedup guard to a delivery path
  obliges you to check what retry behavior the guard is silently removing.
- `purge_statutory_repin_send(p_item_id)` doubles as an operator **release verb**: clearing
  an item's markers makes the next tick re-send, for a send that was marked but demonstrably
  never delivered.
- No pre-existing function was `CREATE OR REPLACE`d. Security attributes do not survive a
  replace and both AP-018 guard tiers are blind to the drop.

---

## Amendment (2026-07-22, #6799 / #6801) — the heads-up band, the scan anchor, and breach-art33

The #6781 send-boundary extension made three assumptions that #6799/#6801 revised.
The `plain-insert`/catch-`23505` idiom itself is unchanged; what changed is the
tick-key semantics and the scan the guard runs over.

- **`headsup` now keys a BAND (T-7 through T-3), not an exact day.** The original
  `daysUntilDue === 7` equality was jitter-fragile: `daysUntilDue` is
  `floor((due - now)/day)` at the cron instant, so ordinary scheduler jitter could
  step 8 → 6 across two runs and the heads-up would silently never fire (#6799).
  The predicate is now `daysUntilDue <= 7` above the danger threshold. The
  migration-135 `tick_key` CHECK already permits exactly `headsup` and
  `daily:YYYY-MM-DD`, so **no migration is required**.
- **A `23505` on the `headsup` key is EXPECTED steady state and is counted
  separately from the double-fire signal.** Under the band, an item pinged at T-7
  re-hits the same constant key at T-6..T-3. The 23505 is disambiguated by the
  existing marker's `created_at`: same UTC date as the run → a genuine same-day
  double-fire (`suppressed`, the `repin_suppressed` tag input, the sole signal a
  second scheduler is live); an earlier date → the expected band re-hit
  (`headsUpAlreadySent`, never in the tag or the escalation). This keeps the #6781
  double-fire detector fully intact — exactly, with no detection-delay residual.
- **The repin scan is anchored on `acknowledged_at`, not `received_at` (#6801).**
  What confers eligibility is `status = 'acknowledged'`, so the 60-day window is
  anchored on when the item became eligible — an item is pingable for 60 days after
  it becomes pingable. `acknowledged_at` is WORM (mig 102) and always set on the
  acknowledge transition, so it is never NULL for an acknowledged row. **Recorded
  residual:** items acknowledged more than 60 days ago are deliberately dropped and
  now VISIBLY dropped — counted as `excluded` in the `deadline-repin-sweep-complete`
  emit (a queryable Sentry tag/field). `excluded` is monotonic and does NOT gate
  escalation (it would page forever); the follow-on flow gaps — a `resolved` state,
  scanning `new` items, and a founder-facing digest for abandoned items — are
  tracked as a separate follow-up, out of #6801's scope.
- **`breach-art33` never enters the heads-up band, by design.** Its 72h `dueRule`
  caps `daysUntilDue` at the danger threshold for any scanned (post-receipt) item,
  so it goes straight to the daily danger cadence — a "7-day heads-up" on a 72-hour
  clock is incoherent. A generic property test asserts this for every hours-kind
  rule, so a future longer hours-rule cannot silently start writing `headsup`
  markers.
- **The ADR-133 marker rollback self-heals ONLY while this predicate is a
  multi-day band.** A rolled-back `headsup` marker re-sends because a later tick in
  the band re-enters the same key. If the band were narrowed back toward an
  equality, that dependency would break (permanent silence on a rolled-back
  heads-up). Named here as the load-bearing invariant, pinned by a re-send test.

### Historical citations (frozen artifacts)

Applied migrations `122_inbox_item.sql` and `135_statutory_repin_send.sql` cite
this decision by its **retired frontmatter ordinal** (`035`). They are content-hashed
after apply (`run-migrations.sh` → `_schema_migrations.content_sha`), so a comment-only
edit would trip `dev-migration-drift-probe` on every future CI run — a permanent
un-clearable warning that is not worth correcting four stale in-file comments. Those
citations are therefore left as-is; this note is the authoritative correction: **the
`plain-insert`/catch-`23505` dedup idiom and its send-boundary extension are ADR-037**
(the filename), regardless of any `035` an applied migration's comment carries.

### Rejected alternatives (this amendment)

- **#6799: keep the equality, add a "traversed-unpinged" counter.** Makes the
  silence visible without ending it — #6799 requires that an item cannot pass the
  window unpinged, which a counter does not satisfy.
- **#6799: per-day heads-up keys (`headsup:<date>`).** Would send a heads-up every
  day of the band (5 emails where 1 is wanted) and violate the mig-135 `tick_key`
  CHECK, forcing a migration.
- **#6801: widen the window to 120/180 days, or a second `warnSilentFallback` emit
  for the excluded count.** The anchor, not the width, is the defect; and the issue
  explicitly rejects a second emit — level-escalating the single emit achieves
  reachability without a second op slug.
