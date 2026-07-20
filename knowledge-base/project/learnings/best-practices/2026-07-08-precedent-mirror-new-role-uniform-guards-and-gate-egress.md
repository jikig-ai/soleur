---
title: "A faithful precedent-mirror for a NEW role must apply the precedent's guards UNIFORMLY across all analogous paths — and account for the surfaces the new role introduces"
date: 2026-07-08
category: best-practices
tags: [migration, security, precedent-mirror, retention, gdpr, review, gate-messages]
issue: 6165
pr: 6160
component: apps/web-platform/supabase/migrations, server/crm, server/tool-tiers
related:
  - knowledge-base/project/learnings/best-practices/2026-06-30-precedent-mirror-for-new-role-breaks-fencing-token-monotonicity.md
---

# Precedent-mirror for a new role: uniform guards + account for new surfaces

## Problem

`feat-beta-conversation-capture` (#6165) added an owner-private beta-tester/prospect
CRM: migration `126_beta_crm.sql` faithfully mirrored `102_email_triage_items.sql`
(RLS/RPC/pg_cron shapes) and `set_email_triage_status` (the `auth.uid()`-pinned
ownership re-check). The mirror was genuinely faithful — every offline shape test
and `tsc --noEmit` passed, and the security core (RLS SELECT-owner-only, no
owner-write policy, REVOKE incl. `service_role`, jti-deny RESTRICTIVE, composite-FK
owner guard, `FOR UPDATE` re-check, PII-safe synthetic-error observability) was
correct.

Yet a 9-agent review panel surfaced **1 P1 + 6 P2** — all in the seams where the
precedent's shape carried a guarantee that did **not** transfer to the new role, or
where the new role introduced a surface the precedent never had. A single-pass author
plus shape-tests plus `tsc` caught **none** of them.

## Root cause

"Copy the precedent shape" optimises for structural fidelity, not for the new role's
invariants. The email-triage precedent is a **statutory WORM ledger with a monotone
one-way status and controller-stamped timestamps**; the beta-CRM is a **mutable CRM
with a free bidirectional stage enum and caller-settable timestamps feeding a
destructive retention sweep**. Same structure, different lifecycle — so the guards
must be re-derived from the new role, not copied.

## The four concrete instances (all fixed inline)

1. **Down-migration: drop a trigger function AFTER its table, never before.**
   `DROP FUNCTION` defaults to `RESTRICT`, and `IF EXISTS` suppresses only the
   *does-not-exist* case — **not** the `pg_depend` dependency error. A trigger records
   a normal dependency on its function, so `DROP FUNCTION beta_contacts_set_updated_at()`
   *before* `DROP TABLE beta_contacts` raises `2BP01 cannot drop function … because
   other objects depend on it` and, inside the down migration's transaction, **aborts
   the entire rollback** — the file cannot roll back at all. Fix: drop the trigger
   function after the table (`DROP TABLE … CASCADE` removes the trigger first), or add
   `CASCADE`. RPC functions with no persistent dependents drop cleanly in any order —
   only trigger/default/view-referenced functions have this ordering constraint.

2. **PII-in-CHECK-DETAIL: if you pre-validate SOME columns, pre-validate ALL of them.**
   The RPC pre-validated `stage` and `amount_basis` before the write with the explicit
   rationale "so a bad enum never trips the column CHECK (whose `Failing row contains
   (…)` DETAIL carries name/company)" — but left `currency ~ '^[A-Z]{3}$'` and
   `amount ⇒ currency` un-pre-validated. A malformed write trips those column CHECKs
   (`23514`), whose DETAIL enumerates every row value — third-party `name`/`company` —
   into the **Postgres server logs**, the exact surface the pre-validation exists to
   protect. A partial defense-in-depth stance is an inconsistency a reviewer will flag;
   pre-validate **every** column whose CHECK failure would carry PII, on **every**
   branch (INSERT literal AND the UPDATE post-COALESCE effective value).

3. **A caller-settable timestamp feeding a destructive sweep needs a monotonicity floor
   on EVERY setter path.** `crm_note_append` correctly advanced `last_contact` forward
   only (`GREATEST`) so a backdated note couldn't drag the 24-month retention clock
   backwards and silently expire an active contact — but `crm_contact_upsert` set the
   same column with a bare `COALESCE` (no floor), and `crm_contact_set_stage` never
   refreshed it at all (a stage-only-worked contact kept a stale anchor → silent purge).
   The retention DELETE **CASCADEs** the contact + all its history, so this is silent
   data loss on a `single-user incident` surface. Fix: apply the same forward-only floor
   (or refresh) on every path that can influence the sweep's key — the note path getting
   it is not enough. (Same class as
   [[2026-06-30-precedent-mirror-for-new-role-breaks-fencing-token-monotonicity]].)

4. **A human-review-gate message doubles as the OFFLINE notification — do not embed
   verbatim third-party PII in it.** `buildGateMessage` strings are shown in the
   in-session review modal AND, when the operator is offline, passed to
   `permission-callback → notifyOfflineUser → push + email` (Resend). Embedding the
   verbatim note `body` / contact `name` (for in-session review value) therefore
   **egresses third-party conversation PII to a sub-processor (Resend) + the operator's
   plaintext inbox — a transport NOT listed in the Article 30 register** (whose
   recipients enumerated only Anthropic for the agent-read path). Reconciliation: show
   **decision-relevant fields** (stage, amount, dates incl. the retention-relevant
   `last_contact`, WHICH fields change) but **redact the verbatim PII values** (body
   text, name/company) — the operator opens the record in-app to review exact text. This
   gives review value (agent-native parity) without widening the PII egress surface
   (recipient-completeness).

## Key insight

**A faithful 1:1 precedent mirror is not proof of correctness for a DIFFERENT role.**
Before shipping a mirrored migration/tool, enumerate the NEW role's invariants and, for
each protective idiom in the precedent, ask two questions: (a) *does the precedent's
guarantee still hold for this role?* (bidirectional enum vs one-way status; settable vs
stamped timestamp; mutable vs WORM), and (b) *does the new role introduce a surface the
precedent never had?* (a caller-settable retention input; a gate message that egresses;
a PII column whose CHECK DETAIL leaks). Apply the guards **uniformly across all analogous
paths**, not just the one path you happened to harden first.

## Prevention

- **Route mirrored-migration/agent-tool PRs through the full multi-agent review**, and
  prompt `architecture-strategist` explicitly with "a faithful mirror is not proof of
  correctness for a different role — enumerate the new role's invariants against the
  precedent's lifecycle." That framing is what surfaced the retention-clock monotonicity
  (P2) that shape-tests + tsc + single-pass all missed.
- For down-migrations: assert the trigger-function drop comes **after** its table (a
  cheap `downSql.search(fnDrop) > downSql.search(tableDrop)` regression guard).
- For PII-carrying CHECK columns: pre-validate them all in the RPC; the offline shape
  test asserts each pre-check's presence.
- For destructive retention sweeps keyed on a settable column: add a live test that a
  backdated setter does not regress the key, and grep every RPC that writes the key.
- For gate messages: treat them as **egress surfaces** (they reach offline push/email),
  not just in-session modals — redact third-party verbatim PII, show decision fields only.

## Session Errors

1. **Migration # collision (123→126)** — siblings landed 123/124/125 between plan
   authoring and /work. Recovery: renumbered ADR + migration at work-start (pre-apply
   collision check). Prevention: already covered by the pre-apply `git ls-tree
   origin/main` collision check + ship-time re-check; handled correctly — one-off.
2. **ADR ordinal collision (098→102)** — sibling landed `ADR-098-soleur-owns-auth-flow`.
   Recovery: `git mv` + renumber sweep. Prevention: existing ADR-ordinal collision gate
   covers it — one-off.
3. **`Edit` "file modified since read" after perl in-place edits** — Recovery: re-Read
   before Edit. Prevention: expected tool behavior after an out-of-band write; one-off.
4. **down.sql `2BP01` (trigger fn dropped before table)** — Recovery: reorder after
   DROP TABLE + regression guard. Prevention: see instance 1 above.
5. **upsert PII-in-CHECK asymmetry** — Recovery: pre-validate currency/amount⇒currency.
   Prevention: see instance 2 above.
6. **retention-clock monotonicity asymmetry** — Recovery: GREATEST/refresh on all setter
   paths. Prevention: see instance 3 above.
7. **gate-message PII egress** — Recovery: redact verbatim PII from gate strings.
   Prevention: see instance 4 above.
8. **vitest zero-arg mock tuple (TS2352)** — Recovery: typed rest params on `vi.fn`.
   Prevention: already-documented trap (`vi.fn((..._a: unknown[]) => …)`); one-off.
