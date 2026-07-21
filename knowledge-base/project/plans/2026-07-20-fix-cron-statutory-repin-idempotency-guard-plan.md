---
title: "fix(notifications): idempotency guard for the statutory-deadline cron send-path"
issue: 6781
date: 2026-07-20
type: bug
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: implemented
---

# fix(notifications): idempotency guard for the statutory-deadline cron send-path

Closes #6781.

> **Lane note:** no `spec.md` exists for this branch, so `lane:` could not be carried
> forward. Defaulted to `cross-domain` (TR2 fail-closed) — justified by the CTO + CLO +
> CPO + GDPR-gate participation in §Domain Review.

## Overview

`cron-email-ingress-probe`'s `deadline-repin` step loops acknowledged statutory
`email_triage_items` rows and calls `notifyOfflineUser` with **no dedupe guard**. A
double-fire sends a duplicate statutory-deadline notification per user **per tick,
indefinitely**.

The fix inserts a durable send-marker row keyed `(item_id, tick_key)` immediately before
dispatch. Dispatch happens **only** on a clean insert; a `23505` means "already sent for
this logical tick" and the dispatch is skipped — the ADR-035 plain-insert-catch-23505 idiom
`notifyInboxItem` already uses.

**The tick identity is the whole problem, and the obvious answers are all wrong.** The repin
has *two* cadences, not one — a **one-shot** heads-up at T-7, and a **daily** ping from T-2
through overdue. A key that models only one fails on the other:

| Candidate key | Fails how |
| --- | --- |
| "have we pinged this item" | Silences the entire daily danger band after day 1 |
| `daysUntilDue` | `due` inherits `received_at`'s time-of-day, so a cron run and a manual-trigger minutes apart compute different values → **same-day duplicate** (R3) |
| UTC calendar date | Correct for the daily band; **wrong for the one-shot** — `daysUntilDue === 7` is true across a 24h window that straddles two calendar dates, so ~5 min of ordinary jitter yields **two T-7 emails** (R4) |

The key that works is **branch-derived**: `'headsup'` (a constant — structurally once, ever)
on the T-7 arm, `'daily:YYYY-MM-DD'` in the danger band. Each cadence gets the identity it
actually has.

Everything else is ordered by one asymmetry: **over-suppression is strictly worse than
duplication.** `breach-art33` is 72 hours, so the entire Art. 33 clock lives inside the
daily band — roughly three ticks. One suppressed tick is ~33% of all notice given.

## Research Reconciliation — Spec vs. Codebase

All claims verified against `apps/web-platform/` on `main`, 2026-07-20.

| # | Claim | Reality | Plan response |
| --- | --- | --- | --- |
| **R1** | Issue cites `notifyOfflineUser :275`, `sendEmailTriageEmailNotification :565`, `resend.emails.send :577`, `notifyInboxItem :710`, `dedup_key :762`, collapse warning `:722` | **All six exact** — all in `server/notifications.ts`. The issue omits the filename, which is itself the `cq-cite-content-anchor-not-line-number` failure it invokes. | Proceed; cite by content anchor. |
| **R2** | Retention can be inherited via `ON DELETE CASCADE` from `purge_email_triage_items()` | **FALSE.** Both DELETEs carry `statutory_class IS NULL`; the comment reads *"the WHERE carve-out IS the statutory retention guarantee."* The repin selects `.not("statutory_class","is",null)` — exactly the rows never purged. **Cascade can never fire.** | Explicit sweep in a **standalone** RPC (R5). |
| **R3** | `tick_key = daysUntilDue` is sound | **UNSOUND.** `computeDueDate` preserves `received_at`'s time-of-day for **both** rule kinds (`hours` = exact `+N*3_600_000`; `calendar-month` explicitly copies `getUTCHours/Minutes/Seconds/Milliseconds`). Cron at 06:00 → `2`; manual-trigger at 06:10 → `1`. Two keys, two emails, same day. | Rejected. |
| **R4** | A UTC calendar date fixes it | **Only for the daily band.** `daysUntilDue === 7` is true over `[due−8d, due−7d)`, which straddles two calendar dates unless `received_at` is exactly 00:00. Reproducer: boundary at 05:55; run D 06:00 → `7`, marker `(item, D)`; run D+1 05:50 (≥5 min negative jitter) → still `7`, marker `(item, D+1)` → **two heads-up emails, no operator involved.** The constant's docstring says *"One-shot heads-up ping at exactly T-7 days"* — the right identity for a one-shot is a **constant**. | `tick_key text`: `'headsup'` \| `'daily:YYYY-MM-DD'`. |
| **R5** | Fold the sweep into `purge_email_triage_items()`; amend `anonymise_email_triage_items()` | **Three independent reasons not to.** (a) `CREATE OR REPLACE` does **not** inherit `SECURITY DEFINER` or `SET search_path = public, pg_temp`; omitting either silently downgrades to `SECURITY INVOKER`, and **both AP-018 tiers are blind** — the runtime gate reads `pg_proc.proacl`, which a replace *preserves*, and `test/migration-lint/definer-grants.ts` only recognizes a definer fn by its header, so an omitted header is never checked. (b) `anonymise_email_triage_items` returns `GET DIAGNOSTICS v_rows` captured right after its UPDATE; a second UPDATE placed naturally rebinds the return value and breaks `test/server/email-triage-worm.test.ts`. (c) `purge_email_triage_items` runs in step (1), is deliberately un-caught, and `retries: 0` is pinned — a new DELETE there can **zero the entire danger band** for the day. | **Zero `CREATE OR REPLACE` of any pre-existing function.** Standalone `purge_statutory_repin_send()` called from the same `retention-purge` step. The marker table has no WORM trigger, so the GUC coupling that motivated folding in never existed. |
| **R6** | Keep `user_id` for DSAR ownership | Unnecessary **and** costly. `DsarTableSpec` supports `joinVia` (`server/dsar-export-allowlist.ts`), used by `messages`/`message_attachments`, and `email_triage_items` is already allowlisted `{ ownerField: "user_id", article: "15+20" }`. Routing through the parent preserves Art. 15 **and** makes the Art. 17 residual structurally impossible — `anonymise_email_triage_items` NULLs the *parent's* `user_id`, so a `joinVia` child stops resolving automatically, with zero new SQL. | Drop the `user_id` column; use `joinVia`. The anonymise amendment dissolves entirely. |
| **R7** | Item-grain **is** recipient-grain, structurally | **Not structural.** `111_email_triage_items_workspace_shared.sql` added `workspace_id` and replaced the RLS policy with `is_email_triage_workspace_owner(workspace_id, auth.uid())` — the item is visible to **every** workspace Owner. Item-grain equals recipient-grain only because the cron pings `row.user_id` alone. A future fan-out to all Owners would collapse under this key — the exact `notifications.ts:722` class. | Decision unchanged (excluding `user_id` is right for the R6 reason); **justification corrected**. Recorded as a named ADR constraint *and* a comment on the repin loop: *the key must be recipient-grain; item-grain suffices only while the send path is single-recipient.* |
| **R8** | The change is confined to app code + one migration | `test/dsar-allowlist-completeness.test.ts` `discoverUserFkTables` (lines 83–103) runs a `while (grew)` fixpoint; `references\s+public\.email_triage_items\s*\(` matches the proposed FK. `.github/workflows/legal-doc-cross-document-gate.yml` lists `dsar-export-allowlist\.ts` as a `surface_pattern` requiring four legal docs, with **no `paths:` filter**. Note the allowlist and `DSAR_TABLE_EXCLUSIONS` live in the **same file**, so an exclusion entry trips the gate identically — the four docs are owed for *touching the file*, not for the kind of entry. | Scope expands by design. Dropping the FK to dodge the lint would delete real referential integrity to evade CI. |
| **R9** | `notifyOfflineUser` failures can drive a compensating delete | Returns `Promise<void>` and **never throws** (fully try/caught to `mirrorNotifyFailure`). No throw to catch. | No release-on-failure. |
| **R10** | Resend `Idempotency-Key` is a cheap second layer | Supported (`resend@^6.12.3`), but `notifyOfflineUser` owns the call and does not thread options; threading means widening `EmailTriageNotificationPayload` across the notification union with exhaustiveness rails — and it covers only the email branch, never push. | **Rejected**, not deferred. |
| **R11** | Migration ordinal | `134_rls_initplan_hotspots.sql` is highest. | **`135_`** — provisional; re-verify against `origin/main` at ship, and sweep this plan + `tasks.md` together if renumbered. |

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) two identical "Statutory item in
your Soleur inbox — action required" emails for one legal deadline, inviting a duplicate or
contradictory response to a regulator or counsel; or — if the guard over-suppresses — (b)
**no deadline ping at all** in the danger band. For `breach-art33` (72 hours) that band is
~3 ticks with no self-healing headroom.

