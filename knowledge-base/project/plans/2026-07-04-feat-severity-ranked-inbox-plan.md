---
date: 2026-07-04
type: feat
lane: cross-domain
issue: 6007
epic: 6006
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-04-multica-primitives-adaptation-brainstorm.md
status: plan-draft
---

# Plan — Severity-ranked inbox (Multica-adaptation Epic #6006, child 1)

## Overview

Give the non-technical founder a single **attention queue**: one inbox that ranks everything needing them by severity (`action_required` → `attention` → `info`), pushes on completion, and never buries a running statutory clock. This is child 1 of the Multica-adaptation program and the **notification spine** every later child delivers into.

**Core architectural decision (evidence-backed — see Research Reconciliation):** introduce a **new `inbox_item` table** for general operational notifications; do **not** generalize `email_triage_items` (a GDPR-hardened WORM statutory-evidence ledger with email-specific `NOT NULL` columns). The inbox **surface** becomes multi-source: it merges (a) email-triage items — severity derived from their existing `statutory_class`, zero schema change — and (b) the new `inbox_item` rows (native severity). Severity is the cross-source sort key, with the existing *unacknowledged-statutory-pinned-first* invariant preserved as the top of that order.

Clean-room throughout (CLO G1–G5): we adapt the *severity-inbox design pattern* (email/PagerDuty/GitHub-notifications prior art), not Multica source; Soleur-native names/schema; no "Multica" trademark.

## Research Reconciliation — Spec vs. Codebase

| Brainstorm/issue claim | Codebase reality (verified 2026-07-04) | Plan response |
|---|---|---|
| "Inbox already aggregates conversations + email-triage" | `inbox-surface.tsx` renders **only** `EmailTriageRow` from `GET /api/inbox/emails`; `conversation-row.tsx` is used on the **dashboard Today page** (`dashboard/page.tsx:786`), not the inbox. The inbox is **single-source** today. | Multi-source merge is **net-new** work on the inbox surface (not "extend an existing merge"). |
| "Generalize `email_triage_items` in place vs new table" (open Q) | `email_triage_items` (mig 102/111) is a **WORM GDPR ledger**: email-specific `NOT NULL` columns (`resend_email_id`, `subject`, `received_at`), a strict mutation-matrix trigger (`email_triage_items_no_mutate`), Art. 17 anonymise, statutory retention carve-outs, workspace-Owner RLS (`is_email_triage_workspace_owner`). | **Resolved: new `inbox_item` table.** Generalizing would force nullable-ing frozen columns + pollute a statutory ledger. Email-triage severity is **computed at the merge layer** from `statutory_class` — no touch to the WORM ledger. |
| "Wire the existing push dispatch path to inbox events" | `server/notifications.ts` is a **fire-and-forget push/email dispatcher** (`notifyOfflineUser`, 3 payload variants) that **persists nothing**; it is **user-scoped** (`push_subscriptions.user_id`). | Add an `inbox_item` payload variant + a `notifyInboxItem()` that **inserts the row then dispatches** via the existing `notifyOfflineUser` path. Reuse shipped VAPID/web-push + Resend fallback + `mirrorNotifyFailure`. |
| "`components/sw-register.tsx`, `components/notification-prompt.tsx`" (CTO summary) | Not at those paths (web-push registration lives elsewhere). Immaterial to this plan — dispatch is server-side in `notifications.ts`. | No dependency on those exact paths. |
| Inbox reads are workspace-grain | Confirmed (ADR-066 / mig 111): reads gated by Owner membership, RLS-only, `createServiceClient` **forbidden** in the read route. | `inbox_item` mirrors this exactly (workspace-grain, Owner-shared reads, RLS-only, user-context client). |

## User-Brand Impact

- **If this lands broken, the user experiences:** the inbox drops or mis-ranks an `action_required` item (e.g., a running statutory clock or a paused run), so the founder learns of a brand-damaging event too late — or a completion push never arrives and they babysit a run that already finished.
- **If this leaks, the user's data is exposed via:** the `inbox_item` read path bypassing workspace-Owner RLS (the exact ADR-066 `createServiceClient`-in-read-route trap), or persisting agent output content into an inbox row that a co-Owner should not see.
- **Brand-survival threshold:** `single-user incident`. → **CPO sign-off required at plan time** (carry-forward from brainstorm Phase 0.1; CPO reviewed the brainstorm). `user-impact-reviewer` runs at PR review.

