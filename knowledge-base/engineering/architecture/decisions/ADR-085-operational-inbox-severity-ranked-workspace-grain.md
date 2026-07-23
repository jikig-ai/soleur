# ADR-085: Operational inbox — severity-ranked, workspace-grain, separate from the email-triage WORM ledger

- **Status:** Accepted
- **Date:** 2026-07-04
- **Issue:** [#6007](https://github.com/jikigai/soleur/issues/6007) (Multica-adaptation epic [#6006](https://github.com/jikigai/soleur/issues/6006), child 1)
- **Relationship to ADR-066:** extends the workspace-grain, Owner-shared inbox posture established by [ADR-066](./ADR-066-email-triage-inbox-workspace-grain.md) for email-triage. This ADR does **not** reverse it; the new store mirrors it exactly (workspace-grain, Owner-shared reads, RLS-only, user-context client in the read route).
- **Relationship to the messages multi-source substrate (ADR-037):** the `messages.source_ref` composite-unique dedup ADR ([`ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`](./ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md)) established the multi-source feed over `messages` + the plain-insert-catch-`23505` idiom this inbox reuses. This ADR records **deliberate co-existence** for v1 (a different substrate — `inbox_item`, not `messages`); `deriveEmailSeverity`/`mergeAndRank` is the shared severity contract that substrate can later adopt, not a silent second engine.

## Context

The founder needs a single **attention queue** — one inbox that ranks everything needing them by severity (`action_required` → `attention` → `info`), pushes on completion, and never buries a running statutory clock. This is the notification spine every later Multica-adaptation child (approvals #4672, autopilot #4674, board #6010) delivers into.

Two questions drove the design:

1. **Where do general operational notifications live?** The existing `email_triage_items` table (mig 102/111) is a GDPR-hardened **WORM statutory-evidence ledger**: email-specific `NOT NULL` columns (`resend_email_id`, `subject`, `received_at`), a strict mutation-matrix trigger (`email_triage_items_no_mutate`), Art. 17 anonymise, statutory retention carve-outs, and `ON DELETE RESTRICT` FKs protecting evidence. Generalizing it in place would force nullable-ing frozen columns and pollute a statutory surface with mutable operational rows.

2. **How is severity derived across sources?** The inbox merges two sources — native operational notifications and email-triage rows. Email-triage rows have no native severity; theirs must be computed. A deadline-driven severity model creates an escalation mechanism (re-notify cron, per-class deadline model on the critical path) that can get a statutory item's ranking wrong.

## Decision

1. **New mutable `inbox_item` table** (mig 122) for general operational notifications — SEPARATE from `email_triage_items`. Read/act/archive state via the `set_inbox_item_state` SECURITY DEFINER RPC; workspace-grain with Owner-shared reads per ADR-066; the email-triage WORM ledger is **not** extended. Native `severity` + `source` discriminator; `source_ref` stores **ids only**.

2. **Severity is computed at READ, never stored.** A shared pure module `lib/inbox-severity.ts` (`deriveEmailSeverity` + `mergeAndRank`) is the single source of truth, consumed by `GET /api/inbox`, the nav badge, and the `inbox_list` agent tool. Email-triage severity is derived at the merge layer from `statutory_class` — no schema change to the ledger.

3. **"Pin all statutory, calm the visuals"** (operator decision 2026-07-04). Every non-archived statutory email row is `action_required`, pinned first, and **exempt from the NEEDS YOU cap** — regardless of clock or acknowledgment status (acknowledgment is workflow state, not legal resolution; it never demotes). Severity **never derives from a deadline**, so the near/far-deadline chip is cosmetic-only and can never move a statutory item out of NEEDS YOU or below the pin. This eliminates the pull-only-escalation risk, the re-notify cron, and the per-class-deadline compliance dependency on the critical path.

4. **Deep links are built from `source_ref` ids AT RENDER**, never stored. A stored URL rots when a route path changes or the target is deleted; a source whose deep-link target doesn't exist yet (approval_required pre-#4672) renders a non-navigating row rather than dead-ending on a 404.

5. **CASCADE FKs + 90d retention** (AP-009 deviation). Operational data follows workspace + user lifecycle (`ON DELETE CASCADE`, NOT the mig-111 statutory `RESTRICT`). A daily pg_cron sweep deletes archived/`info` rows after 90d — more aggressive than the email ledger's 365d, justified as content-minimized operational ephemera — with a hard **never-delete un-acted `action_required`** carve-out.

6. **`source` CHECK ships the v1-emittable set only** (`task_completed`, `system`). #4672 (`approval_required`) and #4674 (`autopilot_run`) each `ALTER` the CHECK in the migration that ships their emitter; the full intended enum is documented here.

## Semantics

- **Founder-scale, no cursor pagination.** The merge does a bounded fetch per source (uncapped non-archived statutory + capped `inbox_item`/email tails), runs `deriveEmailSeverity`/`mergeAndRank` in app memory, and stable-sorts — SQL cannot sort on a wall-clock-derived severity. The GOOD TO KNOW tail is what grows; this is an explicit scale assumption for v1.
- **Content-minimization (GDPR).** `inbox_item` stores a server-generated `title` + `source_ref` ids + severity + source — NEVER agent output / message bodies / email content. A co-Owner-visible row carries nothing the founder wouldn't want a co-Owner to see.
- **RLS is load-bearing.** Targeted rows (`user_id` set) are private to their recipient; broadcasts (`user_id NULL`) are visible to workspace Owners. The read route uses the user-context client (never `createServiceClient` — the ADR-066 404-and-bypass trap), enforced by a source-grep gate.
- **Single global `acted_at`.** v1 stores read/act/archive state inline (no per-Owner recipient-state join — deferred to #4672, where broadcast `approval_required` is the first source that needs independent per-Owner state). One approver resolves for the workspace.
- **Observability.** A missed `action_required` dispatch mirrors to Sentry `op=notify-inbox-action-required` (never silent) — the exact "a decision that needs the founder, with no notice" failure this feature prevents.

## Verification

- Migration shape gate (`test/migration-122-inbox-item.test.ts`): table/RLS/REVOKE, owner-scoped SELECT reusing `is_workspace_owner`, archive-guard, retention carve-out, down.sql.
- Merge/severity unit tests (`test/inbox-severity.test.ts`): statutory always pinned (acknowledged + far-from-deadline), chip ≠ severity, NEEDS YOU cap statutory-exempt, deep-link builder.
- RLS-bypass source grep (`test/inbox-no-service-client.test.ts`): no `createServiceClient` under `app/api/inbox/**`.
- Dispatch tests (`test/notifications.test.ts`): insert-once, dedup-no-push, action_required Sentry mirror, per-Owner broadcast.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Generalize `email_triage_items` in place | WORM GDPR statutory ledger with email-specific NOT-NULLs + a mutation-matrix trigger; touching it risks the compliance surface at the `single-user incident` brand-survival threshold. |
| Ephemeral push-only (no persistent `inbox_item`) | A push you miss is gone; the founder needs a durable queue to return to. |
| Deadline-driven statutory severity (escalate as the clock runs down) | Creates a pull-only-escalation risk + a re-notify cron + a per-class-deadline compliance dependency on the critical path. "Pin all" is strongest-safety and simplest — nothing to escalate, nothing to get wrong. |
| Per-Owner recipient-state join in v1 | No v1 source needs independent per-Owner state (`task_completed` is targeted; `system` broadcasts resolve globally). Deferred to #4672 when broadcast `approval_required` first needs it — avoids a dual `acted_at` source-of-truth. |
