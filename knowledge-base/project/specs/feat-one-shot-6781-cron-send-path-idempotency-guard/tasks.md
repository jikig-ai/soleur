---
feature: feat-one-shot-6781-cron-send-path-idempotency-guard
issue: 6781
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-20-fix-cron-statutory-repin-idempotency-guard-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — cron statutory-repin idempotency guard (#6781)

Derived from the finalized plan. Phase order is load-bearing: the schema contract lands
before its consumer.

## Phase 0 — Preconditions

- [x] 0.1 Re-verify the six `server/notifications.ts` anchors by content (not line number).
- [x] 0.2 Confirm migration ordinal `135_` is still free against `origin/main`. If taken,
      renumber and sweep this file **and** the plan together.
- [x] 0.3 Read `supabase/migrations/122_inbox_item.sql` for the house preamble — no top-level
      `BEGIN`/`COMMIT`, no `CREATE INDEX CONCURRENTLY`.
- [x] 0.4 Confirm `test/server/outbound-chokepoint.test.ts`'s `RESEND_SEND_ALLOWLIST` is
      caller-scoped (this change adds no new `resend.emails.send` call site).

## Phase 1 — Migration (schema contract first)

- [x] 1.1 Create `supabase/migrations/135_statutory_repin_send.sql`:
      table `public.statutory_repin_send` with `item_id uuid NOT NULL REFERENCES
      public.email_triage_items(id) ON DELETE CASCADE`, `tick_key text NOT NULL`,
      `created_at timestamptz NOT NULL DEFAULT now()`, `PRIMARY KEY (item_id, tick_key)`.
      **No `user_id` column.**
- [x] 1.2 `ENABLE ROW LEVEL SECURITY` with **zero** policies (service-role only).
- [x] 1.3 Add standalone `public.purge_statutory_repin_send(p_item_id uuid DEFAULT NULL)` —
      90-day sweep, or targeted delete when p_item_id is supplied (the operator release verb).
      `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `REVOKE ALL … FROM PUBLIC, anon,
      authenticated, service_role`, `GRANT EXECUTE … TO service_role`, `RETURNS integer`.
- [x] 1.3b Add the `tick_key` CHECK constraint ('headsup' OR '^daily:\d{4}-\d{2}-\d{2}$') and
      the 122-style explicit REVOKEs + `COMMENT ON TABLE`. (A CHECK does NOT break DSAR
      parseTables — verified 51/51 tables.)
- [x] 1.4 **Do NOT `CREATE OR REPLACE` `purge_email_triage_items` or
      `anonymise_email_triage_items`.** (Security attributes do not survive a replace; both
      AP-018 guard tiers are blind to the drop.)
- [x] 1.5 Header comment: explicit retention (not cascade), branch-derived `tick_key`, absent
      `user_id`, and the recipient-grain constraint.
- [x] 1.6 Create `135_statutory_repin_send.down.sql` — `DROP TABLE IF EXISTS` +
      `DROP FUNCTION IF EXISTS` + **the `_schema_migrations` ledger delete** (required for
      re-apply, per 102's down file), with a header noting rollback is intentionally lossy.

## Phase 2 — Guard in the repin loop

File: `server/inngest/functions/cron-email-ingress-probe.ts`, step `deadline-repin`.

- [x] 2.1 Compute the run's UTC date **once, before the `for` loop**; return it from the step
      so it is checkpointed (mirror `send-probe`'s `sentAt`).
- [x] 2.2 Derive `tickKey`: `daysUntilDue === DEADLINE_REPIN_HEADS_UP_DAY` → `'headsup'`;
      otherwise `'daily:' + runDateUtc`.
- [x] 2.3 Insert `{ item_id, tick_key }` via `.insert({…}).select("id").single()` (house idiom;
      also makes the existing cron test's fake fail loudly). **Placement: after EVERY
      pre-existing `continue` guard** (`!row.user_id`, unknown `rule_id`) and immediately
      before dispatch — a marker before those guards permanently suppresses the row.
- [x] 2.3b Zero-delivery signal: have `sendPushNotifications` return a delivery tally; emit
      `warnSilentFallback` op `statutory-notify-zero-delivery` from `notifyOfflineUser` when
      `delivered === 0 && payload.isStatutory`.
- [x] 2.4 Wrap the insert in `try/catch` so no outcome escapes the iteration.
- [x] 2.5 `code === "23505"` → `suppressed += 1`; `continue`.
- [x] 2.6 Any other error **or throw** → `warnSilentFallback` (op
      `deadline-repin-marker-insert-failed`) and **fall through to dispatch** (fail open).
- [x] 2.7 Clean insert → `notifyOfflineUser(...)`; `pinged += 1`.
- [x] 2.8 Return `{ pinged, suppressed, scanned, runDateUtc }`; surface `repinSuppressed` on
      `HandlerResult`. Emit the per-run record via `infoSilentFallback` op
      `deadline-repin-sweep-complete` — NOT pino stdout (Vector drops level_int < 40).
- [x] 2.9 Add the recipient-grain constraint comment on the loop (item-grain suffices only
      while the send path is single-recipient).
- [x] 2.10 Call `purge_statutory_repin_send()` from the existing `retention-purge` step.
- [x] 2.11 **Expose the operator RELEASE verb without SSH or prod SQL.** Recovered at review
      time — the plan required this (§Phase 4 step 5, citing
      `hr-no-ssh-fallback-in-runbooks` + `hr-never-label-any-step-as-manual-without`) and the
      Phase-4 renumbering into legal-doc tasks silently dropped it. It was NOT deferred; it was
      lost. Without it the `statutory-notify-zero-delivery` alarm names a problem the operator
      has no lever to fix.
      Wired through the cron's EXISTING manual-trigger event, since
      `/api/internal/trigger-cron` already forwards `event.data`:
      `{"name":"cron/email-ingress-probe.manual-trigger","data":{"release_item_id":"<uuid>"}}`.
      UUID-validated at the handler (the route is a dumb pass-through), audit-logged, and it
      returns `{ itemId, cleared }` so a 0 answers "why did nothing re-send?".
      Covered by T14 / T14b / T14c.

## Phase 3 — Tests (RED first)

New file: `test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts`.

- [x] 3.1 Harness: **do not** mock `@/server/notifications`. Mock the `resend` package with a
      `function`-keyword constructor assigning `this.emails = { send: mockResendSend }`.
- [x] 3.2 Mock `web-push`, `@/server/logger`, `@sentry/nextjs`, `@/server/inngest/client`.
- [x] 3.3 Fake `@/lib/supabase/service` routing `email_triage_items`, `probe_tokens`,
      `statutory_repin_send`, `push_subscriptions`, `auth.admin.getUserById`; it **must
      enforce uniqueness** on `(item_id, tick_key)` and return `23505` on a repeat.
- [x] 3.4 Disambiguate sends by **email subject** (`"Statutory item in your Soleur inbox —
      action required"` vs `SOLEUR-PROBE-`), not by the cron's `title`.
- [x] 3.5 T1 — double-fire same day → 1 email; `repinSuppressed === 1`; assert
      marker-before-dispatch ordering.
- [x] 3.6 T2 — T-7 straddle (boundary 05:55; runs D 06:00 and D+1 05:50) → 1 email.
- [x] 3.7 T3 — two consecutive danger-band days → 2 emails.
- [x] 3.8 T4 — two distinct items same day, parameterized same-user / different-user → 2 each.
- [x] 3.9 T5 — fail-open on a non-23505 `{error}` return → email still sent + Sentry op.
- [x] 3.10 T6 — fail-open on a **thrown** insert (item 3 of 10) → **all 10 dispatch, including
      item 3**, and the run does not die. Asserting only "items 4–10" would pass even if the
      throwing item were silently suppressed — the fail-*closed* direction AC5 forbids.
      (Corrected per CPO ruling 2026-07-20: this task previously encoded the weaker "items 4–10"
      assertion that the plan's T6 row and AC7 explicitly reject.)
- [x] 3.11 T7 — DDL pin (PK, FK, CHECK, ledger delete in down file, no pre-existing function
      replaced), following `test/supabase-migrations/126-beta-crm.test.ts`.
- [x] 3.11b T7b — gated live-DB tier (`TENANT_INTEGRATION_TEST=1`): double-insert against the
      real table, assert `code === "23505"`. Site under `test/server/` (tenant-integration.yml
      scopes vitest there).
- [x] 3.12 T8 — harness negative control: the fake itself returns 23505 on a repeat and no
      error for distinct item_id / distinct tick_key.
- [x] 3.12b T9 — single run crossing UTC midnight mid-loop yields ONE tick_key.
- [x] 3.12c T10 — rows hitting `!row.user_id` / unknown-rule guards write NO marker.
- [x] 3.12d T11 — push-subscribed user, double-fire: exactly one `webpush.sendNotification`.
- [x] 3.15 T13/T13b — the marker insert names no column the table lacks (42703 tripwire), with
      the fake's column-validation as its negative control.
- [x] 3.16 T14/T14b/T14c — operator release verb: clears + re-arms, refuses a non-uuid, and is
      absent on a scheduled run.
- [x] 3.17 T9b/T9c — mixed-cadence run and the OVERDUE bucket, neither of which any fixture
      instantiated (the overdue path is the one the SUT calls "must never be silent").
- [x] 3.12e T12 — **single-recipient send path (R7 tripwire)**. Required by CPO ruling
      2026-07-20 (condition C5, AMENDED); blocks PR-ready. One repin iteration over one item
      dispatches to **exactly one** recipient, and that recipient is `row.user_id`. Construct the
      item so the fan-out would land — more than one workspace Owner via migration 111's
      `is_email_triage_workspace_owner` — and assert the current single-recipient behavior
      explicitly, so a future fan-out reds T12 at the site the constraint governs instead of
      collapsing recipients silently in prod. Include a comment naming the ADR constraint and
      pointing at its clause, so whoever reds this is told to re-key to recipient-grain rather
      than delete the assertion. **T4 does not satisfy this** — it covers distinct items, not
      multiple recipients of one item. Fold verification under the AC-walk (task 6.4); no new AC.
- [x] 3.13 Mutation control (manual verification step, not an AC): delete the `23505` branch,
      confirm T1 reds, restore.
- [x] 3.14 Update `test/server/inngest/cron-email-ingress-probe.test.ts` — route the new table
      in its fake; assert the new result field.

## Phase 4 — Compliance surfaces (CI-forced)

- [x] 4.1 `server/dsar-export-allowlist.ts`: add `statutory_repin_send` to
      **`DSAR_TABLE_EXCLUSIONS`** with a documented reason. NOT the allowlist — `joinVia` is
      not data-driven, so an allowlist entry exports nothing AND hard-fails
      `test/dsar-worker-per-row-where.test.ts`.
- [x] 4.2 Update `docs/legal/privacy-policy.md`.
- [x] 4.3 Update `docs/legal/gdpr-policy.md`.
- [x] 4.4 Update `docs/legal/data-protection-disclosure.md`.
- [x] 4.5 Update `knowledge-base/legal/compliance-posture.md`.
- [x] 4.6 Amend Art. 30 **PA-27** limbs (c)/(f)/(g) in
      `knowledge-base/legal/article-30-register.md`. **No new PA row.**
- [x] 4.7 Add a `BR-*` rule to `knowledge-base/engineering/architecture/domain-model.md`.

## Phase 5 — ADR

- [x] 5.1 Amend the ADR file with frontmatter `adr: 035`
      (`ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`): ingest→send
      extension, the 1:N rebuttal to the rejected alternative, TTL-daemon rejection honored,
      the cadence-shape rule, and the recipient-grain constraint.
- [x] 5.2 Add a one-line see-also pointer to `ADR-035-template-registry-code-static.md`
      (no decision content).

## Phase 6 — Verification

- [x] 6.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` over the affected suites,
      INCLUDING `test/dsar-worker-per-row-where.test.ts` (see plan §Phase 6).
- [x] 6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] 6.3 Full vitest suite green.
- [x] 6.4 Walk all 15 Acceptance Criteria.

## Phase 7 — Deferrals (before PR ready)

- [x] 7.1 Filed **#6798** — statutory email reliance framing (no "not legal advice" disclaimer).
- [x] 7.2 Filed **#6799** — `daysUntilDue === 7` exact-match fragility + T-7 dead for `breach-art33`.
- [x] 7.3 Filed **#6800** — ADR ordinal/frontmatter normalization.
- [x] 7.4 Filed **#6801** — 60-day scan cliff (uncountered permanent silence).
- [x] 7.5 Filed **#6802** — non-410 push failure = permanent total silence (row never pruned,
      email branch never reached, `pinged` reports success).
- [x] 7.6 CPO ruling on conditions C2 and C5 — **RETURNED 2026-07-20**.
      - **C2 UPHELD.** Unconditional dispatch on fail-open stands; AC5 stands. No code change.
        The CPO overruled their own original condition: the T-7 arm is a structural one-shot, so
        fail-open suppression there would produce *no heads-up ever* (the next tick no longer
        satisfies `daysUntilDue === DEADLINE_REPIN_HEADS_UP_DAY`), and the likeliest fail-open
        trigger — the `42P01` deploy race — is correlated, silently dropping the heads-up for
        every T-7 item that day with no self-heal.
      - **C5 AMENDED.** ADR constraint + loop comment retained, **plus T12** (task 3.12e) as a
        tripwire. Documentation does not fail; the invariant currently holds only by accident of
        the send path being single-recipient.
      - Note recorded: the CPO struck "halves the code paths" from C2's rationale — implementation
        path-count is never an acceptable reason to move risk onto a user holding a statutory
        deadline. It pointed the same direction here by coincidence, not by merit.
