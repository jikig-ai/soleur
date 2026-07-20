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

- [ ] 0.1 Re-verify the six `server/notifications.ts` anchors by content (not line number).
- [ ] 0.2 Confirm migration ordinal `135_` is still free against `origin/main`. If taken,
      renumber and sweep this file **and** the plan together.
- [ ] 0.3 Read `supabase/migrations/122_inbox_item.sql` for the house preamble — no top-level
      `BEGIN`/`COMMIT`, no `CREATE INDEX CONCURRENTLY`.
- [ ] 0.4 Confirm `test/server/outbound-chokepoint.test.ts`'s `RESEND_SEND_ALLOWLIST` is
      caller-scoped (this change adds no new `resend.emails.send` call site).

## Phase 1 — Migration (schema contract first)

- [ ] 1.1 Create `supabase/migrations/135_statutory_repin_send.sql`:
      table `public.statutory_repin_send` with `item_id uuid NOT NULL REFERENCES
      public.email_triage_items(id) ON DELETE CASCADE`, `tick_key text NOT NULL`,
      `created_at timestamptz NOT NULL DEFAULT now()`, `PRIMARY KEY (item_id, tick_key)`.
      **No `user_id` column.**
- [ ] 1.2 `ENABLE ROW LEVEL SECURITY` with **zero** policies (service-role only).
- [ ] 1.3 Add standalone `public.purge_statutory_repin_send()` — 90-day sweep, with
      `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `REVOKE ALL … FROM PUBLIC,
      anon, authenticated`, `GRANT EXECUTE … TO service_role`.
- [ ] 1.4 **Do NOT `CREATE OR REPLACE` `purge_email_triage_items` or
      `anonymise_email_triage_items`.** (Security attributes do not survive a replace; both
      AP-018 guard tiers are blind to the drop.)
- [ ] 1.5 Header comment: explicit retention (not cascade), branch-derived `tick_key`, absent
      `user_id`, and the recipient-grain constraint.
- [ ] 1.6 Create `135_statutory_repin_send.down.sql` — plain `DROP TABLE` + `DROP FUNCTION`.

## Phase 2 — Guard in the repin loop

File: `server/inngest/functions/cron-email-ingress-probe.ts`, step `deadline-repin`.

- [ ] 2.1 Compute the run's UTC date **once, before the `for` loop**; return it from the step
      so it is checkpointed (mirror `send-probe`'s `sentAt`).
- [ ] 2.2 Derive `tickKey`: `daysUntilDue === DEADLINE_REPIN_HEADS_UP_DAY` → `'headsup'`;
      otherwise `'daily:' + runDateUtc`.
- [ ] 2.3 Insert `{ item_id, tick_key }` via `.insert({…}).select("id").single()` (house idiom;
      also makes the existing cron test's fake fail loudly).
- [ ] 2.4 Wrap the insert in `try/catch` so no outcome escapes the iteration.
- [ ] 2.5 `code === "23505"` → `suppressed += 1`; `continue`.
- [ ] 2.6 Any other error **or throw** → `warnSilentFallback` (op
      `deadline-repin-marker-insert-failed`) and **fall through to dispatch** (fail open).
- [ ] 2.7 Clean insert → `notifyOfflineUser(...)`; `pinged += 1`.
- [ ] 2.8 Return `{ pinged, suppressed, scanned, runDateUtc }`; surface `repinSuppressed` on
      `HandlerResult`.
- [ ] 2.9 Add the recipient-grain constraint comment on the loop (item-grain suffices only
      while the send path is single-recipient).
- [ ] 2.10 Call `purge_statutory_repin_send()` from the existing `retention-purge` step.

## Phase 3 — Tests (RED first)

New file: `test/server/inngest/cron-email-ingress-probe-repin-idempotency.test.ts`.

- [ ] 3.1 Harness: **do not** mock `@/server/notifications`. Mock the `resend` package with a
      `function`-keyword constructor assigning `this.emails = { send: mockResendSend }`.
- [ ] 3.2 Mock `web-push`, `@/server/logger`, `@sentry/nextjs`, `@/server/inngest/client`.
- [ ] 3.3 Fake `@/lib/supabase/service` routing `email_triage_items`, `probe_tokens`,
      `statutory_repin_send`, `push_subscriptions`, `auth.admin.getUserById`; it **must
      enforce uniqueness** on `(item_id, tick_key)` and return `23505` on a repeat.
- [ ] 3.4 Disambiguate sends by **email subject** (`"Statutory item in your Soleur inbox —
      action required"` vs `SOLEUR-PROBE-`), not by the cron's `title`.