**If this leaks, the user's data is exposed via:** the marker table stores `item_id`, a short
tick string, and a timestamp — **no user id, no email address, no subject, no content**. The
only vector is linkability through the parent item. Service-role-only (RLS enabled, zero
policies), swept at 90 days.

**Brand-survival threshold:** `single-user incident` → `requires_cpo_signoff: true`, and
`user-impact-reviewer` is pulled into review.

## Design

### Guard placement: the cron loop

The insert goes in the `deadline-repin` loop immediately before `notifyOfflineUser`.
`notifyOfflineUser` sends a **push** when the user has subscriptions and only falls back to
email, so cron-site placement suppresses the duplicate **regardless of channel**; guarding at
`resend.emails.send` would leave duplicate *pushes* live. It also has 6 non-test callers,
none of which have a tick identity.

### Fail open on everything except a clean 23505

Only a definitive `23505` may suppress. Every other outcome — an `{error}` return, **a thrown
rejection**, a timeout — dispatches. The two paths are disjoint (a double-fire yields
`23505`; infrastructure trouble yields anything else), so failing open does not reopen the bug.

The **throw** path is load-bearing and easy to miss: an unhandled rejection escapes
`step.run("deadline-repin")`, and under `retries: 0` that is terminal — `send-probe` and
`assert-probe-row` never execute, so the daily ingress liveness probe silently stops. That
inverts the file's own header rationale (*"Step order is LOAD-BEARING"*), which protects the
purge from probe failure but leaves the probe unprotected from repin failure. The insert must
be wrapped so **no** outcome escapes the iteration.

This also covers the deploy race: `web-platform-release.yml` orders `migrate` →
`verify-migrations` → `deploy` but tolerates `migrate` being *skipped*. New code against old
schema hits `42P01`, which is not `23505`, so the guard falls open to today's behavior.
Correct degradation — and another reason the catch must be unconditional.

### The delivery-path hole (found at deepen-plan; changes the design)

Two reviewers independently established the same thing, and it is the sharpest edge in this
change. `notifyOfflineUser` takes the push branch whenever `subscriptions.length > 0` and
reaches email **only** in the `else`. `sendPushNotifications` deletes rows that answer
`410 Gone`. So today there is a **working two-run self-heal**: run 1 pushes to a stale
endpoint, gets 410, prunes the row, delivers nothing; run 2 — the next day, or an operator
manual-trigger the same day — finds zero subscriptions and sends the email.

**The guard destroys that self-heal.** Run 2's marker insert returns `23505` and suppresses.
And this is the guard *working exactly as designed*, so fail-open never reaches it: the
insert was clean. `pinged` incremented on a delivery of nothing.

Three consequences the plan must carry rather than discover at `/work`:

1. **A zero-delivery signal is mandatory** (Phase 2 step 3b). Suppressing on `23505` is sound
   only if the prior marker evidences a *delivery*; it evidences a dispatch *attempt*.
2. **A targeted release verb is mandatory** (Phase 4 step 5). "Post-merge (operator): None"
   was false as first written — there was no way to clear a marker short of hand-written SQL
   against prod, which the operator posture forbids.
3. **A non-410 push failure** (egress-firewall DROP, WNS exclusion — both named in
   `sendPushNotifications`' own comment) never prunes the row, so the email branch is never
   reached and the user receives **nothing, on every tick, forever** while `pinged` reports
   success. Pre-existing, not caused by this change — but the marker now certifies each of
   those non-sends as "sent". Deferred issue #5.

### Marker-before-dispatch: argued, not assumed

The ordering contradicts this plan's own asymmetry (a crash between insert and dispatch loses
that tick; dispatch-first would risk only a duplicate), so it needs an argument rather than an
appeal to `notifyInboxItem`.

It is correct **because of what this issue is about**. The defect is a *concurrent* double-fire
from two schedulers; `concurrency: [{ scope: "fn", limit: 1 }]` is per-Inngest-instance and
does not bind across two instances. Dispatch-first would let both runs send before either
marks — the guard would not guard the very scenario it exists for. Marker-first is the only
ordering that holds under true concurrency.

The accepted cost is a crash window. For the daily band it self-heals next tick (new
`tick_key`); for `'headsup'` it is permanent, which is why the release verb exists.

### Suppression is recorded, never paged

`suppressed > 0` is **not** a fault: `cron/email-ingress-probe.manual-trigger` is a legitimate
second trigger. Paging on it would reproduce the false-page class fixed four commits ago in
`898de92e4`. Benign suppression surfaces in the step return only — the Inngest run history is
the audit trail. The single Sentry signal is the genuinely anomalous one: a marker insert that
failed for a reason other than `23505`.