## Architecture Decision (ADR/C4)

This introduces a new data-model + a cross-cutting operational-notification substrate → an ADR is a **deliverable of this plan**, not a follow-up.

### ADR
- **New ADR (provisional ordinal — verify next-free at ship):** *"General operational inbox — severity-ranked, workspace-grain, separate from the email-triage WORM ledger."* Decision: operational notifications live in a **new mutable `inbox_item` table** (read/unread/archived state, native `severity`, `source` discriminator), workspace-grain with Owner-shared reads per ADR-066; the email-triage WORM ledger is **not** extended; the unified inbox read path merges both sources with a fixed severity order that pins unacknowledged-statutory first. `## Alternatives Considered` records the rejected "generalize `email_triage_items`" option with the WORM/GDPR rationale.
- Amends/extends: cites ADR-066 (workspace-grain inbox) as lineage; does not reverse it.

### C4 views
- **Container view:** add an **"Operational Inbox"** data store (Supabase `inbox_item`) and the edge from the notification dispatcher (`notifications.ts`) → Inbox store → Founder (Owner). Confirm the existing "Email triage inbox" store + Resend/web-push external systems are already modeled; add the new store + the dispatcher→store edge + the Founder→store read edge, and the `view … include` line so it renders. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing the three `.c4` files.

## GDPR / Compliance (Gate 2.7 — regulated-data surface: new table + migration + RLS)

Directly reuses the ADR-066 / mig 111 precedent (the same compliance problem, already solved for email-triage):
- **Workspace-grain, Owner-shared reads, RLS-only.** Read route uses the **user-context** Supabase client, never `createServiceClient` (the ADR-066 404-and-bypass trap).
- **Minimize content.** `inbox_item` stores a **title + deep-link + severity + source refs**, NOT agent output / message bodies / email content. A co-Owner-visible row must carry nothing the founder wouldn't want a co-Owner to see.
- **Art. 17 cascade.** `inbox_item` rows keyed to a `user_id` (personally-targeted items) join the account-delete anonymise/delete cascade; workspace-scoped rows follow workspace lifecycle. Non-WORM (operational) → plain delete on erasure, unlike the statutory ledger.
- **Retention.** Archived/`info` rows get a pg_cron retention sweep (mirror mig 094 pattern; e.g. 90d) — operational noise must not accumulate forever.
- **Run `/soleur:gdpr-gate` at deepen-plan** against the migration + read-route FRs to confirm no Art. 9 / lawful-basis / Art. 30 trigger beyond the above.

## Non-Goals (deferred — tracking below)