- [ ] 3.5 T1 — double-fire same day → 1 email; `repinSuppressed === 1`; assert
      marker-before-dispatch ordering.
- [ ] 3.6 T2 — T-7 straddle (boundary 05:55; runs D 06:00 and D+1 05:50) → 1 email.
- [ ] 3.7 T3 — two consecutive danger-band days → 2 emails.
- [ ] 3.8 T4 — two distinct items same day, parameterized same-user / different-user → 2 each.
- [ ] 3.9 T5 — fail-open on a non-23505 `{error}` return → email still sent + Sentry op.
- [ ] 3.10 T6 — fail-open on a **thrown** insert (item 3 of 10) → items 4–10 still dispatch.
- [ ] 3.11 T7 — DDL pin: PK is exactly `(item_id, tick_key)`, FK present, no pre-existing
      function replaced.
- [ ] 3.12 T8 — DSAR discovery pin: new table appears in `discoverUserFkTables` output.
- [ ] 3.13 Mutation control (manual verification step, not an AC): delete the `23505` branch,
      confirm T1 reds, restore.
- [ ] 3.14 Update `test/server/inngest/cron-email-ingress-probe.test.ts` — route the new table
      in its fake; assert the new result field.

## Phase 4 — Compliance surfaces (CI-forced)

- [ ] 4.1 `server/dsar-export-allowlist.ts`: add `statutory_repin_send` with
      `ownerField: "user_id"`, `article: "15"`, and
      `joinVia: { parentTable: "email_triage_items", parentJoinColumn: "item_id" }`.
- [ ] 4.2 Update `docs/legal/privacy-policy.md`.
- [ ] 4.3 Update `docs/legal/gdpr-policy.md`.
- [ ] 4.4 Update `docs/legal/data-protection-disclosure.md`.
- [ ] 4.5 Update `knowledge-base/legal/compliance-posture.md`.
- [ ] 4.6 Amend Art. 30 **PA-27** limbs (c)/(f)/(g) in
      `knowledge-base/legal/article-30-register.md`. **No new PA row.**
- [ ] 4.7 Add a `BR-*` rule to `knowledge-base/engineering/architecture/domain-model.md`.

## Phase 5 — ADR

- [ ] 5.1 Amend the ADR file with frontmatter `adr: 035`
      (`ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`): ingest→send
      extension, the 1:N rebuttal to the rejected alternative, TTL-daemon rejection honored,
      the cadence-shape rule, and the recipient-grain constraint.
- [ ] 5.2 Add a one-line see-also pointer to `ADR-035-template-registry-code-static.md`
      (no decision content).

## Phase 6 — Verification

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` over the six affected suites
      (see plan §Phase 6).
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 6.3 Full vitest suite green.
- [ ] 6.4 Walk all 15 Acceptance Criteria.

## Phase 7 — Deferrals (before PR ready)

- [ ] 7.1 File: statutory email reliance framing (no "not legal advice" disclaimer).
- [ ] 7.2 File: `daysUntilDue === 7` exact-match fragility + T-7 dead for `breach-art33`.
- [ ] 7.3 File: ADR ordinal/frontmatter normalization.
- [ ] 7.4 File: 60-day scan cliff (uncountered permanent silence).