An earlier draft added a `deadline-repin-all-suppressed` signal for over-suppression. It is
**cut**: `pinged === 0 && suppressed > 0` is exactly what a routine manual-trigger produces
after the cron already pinged the band, so it has no discriminating power. It is therefore not
listed as a mitigation anywhere in this plan.

## Files to Create

- `apps/web-platform/supabase/migrations/135_statutory_repin_send.sql` + `.down.sql`
- `apps/web-platform/test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts`

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts` — the guard.
- `apps/web-platform/test/server/inngest/cron-email-ingress-probe.test.ts` — route the new
  table in the fake; assert the new result field.
- `apps/web-platform/server/dsar-export-allowlist.ts` — `joinVia` entry.
- `docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`,
  `docs/legal/data-protection-disclosure.md`, `knowledge-base/legal/compliance-posture.md`
  — CI-forced (R8).
- `knowledge-base/legal/article-30-register.md` — amend **PA-27** limbs (c), (f), (g). No new PA.
- `knowledge-base/engineering/architecture/domain-model.md` — a `BR-*` rule in the
  `BR-DSAR-1` / `BR-BYOK-1` shape.
- `knowledge-base/engineering/architecture/decisions/ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`
  (frontmatter `adr: 035`) — amend.

## Implementation Phases

Schema contract lands before its consumer
(`2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`).

### Phase 0 — Preconditions

1. Re-verify R1's anchors by content.
2. Confirm `135_` is free against `origin/main`; renumber + sweep plan and `tasks.md` if not.
3. Read `122_inbox_item.sql` for the house preamble: **no top-level `BEGIN`/`COMMIT`**, **no
   `CREATE INDEX CONCURRENTLY`** (SQLSTATE 25001 inside the migration txn).
4. Confirm `outbound-chokepoint.test.ts`'s `RESEND_SEND_ALLOWLIST` is caller-scoped — this
   plan adds no new `resend.emails.send` call site.

### Phase 1 — Migration

`135_statutory_repin_send.sql`:

- Table `public.statutory_repin_send`:
  - `item_id uuid NOT NULL REFERENCES public.email_triage_items(id) ON DELETE CASCADE`
  - `tick_key text NOT NULL` — `'headsup'` or `'daily:YYYY-MM-DD'`
  - `created_at timestamptz NOT NULL DEFAULT now()` — the dispatch instant
  - `PRIMARY KEY (item_id, tick_key)` — `item_id` leads, so the PK index also serves the
    `ON DELETE CASCADE` FK lookup; no separate FK index is needed.
  - `CONSTRAINT statutory_repin_send_tick_key_shape CHECK (tick_key = 'headsup' OR tick_key ~ '^daily:\d{4}-\d{2}-\d{2}$')`
    — bounds an otherwise-unbounded `text` PK component, matching the house style
    (`probe_tokens` uses `CHECK (length(token) BETWEEN 1 AND 128)`). A malformed `tick_key`
    from a future code path is itself an over-suppression vector.
  - **No `user_id` column** (R6).
- `ENABLE ROW LEVEL SECURITY`, **zero policies**, **plus** the explicit
  `REVOKE INSERT/UPDATE/DELETE … FROM PUBLIC, anon, authenticated` defense-in-depth from
  `122_inbox_item.sql`, so a future `CREATE POLICY … FOR ALL` cannot silently open writes.
  Add a `COMMENT ON TABLE` — every table in migrations 102 and 122 carries one.
- New standalone `public.purge_statutory_repin_send()`: deletes rows older than **90 days** —
  derived as `DEADLINE_REPIN_SCAN_WINDOW_DAYS` (60) plus a month of margin, since a marker
  older than the scan window can never be consulted again. Must carry `SECURITY DEFINER`,
  `SET search_path = public, pg_temp`, `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role`
  followed by `GRANT EXECUTE … TO service_role` (102's literal shape), and an explicit
  `RETURNS integer` with `GET DIAGNOSTICS` — §Observability promises a purge count, so the
  return type is load-bearing, not incidental.
- **No index on `created_at`.** The sweep is a seq scan by design: `probe_tokens` is swept by
  the identical predicate with no such index, volume is bounded (~33 markers per statutory
  item), and `132_drop_unused_indexes.sql` establishes the direction against speculative indexes.
- **Do not `CREATE OR REPLACE` `purge_email_triage_items` or `anonymise_email_triage_items`** (R5).
- Header comment records: why retention is explicit (R2), why `tick_key` is branch-derived
  (R3/R4), why `user_id` is absent (R6), and the R7 recipient-grain constraint.
- `.down.sql`: `DROP TABLE IF EXISTS` + `DROP FUNCTION IF EXISTS` (a bare `DROP` aborts the
  whole `--single-transaction` stream if a partial apply left one object missing), **plus the
  `_schema_migrations` ledger delete** —
  `DELETE FROM public._schema_migrations WHERE filename = '135_statutory_repin_send.sql';`.
  House convention per `102_email_triage_items.down.sql` (*"Ledger row. Required for
  re-apply"*): `run-migrations.sh` skips filenames already in the ledger, so omitting it leaves
  135 marked applied and the re-apply silently no-ops. Header comment must state that rollback
  is **intentionally lossy** — dropping the table re-sends one duplicate per in-band item on
  the next tick, which is the safe direction.

### Phase 2 — Guard in the repin loop

1. Compute the run's UTC date **once, before the `for` loop**, and return it from the step so
   it is checkpointed — mirroring `send-probe`'s `sentAt`, which carries a comment explaining
   exactly this hazard. Per-row computation lets a run straddling UTC midnight produce two
   `tick_key`s within one run, reintroducing the duplicate class.
2. Derive `tickKey` from the branch actually taken:
   `daysUntilDue === DEADLINE_REPIN_HEADS_UP_DAY` → `'headsup'`; otherwise `'daily:' + runDateUtc`.
3. Insert `{ item_id: row.id, tick_key }` using the house idiom
   `.insert({…}).select("id").single()` (matches `notifyInboxItem`, and makes the existing
   cron test's fake fail loudly rather than silently — see §Risks).

   **Placement is load-bearing.** The insert goes **after every pre-existing `continue`
   guard** — `if (!row.user_id) continue` (Art. 17 anonymised rows) and the unknown-`rule_id`
   `warnSilentFallback` + `continue` — and immediately before dispatch. A marker written
   before those guards marks a row that is then never pinged, permanently suppressing it:
   exactly the over-suppression this plan calls strictly worse than duplication.

3b. **Zero-delivery signal (new, required).** `notifyOfflineUser` dispatches push **or**
   email, never both, and `sendPushNotifications` `Promise.allSettled`s every send without
   throwing — so a user whose only subscription is stale gets nothing while `pinged`
   increments. Have `sendPushNotifications` return a delivery tally and emit
   `warnSilentFallback` (op `statutory-notify-zero-delivery`) from `notifyOfflineUser` when
   `delivered === 0 && payload.isStatutory`. Without this the guard converts a currently-
   working remediation into silence — see §Design "The delivery-path hole".
4. Wrap the insert in `try/catch` so no outcome escapes the iteration:
   - `(err as { code?: string }).code === "23505"` → `suppressed += 1`; `continue`.
     `server/ws-handler.ts`'s `isContextPathUniqueViolation` documents that supabase-js does
     not always populate `code`; we rely on it only for a PK violation on a plain insert, and
     **anything else falls open** — the safe direction.
   - any other error **or throw** → `warnSilentFallback` (op
     `deadline-repin-marker-insert-failed`) and **fall through to dispatch**.
5. Clean insert → `notifyOfflineUser(...)`; `pinged += 1`.
6. Return `{ pinged, suppressed, scanned, runDateUtc }`; surface `repinSuppressed` on
   `HandlerResult`.

### Phase 3 — Test (RED first, `cq-write-failing-tests-before`)

New file `test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts`.

**Harness contract — the load-bearing part of the issue's fourth acceptance criterion:**

- **Do NOT mock `@/server/notifications`.** The existing cron test does exactly that; copying
  its harness reproduces the defect shape the issue is about. The real module must run.
- Mock the `resend` package with the house vitest-4 idiom — a **`function`-keyword**
  constructor assigning `this.emails = { send: mockResendSend }` (an arrow returning an object
  throws "is not a constructor").
- Mock `web-push`, `@/server/logger`, `@sentry/nextjs`, `@/server/inngest/client`, and
  **`@/server/observability`** — T5 asserts `warnSilentFallback` was called, so the spy must
  exist; ten sibling files under `test/server/inngest/` already mock it.
- The fake returns **`[]` for `push_subscriptions` by default**, which is what makes T1–T4
  count *emails* — `notifyOfflineUser` sends push **or** email, never both. State this
  explicitly; T11 overrides it.
- `beforeEach` must reset the uniqueness `Set` **and** all fake DB state. A marker leaking
  between cases makes T3/T4 fail confusingly rather than vacuously pass.
- The fake `@/lib/supabase/service` must route `email_triage_items`, `probe_tokens`,
  `statutory_repin_send`, `push_subscriptions`, and `auth.admin.getUserById` — the last two
  because the **real** `notifyOfflineUser` now executes — and must **enforce uniqueness** on
  `(item_id, tick_key)` via an in-memory `Set`, returning `23505` on a repeat. Without that
  enforcement every case below is vacuous.
- Both the probe send and the repin send hit the same `mockResendSend`. Disambiguate by the
  **email subject** `"Statutory item in your Soleur inbox — action required"` vs the probe's
  `SOLEUR-PROBE-` prefix — **not** by the cron's `title` (`"Statutory deadline approaching — …"`),
  which is a different string.
- `vi.useFakeTimers()` + `vi.setSystemTime(...)`.

| # | Case | Assertion |
| --- | --- | --- |
| T1 | Double-fire, same day, danger band | Exactly **1** email; second run reports `repinSuppressed === 1`. Also assert the marker is written **before** dispatch (T1 must not pass under send-then-marker) |
| T2 | **T-7 straddle (R4):** boundary 05:55; run D 06:00 and run D+1 05:50 — both compute `daysUntilDue === 7` | Exactly **1** email. The case the calendar-date design failed |
| T3 | **Cadence:** two consecutive days in the danger band | **2** emails |
| T4 | **Distinct items, same day** — parameterized over same-user and different-user | **2** emails each (evidences the issue's "recipients not collapsed" criterion) |
| T5 | **Fail-open, `{error}` shape:** non-23505 error returned | Email **still sent**; `warnSilentFallback` called with op `deadline-repin-marker-insert-failed` |
| T6 | **Fail-open, throw shape:** insert rejects on item 3 of 10 | **All 10 dispatch** — including item 3. Asserting only "items 4–10" would pass even if the throwing item were silently suppressed, which is the fail-*closed* direction AC5 forbids. The run does not die |
| T7 | **DDL pin:** read `135_…sql` — PK is exactly `(item_id, tick_key)`, the FK and the `tick_key` CHECK exist, no pre-existing function is replaced, and `.down.sql` carries the `_schema_migrations` delete | Tier 1 of the house two-tier migration-test convention |
| T7b | **Live-DB tier (gated):** `describe.skipIf(process.env.TENANT_INTEGRATION_TEST !== "1")` — double-insert the same `(item_id, tick_key)` against the real table, assert the surfaced error carries `code === "23505"` | The one contract the in-memory fake **cannot** test — and `server/ws-handler.ts`'s `isContextPathUniqueViolation` exists precisely because supabase-js does not reliably populate `code`. Follow `test/supabase-migrations/126-beta-crm.test.ts`. **Site it under `test/server/`**: `tenant-integration.yml` scopes vitest to `test/server/`, so a gated block elsewhere never runs. No new workflow (#3221 stays deferred) |
| T8 | **Harness negative control:** assert the fake itself returns `23505` on a repeat `(item_id, tick_key)` and no error for a distinct `item_id` or distinct `tick_key` | The harness contract says "without that enforcement every case below is vacuous" — this makes that sentence a test instead of a comment. Committable, unlike the manual mutation step |
| T9 | **Once-per-run date:** a single run whose clock crosses UTC midnight mid-loop | All markers in that run share ONE `tick_key`. This is a listed Sharp Edge with zero coverage — T3 uses two separate runs and structurally cannot catch per-row computation |
| T10 | **Marker placement:** a row hitting `!row.user_id` and a row hitting unknown-`rule_id` | **No marker written** for either; a later run for a now-valid row still dispatches. A marker without a dispatch is permanent over-suppression |
| T11 | **Push channel:** a user WITH push subscriptions, double-fire | Exactly **one** `webpush.sendNotification`. §Design justifies cron-site placement precisely because guarding at `resend` would leave duplicate pushes live — currently untested |

**Mutation control (verification step, not an AC):** delete the `23505` branch and confirm T1
reds. This is a manual procedure, not a committable test — recorded as a Phase 3 step so it is
actually performed, rather than as a checkbox that gets ticked regardless.

### Phase 4 — Compliance surfaces (CI-forced)

1. `dsar-export-allowlist.ts`: add `statutory_repin_send` to **`DSAR_TABLE_EXCLUSIONS`**, not
   the allowlist, with the reason *"Operational send-suppression marker. No user-provided
   content and no direct subject identifier — only an item FK, a tick string, and a timestamp.
   The underlying statutory item is exported via `email_triage_items`."*

   **Why not `joinVia`** (this reverses an earlier draft): `joinVia` is **not data-driven**.
   `server/dsar-export.ts` carries hand-written per-table blocks (`-- messages (joinVia
   conversations)`, `-- message_attachments (joinVia messages)`), and
   `test/dsar-worker-per-row-where.test.ts` iterates `Object.keys(DSAR_TABLE_ALLOWLIST)` and
   asserts each has a `service.from("<table>")` chain in the worker, failing with *"silent
   absence is an Art. 15 completeness regression."* An allowlist entry without a worker block
   would export nothing **and** hard-fail CI. Exclusion is the honest shape for a payload this
   thin; precedent is `runtime_mint_intent` in the same file.
2. Update the four cross-document-gate files — minimal and truthful: an internal
   send-suppression marker, 90-day retention, no new recipient or transfer. (Owed for
   *touching the file*; an exclusion entry trips the gate identically to an allowlist entry.)
3. Art. 30 **PA-27** limbs (c)/(f)/(g). **No new PA** — inflating the register for a TOM detail
   degrades it.
4. `domain-model.md`: a `BR-*` rule in the `BR-DSAR-1` shape.
5. **Operator release verb.** Extend `purge_statutory_repin_send()` with an optional
   `p_item_id uuid DEFAULT NULL` — when supplied, delete that item's markers instead of
   sweeping by age. Expose it the way `soleur:trigger-cron` reaches the cron, so an operator
   can clear a marker whose dispatch delivered nothing (§Design, "The delivery-path hole")
   without hand-written SQL against prod. Without this the plan has no recovery path and
   `hr-never-label-any-step-as-manual-without` / `hr-no-ssh-fallback-in-runbooks` are violated.

### Phase 5 — ADR amendment

See §Architecture Decision.

### Phase 6 — Verification

```
cd apps/web-platform && ./node_modules/.bin/vitest run \
  test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts \
  test/server/inngest/cron-email-ingress-probe.test.ts \
  test/notifications.test.ts test/server/outbound-chokepoint.test.ts \
  test/dsar-allowlist-completeness.test.ts test/server/email-triage-worm.test.ts
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit
```

Full suite before ship. `bunfig.toml` sets `pathIgnorePatterns = ["**"]` — vitest only, never
`bun test`. Typecheck is the in-package `tsc`, never `npm run -w …` (the repo root declares no
`workspaces`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** Migration hygiene: no `CONCURRENTLY`, no top-level `BEGIN`/`COMMIT`.
- [x] **AC2** PK is exactly `(item_id, tick_key)`; RLS enabled with zero policies; the FK to
      `email_triage_items` is present; there is **no** `user_id` column.
- [x] **AC3** No pre-existing function is replaced. Verify:
      `grep -cE 'CREATE OR REPLACE FUNCTION public\.(purge|anonymise)_email_triage_items' <migration>`
      returns `0`. **Verified: 0.**
      *(Form corrected twice. The original `grep -c 'statutory_repin_send' ≥ 2` was vacuous —
      the migration creates that table, so it self-matches. Its replacement, a bare-token
      `grep -cE 'purge_email_triage_items|anonymise_email_triage_items'`, then returned **1**
      against a correct migration: the header comment explains at length WHY those two
      functions are deliberately NOT replaced, and a bare-token grep cannot tell an
      explanation from a call. That is `cq-assert-anchor-not-bare-token` — anchor on the
      syntactic construct a comment cannot produce (`CREATE OR REPLACE FUNCTION public.…`),
      never on a name the file also legitimately discusses. The comment is load-bearing
      documentation and was kept; the assertion was fixed instead. Test T7 already used the
      correct anchored form.)*
- [x] **AC4** `purge_statutory_repin_send()` declares `SECURITY DEFINER`,
      `SET search_path = public, pg_temp`, and the `REVOKE` / `GRANT EXECUTE … TO service_role` pair.
- [x] **AC5** Suppression occurs **only** on `23505`. Every other outcome — `{error}` return
      **or** thrown rejection — dispatches. *(Supersedes an earlier AC5/AC6 pair that
      contradicted each other: "dispatch only on a clean insert" forbade the fail-open the
      design rests on.)*
- [x] **AC6** T2 passes — the T-7 heads-up sends exactly once across a calendar-day straddle.
- [x] **AC7** T6 passes — a thrown insert does not kill the run; later items still dispatch.
- [x] **AC8** T1 passes and asserts marker-before-dispatch ordering.
- [x] **AC9** The new test never **mocks** the notifications module. Verify:
      `grep -cE 'vi\.(do)?mock\([^)]*server/notifications' <new-test-file> || true` returns `0`.
      **Verified: 0.**
      *(Form corrected. The original bare-name `grep -c "@/server/notifications"` returned
      **1** against a correct test file — the header comment states, as the file's central
      contract, that it deliberately does NOT mock that module. Same trap as AC3: a bare-token
      grep matches the explanation of the invariant as readily as a violation of it. The
      widened regex covers the multi-line, single-quoted, and `vi.doMock` forms the original
      note was rightly worried about, while anchoring on the CALL rather than the name.
      `|| true` retained because `grep -c` exits 1 on zero matches.)*
- [x] **AC10** `dsar-allowlist-completeness.test.ts` passes, and T8 asserts the table is
      actually discovered — not merely that the suite is green.
- [x] **AC11** The four cross-document-gate files are updated; the gate is green.
- [x] **AC12** Art. 30 PA-27 limbs (c)/(f)/(g) amended; no new PA row.
- [x] **AC13** The ADR file with frontmatter `adr: 035`
      (`ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`) is amended —
      assert it **appears** in `git diff --name-only origin/main...HEAD`.
      `ADR-035-template-registry-code-static.md` gains **no decision content**: if it appears
      in the diff at all, its added lines must number ≤ 2 and every one must reference
      `ADR-037` (the permitted see-also pointer). Verify with
      `git diff --unified=0 origin/main...HEAD -- <that-file> | grep -c '^+[^+]'`.
      *(Use the **three-dot** form throughout — two-dot compares against origin/main's tip and
      false-positives on anything that landed after the branch point; the cross-document gate
      documents this exact trap. A filename-absence assertion would be wrong here, since the
      pointer is permitted — assert the shape of the change, not its absence.)*
- [x] **AC14** No new Sentry paging rule (`apps/web-platform/infra/sentry/` untouched).
- [x] **AC15** PR body uses `Closes #6781`.