- **Full per-entity subscription** (Multica's per-issue subscriber model). Soleur's Owner-scoped workspace reads make "subscription" mostly implicit. MVP: workspace-Owner-visible by default + optional `user_id` for personally-targeted items. Rich subscription rides the **board (child 5, #6010)**.
- **Autopilot-run items as a source** — the `inbox_item` `source` enum includes `autopilot_run`, but *emitting* them is **child 2 (#4674)**. This plan ships the table + severity + email-triage + task-completion sources; autopilot wires in later with zero inbox change.
- **HITL approval items** — `source: 'approval_required'` + `severity: 'action_required'` is defined here (so the inbox is the one queue), but the approval **queue mechanics** are **#4672**. One queue, not two.
- **New visual design system for rows** beyond a severity indicator — the richer board/timeline visual work is child 5.
- **Severity classification calibration / feedback loop** (CPO's riskiest-gap flag) — measuring whether `action_required` over/under-fires needs shipped-usage data; **deferred to a follow-up issue** (file at Phase 3.6). v1 ships a *deterministic, reviewable* `deriveSeverity()` (Appendix B) so the rule is auditable even before it is tuned.
- **Snooze / defer / filters / per-source config / mark-unread / cross-source dedup** (spec-flow P2-3/P2-4) — CPO: ship the spine, not an inbox app. Tracked in Appendix B; revisit only on demonstrated need.

## Implementation Phases

### Phase 1 — Data model: `inbox_item` table (migration)
- New migration `apps/web-platform/supabase/migrations/<next>_inbox_item.sql` (+ `.down.sql`). `ls` the migrations dir first for the next ordinal and to copy the RLS/`is_*_workspace_owner` + pg_cron patterns from mig 111 / 094.
- `inbox_item` columns: `id uuid pk`, `workspace_id uuid NOT NULL REFERENCES workspaces ON DELETE RESTRICT`, `user_id uuid NULL REFERENCES users ON DELETE CASCADE` (personally-targeted; NULL = workspace-broadcast), `severity text CHECK (severity IN ('action_required','attention','info'))`, `source text CHECK (source IN ('task_completed','autopilot_run','approval_required','system'))`, `title text NOT NULL` (server-generated/sanitized; **no** third-party/agent-output content), `source_ref jsonb NULL` (**ids only** — `{conversationId}`/`{routineRunId}`; the deep link is **built at render time** from these, never stored — spec-flow P1-2: a stored URL rots + strands the founder when a route path changes or the target is deleted), `dedup_key text NULL UNIQUE` (idempotent emit), `created_at`, `acted_at timestamptz NULL` (the single "resolved" signal — CPO: v1 = read + pin + **single ack**, no snooze/filters/state machine).
- **Per-recipient read/ack state (spec-flow P0-3):** broadcast rows (`user_id NULL`) need **per-Owner** read/archive state — a single `status` column would let Owner A's archive silently drop the nudge for Owner B. Model read/ack/archive in a `inbox_item_recipient_state (inbox_item_id, user_id, read_at, acted_at, archived_at)` join (PK `(inbox_item_id, user_id)`). Targeted rows (`user_id` set) are single-recipient — their state may live inline, but use the join uniformly to avoid two code paths.
- **Not WORM** (operational; needs read/archive mutation) — RLS: Owner-membership SELECT via a reused/added `is_workspace_owner` helper (mirror `is_email_triage_workspace_owner`); UPDATE via an owner-pinned RPC `set_inbox_item_state(id, action)` mirroring `set_email_triage_status`. **Archive guard (spec-flow P0-2):** the RPC **rejects archiving an `action_required` item that is not yet `acted`** (mirror the email precedent where statutory rows have no archive button) — a single misclick must not permanently lose an approval. INSERT via service-role dispatcher only (REVOKE from authenticated).
- **Retention (spec-flow P0-2 + GDPR):** pg_cron sweep deletes archived/`info` rows after ~90d **but never un-acted `action_required`** (carve-out mirrors the email statutory carve-out).
- Files: new migration + `.down.sql`.

### Phase 2 — Emit + push: `notifyInboxItem()` in `notifications.ts`
- Add `InboxItemNotificationPayload` to the `NotificationPayload` union (`type: 'inbox_item'`); sweep consumers per `cq-union-widening-grep-three-patterns` + `tsc --noEmit`.
- Add `notifyInboxItem(opts)`: insert the `inbox_item` row (service client, dedup on `dedup_key`), then call the existing `notifyOfflineUser` dispatch for a targeted `user_id` (or each workspace Owner for broadcast). Reuse VAPID/web-push + Resend fallback + `mirrorNotifyFailure` (extend it: a missed `action_required` push mirrors to Sentry `op=notify-inbox-action-required`).
- **Push `tag` (spec-flow P1-6):** the `inbox_item` push variant needs its **own `tag`** in `public/sw.js` (e.g. `inbox-item-{id}`) — `sw.js` collapses by per-variant tag, so a shared tag would make inbox pushes replace each other. Also confirm the post-login redirect preserves the deep-link target (returning via an expired-session push must land on the item, not `/dashboard`).
- **Emit-gating (spec-flow P1-1):** `source` enum defines `approval_required`/`autopilot_run` so the inbox is *one* queue, but **no producer may emit them until their child ships** (#4672 / #4674). This plan wires only **`task_completed`** (agent run finishes) — the demo-able "your Legal finished" ping — and `system`. Emit from the agent-run terminal path (grep `agent-runner`/session-complete; trace from entry per `trace-callgraph-from-entrypoint`).
- Files: `server/notifications.ts`; `public/sw.js`; the agent-run completion call-site.

### Phase 3 — Unified read path: `GET /api/inbox`
- New route (or generalize `/api/inbox/emails` → keep back-compat) that returns a merged, severity-ordered list from **two sources**: `inbox_item` (native severity) + `email_triage_items`.
- **Email severity map — clock-threshold based (operator decision 2026-07-04, reconciling wireframe + spec-flow P0-1):** statutory severity is governed by **time-to-deadline, not `status`**, with three hard safety invariants that preserve the P0-1 protection:
  1. A non-archived statutory item is **never `info`, never capped-out-of-view, never swept** while unresolved — even when it sits in GOOD TO KNOW it renders (uncapped).
  2. It **auto-escalates monotonically to `action_required` (NEEDS YOU, pinned)** once `hours_to_deadline ≤ STATUTORY_URGENT_MARGIN` — a conservative margin chosen so the founder always reaches NEEDS YOU with ample time to act. Above the margin it is `attention` (amber, GOOD TO KNOW).
  3. `acknowledged` **never demotes** severity — only the clock does (acknowledgment is workflow state, not legal resolution). So an acknowledged statutory item inside the margin is still pinned.
  - **Deadline derivation is a compliance rule (CLO + deepen-plan):** `email_triage_items` stores `statutory_class` + `received_at` but no explicit deadline. Deadline = `received_at + window(statutory_class)` (e.g. breach→GDPR Art. 33 72h; dsar→Art. 12 ~1 month; service-of-process/regulator per counsel). deepen-plan MUST have CLO fix the per-class window + the `STATUTORY_URGENT_MARGIN`; until then the safe fallback is "all non-archived statutory → `action_required`/pinned". Non-statutory email → `info`.
- **Preserve the load-bearing invariant:** any statutory item currently at `action_required` pins first (uncapped), then severity rank, then `received_at DESC`. The clock-threshold rule only moves a statutory item *up* to the pin as its deadline nears — it can never let a near-deadline clock fall below the fold.
- **`action_required` derivation rule is a reviewable spec artifact (CPO change):** the exact predicate per source (which statutory states, which inbox_item sources) lives in a named, tested `deriveSeverity()` helper + a table in this plan (see Appendix B) — not code-buried. This is the product's precision contract.
- **Cap NEEDS YOU with explicit overflow (CPO change):** cap the visible NEEDS YOU count (e.g. 20) with a "+N more need you" overflow row — protect against banner-blindness — but the **statutory pin is never subject to the cap**.
- Keep the existing `email_triage_list` agent-tool filter in lockstep (agent-native parity).
- Files: new/edited route under `app/api/inbox/`; shared `deriveSeverity()` + merge helper in `lib/`.

### Phase 4 — Surface: multi-source, severity-grouped inbox
- Extend `inbox-surface.tsx` to consume `GET /api/inbox`, render two groups — **NEEDS YOU** (`action_required`) over **GOOD TO KNOW** (`attention`/`info`) per the copywriter (improves on "FYI") — with a severity indicator (red/amber/grey dot, business framing, **not** Linear status columns), and dispatch to the right row renderer by `source` (existing `EmailTriageRow` for email; new `InboxItemRow` for the rest). Preserve Active/Archived tabs + SWR per-filter cache keys + the "render in API order, never re-sort" contract.
- **Graceful non-navigating rows (spec-flow P1-1/P1-2):** `InboxItemRow` builds its link from `source_ref` at render; when a source's deep-link target doesn't exist yet (`approval_required` pre-#4672) or was deleted, render a non-navigating row rather than dead-ending on a 404.
- **Per-group empty/positive states (spec-flow P1-3, copy from Appendix A):** empty-NEEDS-YOU-with-FYI renders as reassurance ("Nothing needs your call right now."), fully-empty ("You're all caught up."), all-archived points to the Archived tab. Never a vanished header that reads as broken.
- **Archive confirmation (spec-flow P0-2):** archiving an `action_required` item prompts confirmation; the row's archive affordance is disabled/guarded until acted.
- **Nav badge (spec-flow P1-4 / P2-2 + copywriter):** count **outstanding `action_required` only** (regardless of read), `9+` cap; a read-but-un-acted approval still nudges; FYI-only unread shows a small gold dot, no number; never render "0".
- Files: `components/inbox/inbox-surface.tsx`, new `components/inbox/inbox-item-row.tsx`, the nav badge (`components/dashboard/nav-count-badge.tsx` / `inbox-nav-badge.tsx` — align to the shipped badge aria/cap pattern). *(New component file → BLOCKING Product/UX tier, wireframe below.)*

### Phase 5 — Tests + observability
- Migration RLS tests (Owner sees / non-Owner 0 rows / service-role INSERT only), the `set_inbox_item_status` one-way + owner-pin tests, severity-order + statutory-pin merge tests, `notifyInboxItem` insert+push+dedup + Sentry-mirror-on-failure tests. Verify the runner: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (not `bun test`, not `npm -w`); test paths must match `vitest.config.ts` `include:` globs (`test/**`).

## Observability

```yaml
liveness_signal:
  what: inbox_item insert rate + push dispatch success (reuse notifications.ts logs)
  cadence: per-event
  alert_target: Sentry op=notify-inbox-action-required (missed action_required push)
  configured_in: apps/web-platform/infra/sentry/*.tf (add rule) + server/notifications.ts mirrorNotifyFailure
error_reporting:
  destination: Sentry via reportSilentFallback / mirrorNotifyFailure
  fail_loud: true (a missed action_required push mirrors to Sentry — never silent)
failure_modes:
  - mode: inbox_item insert fails
    detection: reportSilentFallback op=inbox-item-insert
    alert_route: Sentry
  - mode: push dispatch fails for action_required
    detection: mirrorNotifyFailure op=notify-inbox-action-required
    alert_route: Sentry issue alert
  - mode: read route falls back to service client (RLS bypass)
    detection: static gate — no createServiceClient in app/api/inbox/**
    alert_route: review-time (security-sentinel) + a source-grep test
logs:
  where: pino child logger "notifications" / route handler
  retention: existing platform retention
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/**/inbox*.test.ts"
  expected_output: "all inbox merge/RLS/dispatch tests pass; no ssh"
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `inbox_item` (+ `inbox_item_recipient_state`) migration applies on a clean DB; `.down.sql` reverses cleanly; service-role-only INSERT.
- [ ] **RLS-leak negative test as a merge gate (CPO required change):** Owner A cannot read Owner B's items via `GET /api/inbox` (workspace isolation); a non-Owner gets 0 rows. Read route uses the user-context client (grep gate: **no `createServiceClient` under `app/api/inbox/**`**).
- [ ] **Archive guard (spec-flow P0-2):** `set_inbox_item_state` rejects archiving an un-acted `action_required` item; retention sweep never deletes un-acted `action_required` (test both).
- [ ] **Per-Owner state (spec-flow P0-3):** a broadcast row acked/archived by Owner A still shows to Owner B until B acts (per-recipient state test).
- [ ] **Statutory clock-escalation (spec-flow P0-1 + operator clock-threshold decision):** a statutory item within `STATUTORY_URGENT_MARGIN` of its deadline is `action_required`/pinned (incl. when `acknowledged`); one with ample clock is `attention` but still rendered uncapped and never swept; escalation is monotonic as the deadline nears (tests at both sides of the margin + an acknowledged-near-deadline case).
- [ ] `email_triage_items` is **unmodified** (`git diff` shows zero changes to mig 102/111, no new trigger on it).
- [ ] `GET /api/inbox` merges both sources via the tested `deriveSeverity()` helper; statutory pinned first + uncapped; NEEDS YOU capped with overflow (statutory exempt from the cap).
- [ ] `notifyInboxItem` inserts once (idempotent on `dedup_key`) then dispatches; the `inbox_item` push variant has its own `sw.js` `tag`; a failed `action_required` dispatch mirrors to Sentry `op=notify-inbox-action-required`.
- [ ] Deep links are **built from `source_ref` at render** (no stored URL); unknown/deleted targets render non-navigating, not a 404.
- [ ] Surface renders NEEDS YOU / GOOD TO KNOW groups with per-group empty states (Appendix A copy); nav badge counts outstanding `action_required` only (`9+` cap), FYI-only = gold dot.
- [ ] New ADR committed + three `.c4` files edited & rendering (c4 tests green). **CPO sign-off recorded: GO-WITH-CHANGES — all listed changes folded (see Domain Review).**
- [ ] `tsc --noEmit` clean; targeted vitest suites green.

### Post-merge (operator / ship)
- [ ] Migration applied to prod via `web-platform-release.yml#migrate` (automatable — ship handles).

## Domain Review

**Domains relevant:** Product, Engineering, Marketing, Legal, Operations (carry-forward from brainstorm `## Domain Assessments`; Sales/Finance/Support n/a).

### Engineering (CTO) — carry-forward
**Status:** reviewed. Severity inbox S–M: web-push shipped, statutory pinning exists; the net-new is the `inbox_item` table + merge. Risk: RLS-bypass in the read route (ADR-066 trap) — mitigated by user-context-client-only + a source-grep gate.

### Marketing (CMO) — carry-forward
**Status:** reviewed. Inbox is the weakest standalone demo (autopilot is the "wow") — ship it as the spine, not the headline. Severity framing must read as "Decisions needing you", business language, not a dev notification center.

### Legal (CLO) — carry-forward
**Status:** reviewed. GO-with-guardrails: reuse ADR-066 compliance posture; new table is operational (non-WORM) but still workspace-Owner-scoped + content-minimized + Art.17-cascaded. G1–G5 clean-room (no Multica source). Run gdpr-gate at deepen-plan.

### Operations (COO) — carry-forward
**Status:** reviewed. The inbox is where autopilot results land; keep `info` items low-noise (retention sweep) so the queue stays an attention tool, not a log.

### Product/UX Gate
**Tier:** BLOCKING (operator-confirmed 2026-07-04: new grouped `InboxItemRow` component + a new severity visual language → wireframe required).
**Design direction (operator-selected):** a **"NEEDS YOU"** group (`action_required`, pinned top) over a **"GOOD TO KNOW"** group (`attention`/`info` — copywriter improved on "FYI"), each row a severity dot + plain-language title + relative time; statutory clock shown as remaining hours.
**Decision:** reviewed. **Agents invoked:** spec-flow-analyzer, cpo (sign-off), copywriter (copy), ux-design-lead (`.pen`).
**Skipped specialists:** none.
**Pencil available:** yes (`✔ Connected`).

**CPO sign-off:** **GO-WITH-CHANGES** — all folded: (1) cap NEEDS YOU + overflow (statutory exempt); (2) RLS-leak negative test as a merge gate; (3) `action_required` derivation as a reviewable spec artifact (`deriveSeverity()` + Appendix B); (4) v1 = read + pin + single ack (no snooze/filters/state machine); (5) keep 3 severities internal, only 2 groups in UI. **CPO riskiest gap (deferred):** classification precision has no calibration/feedback loop — filed as a follow-up (see Non-Goals) since tuning needs shipped-usage data.

**spec-flow findings folded:** P0-1 (acknowledged-statutory band → Phase 3 + AC), P0-2 (archive guard + retention carve-out → Phase 1/4 + AC), P0-3 (per-Owner recipient state → Phase 1 + AC), P1-1 (emit-gating → Phase 2), P1-2 (deep-link from source_ref → Phase 1/4), P1-3 (per-group empty states → Phase 4 + Appendix A), P1-4/P2-2 (badge = outstanding action_required only → Phase 4), P1-6 (push tag + redirect → Phase 2). P1-5 (multi-Owner "already resolved" banner) + P2-3/P2-4 tracked in Appendix B state matrix.

**copywriter copy folded:** Appendix A.

**Wireframe:** `knowledge-base/product/design/inbox/severity-ranked-inbox.pen` (8 screens 13–20). **Operator-reviewed & approved 2026-07-04** (Phase 3.55b), with one change: **statutory severity is clock-threshold-based, not status-based** (folded into Phase 3 `deriveSeverity()` + Appendix B, preserving the never-hidden/auto-escalate safety invariants). Screen 19 (archive-confirm on a running statutory clock) is the load-bearing brand-safety affordance.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Generalize `email_triage_items` in place | **Rejected** | WORM GDPR statutory ledger; email-specific NOT-NULLs; touching it risks the compliance surface at single-user threshold. |
| New `inbox_item` table + merge-layer severity for email-triage | **Chosen** | Zero blast radius on the compliance ledger; extends the already-workspace-grain inbox pattern; severity is a clean cross-source sort key. |
| Ephemeral push-only (no persistent inbox_item) | Rejected | A push you miss is gone; the founder needs a durable queue to come back to. |

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails deepen-plan Phase 4.6 — it is filled above.
- **Do not `createServiceClient` in the inbox read route** — it silently bypasses workspace-Owner RLS (the exact ADR-066 incident). User-context client only; add a source-grep gate.
- **Severity cap must never hide a running statutory clock** — port the existing uncapped-statutory-pin merge verbatim; severity ordering sits *below* the pin.
- `inbox_item.title`/`deep_link` are server-generated — never persist agent output or email subject into a co-Owner-visible row.
- Test runner is **vitest** (`./node_modules/.bin/vitest run`), not `bun test`/`npm -w`; test paths must match `vitest.config.ts` `include:` globs.

## Appendix A — Copy (copywriter, brand-guide-aligned)

**Group headers** (existing ALL-CAPS gold kicker style): `NEEDS YOU` (helper: "A few things are waiting on your call.") · `GOOD TO KNOW` (helper: "Updates from your organization. Nothing to do here.").

**Empty states:** (a) empty NEEDS YOU + FYI present → "Nothing needs your call right now." / "The updates below are just to keep you in the loop." (b) fully empty → "You're all caught up." / "Your organization is handling things. Anything that needs you will show up here." (c) empty archived → "Nothing here yet." / "Items you've handled or set aside are kept here."

**Item title templates** (server-generated, sanitized; no "task/queue/dispatch"): `task_completed` → `{Agent} finished: {work}` (GOOD TO KNOW) · `autopilot_run` → `Autopilot: {summary}` (GOOD TO KNOW) · `approval_required` → `{Agent} needs your go-ahead: {what}` (NEEDS YOU) · `system` → `From Soleur: {message}` (GOOD TO KNOW; NEEDS YOU only if it truly blocks, e.g. billing failure) · email statutory → `Legal mail from {sender} — timely response needed` (NEEDS YOU; deadline as calm metadata "Respond by 7 Jul", never "statutory"/"URGENT") · email non-statutory → `{sender}: {subject}` (GOOD TO KNOW; mail-class pill carries category).

**Nav badge:** count **action_required only**; aria `"{n} item(s) need your decision"`; `9+` cap; FYI-only unread → small gold dot ("New updates in your inbox"); zero of everything → no badge.

**Wireframe (.pen):** `knowledge-base/product/design/inbox/severity-ranked-inbox.pen` — screens 13–20, operator-approved 2026-07-04. **Reconcile note:** the agent flagged `dashboard-inbox.pen` as a possibly-overlapping prior surface — deepen-plan should confirm consolidation vs. co-existence.

## Appendix B — Per-source severity, deep-link targets & state matrix

**`deriveSeverity()` contract (the product's precision rule — tested, not code-buried):**

| Source | Severity → group | Deep-link target | Target exists? | Emit-gated by |
|---|---|---|---|---|
| email statutory, `hours_to_deadline ≤ margin` | `action_required` → NEEDS YOU (pinned, uncapped) | `/dashboard/inbox/email/{id}` | ✓ | shipped |
| email statutory, ample clock (> margin) | `attention` → GOOD TO KNOW (amber; **never capped/swept**; auto-escalates as deadline nears) | `/dashboard/inbox/email/{id}` | ✓ | shipped |
| email non-statutory | `info` → GOOD TO KNOW | `/dashboard/inbox/email/{id}` | ✓ | shipped |
| `task_completed` | `info` → GOOD TO KNOW | `/dashboard/chat/{conversationId}` | ✓ | **this PR** |
| `system` | `info` (→ `action_required` only if blocking, e.g. billing) | dashboard / contextual | ✓ | **this PR** |
| `approval_required` | `action_required` → NEEDS YOU | approvals route | ✗ (built in #4672) | **#4672 — no emit until then** |
| `autopilot_run` | `info` (or `action_required` on failure) | run result | ✗ (no per-run page; degrade to routines list) | **#4674 — no emit until then** |

**State matrix (group × availability × tab):** NEEDS YOU {populated / empty-with-FYI / empty} × GOOD TO KNOW {populated / empty} × {Active / Archived}. Every empty combination has Appendix A copy; Archived is grouped the same way; archiving `action_required` requires confirmation and is blocked until acted.

**Deferred (tracked, not built):** P1-5 stale-Owner "already resolved" banner on a resolved action item; P2-3 cross-source dedup; P2-4 mark-unread; severity calibration/feedback loop (CPO).

## Next
`/soleur:deepen-plan` (ultrathink → mandatory) → tasks.md → `/soleur:work`. Wireframe review pause (Phase 3.55b) happens first.