### Post-merge (operator)

None. Migration apply and container restart both ride `web-platform-release.yml`.

## Observability

```yaml
liveness_signal:
  what: "deadline-repin step return gains `suppressed` and `runDateUtc` alongside `pinged`/`scanned`; surfaced as repinSuppressed on HandlerResult"
  cadence: "daily, 0 6 * * * (unchanged)"
  alert_target: "existing Sentry cron monitor cron-email-ingress-probe. NO new paging rule."
  configured_in: "apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts"
error_reporting:
  destination: "Sentry via warnSilentFallback (server/observability.ts), which promotes the SQLSTATE as a queryable pg_code tag"
  fail_loud: true
failure_modes:
  - mode: "benign suppression — operator manual-trigger after the cron already pinged"
    detection: "suppressed > 0 && pinged > 0"
    alert_route: "step return only, visible in Inngest run history. Deliberately NOT Sentry — manual-trigger is a legitimate second trigger and paging here reproduces the 898de92e4 false-page class."
  - mode: "marker insert fails for a reason other than 23505, including a thrown rejection"
    detection: "catch block; code !== 23505"
    alert_route: "Sentry op=deadline-repin-marker-insert-failed; dispatch proceeds (fail open)"
  - mode: "new code meets old schema (migrate skipped, deploy proceeds)"
    detection: "insert returns 42P01 undefined_table"
    alert_route: "same fail-open path; degrades to today's behavior. Documented, not alarmed."
  - mode: "STATUTORY ZERO-DELIVERY — marker written, nothing delivered (stale push endpoints)"
    detection: "sendPushNotifications returns a delivery tally; notifyOfflineUser emits when delivered === 0 && payload.isStatutory"
    alert_route: "Sentry op=statutory-notify-zero-delivery (warn). NEW SIGNAL — REQUIRED. mirrorNotifyFailure does NOT cover this: it is reachable only from notifyOfflineUser's outer catch, the email-lookup miss, and the sendEmail* error branches. sendPushNotifications Promise.allSettle()s every send and never throws, and its 410 branch is log.info + delete with no Sentry at all. Today this mode emits NOTHING."
  - mode: "marker table grows without bound"
    detection: "purge_statutory_repin_send() count, carried in the per-run infoSilentFallback payload below"
    alert_route: "Sentry op=deadline-repin-sweep-complete (info)"
logs:
  where: "Sentry, via a per-run infoSilentFallback(null, { feature: 'email-triage', op: 'deadline-repin-sweep-complete', extra: { pinged, suppressed, scanned, runDateUtc, purgedMarkers } }) — mirroring cron-workspace-gc.ts. NOT pino stdout: apps/web-platform/infra/vector.toml [transforms.app_container_warn_filter] keeps only level_int >= 40, so INFO and step-return values are DROPPED and never reach Better Stack. An earlier draft of this plan claimed these counters reach Better Stack source 2457081 — that claim was false. WARN-level events (the two ops above) do clear the filter and reach both."
  retention: "Sentry retention (existing). Marker rows: explicit 90-day sweep via purge_statutory_repin_send (NOT cascade — R2)."
discoverability_test:
  command: "bash -c 'doppler run -p soleur -c prd -- scripts/sentry-issue.sh op:deadline-repin-sweep-complete'  # after firing cron/email-ingress-probe.manual-trigger via soleur:trigger-cron"
  expected_output: "The most recent run's counter payload (pinged / suppressed / scanned / runDateUtc / purgedMarkers). No SSH. The manual-trigger event is auto-allowlisted via EXPECTED_CRON_FUNCTIONS in lib/inngest/manual-trigger-allowlist.ts. NOTE: the vitest suite is a pre-merge gate, NOT the discoverability probe — a test proves the code works on the author's laptop, not that the signal is visible in prod from a keyboard."
```

### Affected-surface note (§2.9.2)

The Inngest cron worker is not directly inspectable. `suppressed`/`pinged`/`scanned` are
in-surface counters emitted from the worker and discriminate the competing hypotheses:
`suppressed>0, pinged>0` = benign manual-trigger or a real double-fire; `suppressed=0,
pinged=0, scanned>0` = nothing in the danger band. **Known limit:** `pinged` counts dispatch
*attempts*, not deliveries — `notifyOfflineUser` returns `void` on a stale-push or
missing-email path, so these counters cannot distinguish "pinged and delivered" from "pinged
and dropped."

## Architecture Decision (ADR/C4)

### ADR

**Amend** `ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`
(frontmatter `adr: 035`). Record:

1. The idiom extends from **ingest** dedup to **send** dedup.
2. The rejected alternative *"Single-source-ref-per-table"* is **not** violated: it presumed a
   canonical row that can carry the key. `email_triage_items` is WORM, and — decisively — this
   is a **1:N** relation (one item × many ticks) that a column cannot express at any cost.
   ADR-035's `messages.source_ref` is 1:1. Different shape, different mechanism. House
   precedent for a send-side marker exists in `outbound_sends`.
3. The rejection of an *"Explicit TTL daemon"* is honored — the sweep is a plain RPC called
   from an existing cron step, adding no scheduled function.
4. **The tick component must match the cadence's own shape:** a constant for a one-shot, a date
   for a daily ping. A date-valued key on a countdown predicate straddles calendar days (R4).
   This generalizes `notifications.ts:722` beyond "namespace per `user_id`".
5. **Named constraint (R7):** the key must be *recipient*-grain. Item-grain suffices only while
   the send path is single-recipient; `111_…workspace_shared.sql` already makes items visible
   to every workspace Owner, so a future fan-out must re-key.

**Corrected from an earlier draft:** the claim "no new ordinal, so no collision risk" was wrong
— the collision already exists and is systemic (`ADR-035-template-registry` carries
`adr: ADR-035` while `ADR-037-…` carries `adr: 035`; filenames ADR-030 ×2, ADR-031 ×2, ADR-033
×3, ADR-038 ×2; two frontmatter formats in use). A one-line see-also pointer on the
template-registry ADR is the cheap remedy; corpus-wide normalization is deferred (#3 below).

### C4 views

**No `.c4` edit required.** All three model files were read (`model.c4` 542 lines, `views.c4`
62, `spec.c4` 54) and enumerated: **external human actors** — `emailSender` (`model.c4:14`)
and `founder` (`:9`, whose description already covers multi-Owner email-triage) both present;
**external systems** — `resend` (`:254`) present, already described as "transactional outbound
(statutory triage notifications)"; **containers** — the triage tables live inside the generic
`supabase` database element and no element exists for `email_triage_items`, so a sibling table
adds none; **relationships** — `webapp -> resend` (`:337`) and `api -> resend` (`:422`) both
exist, and this change alters only *how often* that edge fires; **falsified descriptions** —
none (`operationalInbox`'s "SEPARATE from the email-triage WORM statutory ledger" stays true).

Engaging the counter-precedent: the model *does* sometimes promote a migration-scoped table to
its own element (`operationalInbox`, `technology "Supabase (inbox_item, mig 122)"`). The
conclusion survives it — that promotion carries a new external relationship and a distinct
trust boundary; a send-suppression marker carries neither.

## Open Code-Review Overlap

61 open `code-review` issues queried; none reference `server/notifications.ts`,
`cron-email-ingress-probe`, or `ADR-035`. Two match `supabase/migrations` generically —
**#3220** (postmerge verification of trigger-bearing migrations; migration 135 creates no
triggers) and **#3221** (nightly env-gated integration tests). Both **acknowledged**; both
remain open.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO), plus a `soleur:gdpr-gate`
run (Phase 2.7) and a 6-agent plan-review panel.

### Engineering (CTO)

**Status:** reviewed. Guard placement correct; concurrency fine; ADR divergence legitimate. Two
findings broke the first draft — retention-by-cascade is false (R2), and `user_id` in the key
is both an un-erasable residual and a subtle weakening (R6/R7). Also rejected `daysUntilDue`
(R3) and the Resend key (R10), and flagged that a Sentry signal on `suppressed>0` would
false-page on manual-trigger.

### Legal (CLO)

**Status:** reviewed. Seven blocking items, all folded in: fail-open on non-23505; the tick must
carry a date; DSAR classification is CI-enforced; retention must be *declared*, not inherited;
PA-27 limbs (c)/(f)/(g) with no new PA; suppression recorded without paging. Sharpened the harm
asymmetry — the `breach-art33` 72-hour clock lives entirely inside the daily band. Item 8
(reliance framing on the statutory email copy) is P2 and separable → deferred issue #1.

### GDPR Gate (Phase 2.7)

**Status:** reviewed. **No Critical findings** — no Art. 9 escalation, no `compliance-posture.md`
Active Items write, no `compliance/critical` issue. Four Important (Art. 17 erasure gap,
Art. 5(1)(e) cascade carve-out, Art. 15 DSAR lint, Art. 6 annotation) folded into Phases 1 and
4 — the first now dissolved outright by dropping `user_id` (R6). Confirmed
`breach`/`dsar`/`regulator` classify the controller's legal-process posture, not special
categories: **Art. 9 does not apply.**

> Advisory only, heuristic. Not legal review.

### Plan-review panel (6 agents)

**Convergent findings.** DHH + code-simplicity both demanded `user_id` be cut; code-simplicity
found `joinVia`, which preserves Art. 15 where an exclusion entry would have lost it. Three
agents reached "do not `CREATE OR REPLACE`" by three different routes (security-attribute drop,
`GET DIAGNOSTICS` clobber, fail-loud-step coupling) — per the plan-review rule that when both
panels fire on one scope, prefer delete, both RPC amendments were removed.

**Independent P0s.** spec-flow and architecture-strategist separately found the unhandled
**throw** path. Kieran found the T-7 calendar-date failure (R4) that every earlier reviewer,
including this plan's author, had missed.

**Author errors, recorded rather than quietly fixed.** A Risks-table mitigation claiming the
existing cron test's fake "throws `unexpected table`" was **fabricated** — verified zero
occurrences; the fake accepts any table and returns `{ data: [], error: null }`, i.e. a clean
insert, so the guard would have been exercised but entirely unverified. AC3's grep was vacuous.
AC5/AC6 contradicted each other. AC13's diff was two-dot. R7's structural justification was wrong.

### Product/UX Gate

**Tier:** none — the mechanical UI-surface override does not fire (no `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit). Email copy is unchanged; the
only user-visible delta is the absence of a duplicate. No wireframe required. CPO participation
is driven by the `single-user incident` threshold, not a UI surface.

**Decision:** reviewed
**Agents invoked:** cto, clo, cpo, gdpr-gate, dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer
**Skipped specialists:** cmo, ux-design-lead — relevance gate did not activate (no UI surface, no market/brand copy in scope)
**Pencil available:** N/A (no UI surface)

#### CPO conditions

Sign-off was **GRANTED WITH CONDITIONS** on the design. Dispositions:

| # | Condition | Disposition |
| --- | --- | --- |
| C1 | Catch **only** 23505 | **Folded in** — AC5 |
| C2 | Band-split fail-open (skip at T-7, send in band) | **Not adopted — UPHELD by CPO ruling 2026-07-20.** Sends unconditionally. The T-7 arm is a structural one-shot: fail-open suppression there yields *no heads-up ever*, since the next tick no longer satisfies `daysUntilDue === DEADLINE_REPIN_HEADS_UP_DAY`. The likeliest fail-open trigger — the `42P01` deploy race — is correlated, so it would drop the heads-up for every T-7 item that day at once, with no self-heal. A duplicate T-7 email occurs only on the already-anomalous, already-Sentry-alerted fail-open path (ordinary double-fire yields `23505` and suppresses correctly) and is the cheaper failure under the governing asymmetry |
| C3 | No release-on-failure; T-7 loss must be visible | **Folded in** — R9; `mirrorNotifyFailure` surfaces it |
| C4 | Marker covered by erasure and swept | **Folded in, now structural** — no `user_id` to erase (R6), plus the 90-day sweep |
| C5 | Uniqueness per-recipient, never workspace-scoped | **AMENDED by CPO ruling 2026-07-20.** Property satisfied and justification corrected — item-grain is recipient-grain *today*, but R7 shows that is a property of the send path, not of structure. ADR named constraint + loop comment retained, **plus T12** (task 3.12e) as a tripwire: documentation does not fail, and if a future fan-out lands, the first Owner's marker would suppress every other Owner — N−1 recipients get silence on a statutory deadline while `pinged` reports success. No schema change; re-adding a recipient column stays settled per R6 (Art. 17 residual) |
| C6 | Test drives the real send path, asserts both directions | **Folded in** — Phase 3 harness contract, T1 + T5/T6 |

> **Ruling returned 2026-07-20.** C2 **UPHELD** (no change required). C5 **AMENDED** — the
> property stands, but the CPO required a test tripwire rather than documentation alone; T12
> (task 3.12e) is the result and blocks PR-ready. The CPO also struck "halves the code paths"
> from C2's rationale: implementation path-count is never an acceptable reason to move risk onto
> a user holding a statutory deadline, and here it pointed the right way only by coincidence.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **Over-suppression silences a statutory deadline** (brand-survival) | Branch-derived `tick_key`; fail-open on every non-23505 outcome including throws; T2/T3/T4 cover each cadence |
| A thrown insert kills the run and stops the ingress probe | Unconditional `try/catch`; T6 |
| Existing cron test exercises the guard but verifies nothing | Its fake accepts **any** table and returns `{data:[],error:null}` — it does **not** throw (an earlier draft of this plan claimed otherwise). Mandating `.insert(…).select("id").single()` in Phase 2 makes it fail loudly, because the fake's chain has no `single` |
| In-memory fake drifts from the real constraint | T7 pins the PK from the migration SQL |
| Guard is a no-op and the suite still green | Phase 3 mutation-control step |
| DSAR table silently not discovered (`parseTables` regex) | T8 asserts membership in `discoverUserFkTables` output |
| Migration ordinal 135 claimed by a sibling PR | Re-verify at ship; renumber and sweep plan + `tasks.md` together |
| Deploy race (migrate skipped, new code live) | `42P01` is not `23505` → fail open → today's behavior. Documented, not alarmed |

## Alternatives Considered

| Alternative | Verdict |
| --- | --- |
| **Inngest `idempotency` config** | Rejected — keys off event data; a cron has none, and it would also suppress the load-bearing `retention-purge` step |
| **`tick_key = daysUntilDue`** | Rejected (R3) — same-day duplicate across cron + manual-trigger |
| **`tick_key` = UTC calendar date alone** | Rejected (R4) — correct for the daily band, but the T-7 one-shot straddles two dates |
| **`user_id` in the key** | Rejected (R6/R7) — Art. 17 residual and a weaker key; `joinVia` preserves Art. 15 without it |
| **Column on `email_triage_items`** | Rejected — WORM table, and 1:N cannot be expressed by a column |
| **Reuse `inbox_item`** | Rejected — workspace-scoped index, and a row creates a *user-visible* inbox entry (ADR-085): a product change, not a guard |
| **Fold the sweep into `purge_email_triage_items`** | Rejected (R5) — three independent hazards; a standalone RPC has none |
| **Retention by `ON DELETE CASCADE` alone** | Rejected (R2) — the parent is never deleted for statutory rows |
| **Resend `Idempotency-Key`** | Rejected (R10) — union widening, email-branch only |
| **Release-on-failure compensating delete** | Rejected (R9) — `notifyOfflineUser` never throws |

## Deferred — follow-up issues to file

Per `wg-when-deferring-a-capability-create-a`, each needs an issue **before this PR is ready**:

1. **Statutory email reliance framing** (CLO item 8, P2). No "not legal advice" disclaimer
   exists (`grep -rn "legal advice" apps/web-platform/` → 0 hits), while the copy presents a
   *computed* date as **the** statutory deadline and Art. 33's 72 hours runs from *awareness*,
   not receipt. Making this backstop more reliable deepens detrimental reliance.
2. **`daysUntilDue === 7` exact-match fragility.** A jittered run can skip 7 entirely — run at
   D−8 06:00:10 → `8`, run at D−7 06:00:40 → `6`, so the heads-up **silently never fires**.
   This lives in the *predicate*, not the key; the guard is correct either way, which is what
   makes it cleanly separable. Also note the T-7 arm is **dead code for `breach-art33`** (72h →
   `daysUntilDue` maxes at 2).
3. **ADR ordinal/frontmatter normalization.** Duplicate filenames and two frontmatter formats
   make `ADR-NNN` greps ambiguous corpus-wide.
4. **60-day scan cliff.** An item acknowledged more than `DEADLINE_REPIN_SCAN_WINDOW_DAYS` after
   receipt gets **zero pings, ever**, with no counter. Fold the excluded-row count into the
   per-run `infoSilentFallback` payload rather than a separate emit.
5. **Non-410 push failure = permanent total silence.** A subscription that fails with anything
   other than `410` is never pruned, so `subscriptions.length > 0` holds forever, the email
   branch is never reached, and the user receives **no statutory notice on any tick** while
   `pinged` reports success. Pre-existing (not caused by this change), but the marker now
   certifies each non-send as sent. The zero-delivery signal in Phase 2 step 3b makes it
   *visible*; actually fixing it (fall back to email on non-410 push failure) is its own issue.

## Blocking before PR-ready

- [x] **CPO ruling on C2 and C5 has returned** (2026-07-20). C2 UPHELD, C5 AMENDED. See the
      CPO conditions table above.
- [x] **T12 (task 3.12e) is implemented and green.** This is the C5 amendment and is the one
      thing the CPO ruling added as a PR-ready blocker.
- [x] All five deferred issues above are filed: #6798 (reliance framing), #6799 (T-7
      equality fragility), #6800 (ADR ordinals), #6801 (60-day scan cliff), #6802 (non-410
      push silence).

## Sharp Edges

- **`ADR-035` is a frontmatter value, not a filename.** The dedup ADR is `ADR-037-…md`.
- **Do not mock `@/server/notifications` in the new test.** That is the fixture seam the issue's
  fourth criterion forbids — and the *existing* cron test does it.
- **Do not `CREATE OR REPLACE` `purge_email_triage_items` or `anonymise_email_triage_items`.**
  Security attributes do not survive a replace and both AP-018 tiers are blind to the drop.
- **Compute the run date once, before the loop, and checkpoint it** — mirroring `send-probe`'s
  `sentAt`. Per-row computation reintroduces the duplicate class across UTC midnight.
- **`ON DELETE CASCADE` is decorative for retention here.** Statutory parents are never purged.
- **A `CHECK` constraint does NOT break DSAR `parseTables`.** An earlier draft of this plan
  warned that a trailing `CHECK (…)` before `);` was a known failure shape. That was
  **empirically false** — the actual regex was run against three DDL variants and the whole
  corpus (51/51 tables parsed, zero missed), and migration 102's own `email_triage_items`
  already ends in a trailing `CONSTRAINT … CHECK` and parses fine. The lazy `[\s\S]*?\)\s*;`
  cannot terminate early because a CHECK's closing paren is followed by `,` or `\n)`, never
  `;`. Add the constraint.
- **`joinVia` is not data-driven.** An allowlist entry without a hand-written block in
  `server/dsar-export.ts` exports nothing and hard-fails `dsar-worker-per-row-where.test.ts`.
- **`pinged` counts dispatch attempts, not deliveries** — and a stale-push user gets nothing
  while it increments. Never cite it as evidence of notice.
- **Touching `dsar-export-allowlist.ts` forces four legal-doc edits** — and an exclusion entry
  trips the gate identically, since both maps live in that one file.
- **Do not add a Sentry paging rule for suppression** — `manual-trigger` makes it benign.
- Ordinal `135` is provisional. Typecheck with the in-package `tsc`; tests are vitest only.
- The vitest-4 `resend` constructor mock must use the `function` keyword and assign to `this`.
