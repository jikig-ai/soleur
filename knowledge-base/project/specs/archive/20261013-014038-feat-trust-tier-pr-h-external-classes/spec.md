---
title: PR-H — Trust-tier external classes
date: 2026-05-19
tracking_issue: 4077
parent_issue: 3244
parent_pr: 3940
sibling_pr: 3984
draft_pr: 4065
brainstorm: knowledge-base/project/brainstorms/2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# PR-H — Trust-tier external classes (`external_low_stakes`, `external_brand_critical`, `auto_with_digest` wiring)

Closes umbrella #3244 unchecked acceptance criterion: "Trust-tier policy engine: 5 action classes (read/draft auto, internal infra auto+digest, external low-stakes draft+1-click, external brand-critical approve-every-time, money/legal/credentials per-command ack)."

## Problem Statement

Umbrella #3244 ships in 7 sequenced PRs. PR-F (#3940) shipped the 3-tier policy vocabulary, `messages_external_tier_status_check` DB CHECK, and the Stripe → Inngest → CFO autonomous-draft flow. PR-G (#3984) shipped the per-tenant scope-grants substrate, the audit-log viewer, the 3-radio scope-grants UI, and the legal amendments (T&C 2.0.0, AUP §5.4, Privacy §8.3, DPD §2.3(o), Article 30 PA-13/PA-14, ADR-033).

Two trust-tier classes from the parent plan §3.4 remain unwired:
- `external_low_stakes` (draft + 1-click)
- `external_brand_critical` (approve every time)

In addition, PR-G shipped the Send/Edit/Discard buttons in `today-card.tsx:48-73` with `disabled` + `title="Wires in PR-G (#3947)"` but did NOT wire the handlers. The action-class registry contains only `finance.payment_failed`; no end-to-end path exists for the founder to act on a draft. PR-H closes both gaps and lands the `auto_with_digest` 4th tier per parent plan §3.4 ("internal infra auto+digest"). The 5th class (`money_legal_credentials`) is enforced by enum-absence — unreachable through `ACTION_CLASSES`, falls through `isGranted → null → fail-closed`.

## Goals

1. Extend `ACTION_CLASSES` registry from 1 → ~12 entries across 4 categories (`external.low_stakes.*`, `external.brand_critical.*`, `infra.*`, `finance.*`).
2. Add `auto_with_digest` as 4th value in `ActionClassTier` enum and `scope_grants.tier` CHECK.
3. Wire `today-card.tsx` Send/Edit/Discard buttons to real route handlers (re-check `isGranted` at click-time; branch on effective tier).
4. Ship typed-confirmation modal component for `approve_every_time` tier (renders exact payload; requires founder to type "SEND" verbatim; server-side re-validates).
5. Add new `action_sends` WORM table at migration 051 with `template_hash`, `per_send_body_sha256`, `clicked_at`, `confirmed_typed`, `approval_signature_sha256`, `grant_id` columns. Mirror `audit_byok_use` (mig 037) pattern.
6. Add `messages.action_class` column at migration 051 so `isGranted` re-check at Send-click can resolve the class.
7. Ship Inngest scheduled function emitting daily `infra.*` digest to the founder's Today section.
8. Update legal artifacts: Article 30 PA-15 "Template-authorized autonomous send"; DPD §2.3(p) `external_low_stakes`; DPD §2.3(q) `auto_with_digest`; Privacy §8.3 template-authorization sub-clause + Art. 22(3) digest-clarification one-liner.
9. Draft 2 ADRs: (a) "Action-class registry is code-static, declared at producer call sites"; (b) "Money/legal/credentials category enforced by enum-absence, not parallel DB CHECK".
10. Ship the union-widening parity test for `ACTION_CLASS_DEFAULTS` and `ACTION_CLASS_CATEGORY` (per `cq-union-widening-grep-three-patterns`).

## Non-Goals (deferred to PR-I)

- `template_authorizations` WORM table.
- Template authorization bounds (100 sends OR 30 days; 90-day hard expiration; 30-day re-confirmation soft prompt).
- Retroactive classifier-feedback loop (founder flags past `external_low_stakes` as `brand_critical` via `/dashboard/audit`).
- Quarantine future sends from same `template_hash`.
- LLM-based runtime classifier inspecting recipient/channel/audience signals (Phase 2 evolution).
- Outbound *delivery* integrations (Bluesky API client, marketing-email-blast adapter, X/Twitter publish API). PR-H ships the *gating* layer; producer call sites that don't yet have an integration ship as no-op stubs that write to `action_sends` but skip the actual send.
- Cohort flip of `SOLEUR_FR5_ENABLED=true` — remains a separate post-merge operator step per PR-G's pattern.

## Functional Requirements

**FR1.** `action-class-map.ts` exports `ACTION_CLASSES` containing at minimum: `finance.payment_failed` (existing), 4 `external.low_stakes.*` entries, 5 `external.brand_critical.*` entries, 2 `infra.*` entries. Exact final list confirmed in /plan.

**FR2.** `ActionClassTier` enum value list: `"auto" | "draft_one_click" | "approve_every_time" | "auto_with_digest"`. `scope_grants.tier` CHECK constraint widened at mig 051.

**FR3.** `ACTION_CLASS_CATEGORY: Record<ActionClass, "finance" | "external_low_stakes" | "external_brand_critical" | "infra">` discriminant added.

**FR4.** `ACTION_CLASS_DEFAULTS` populated per category:
- `finance.*` → `approve_every_time` (existing).
- `external.low_stakes.*` → `draft_one_click`.
- `external.brand_critical.*` → `approve_every_time`.
- `infra.*` → `auto_with_digest`.

**FR5.** New routes at `app/api/dashboard/today/[id]/{send,edit,discard}/route.ts`. Mirror `/api/scope-grants/grant/route.ts` shape (founder JWT auth, origin/CSRF gate, JSON body, Sentry breadcrumbs).

**FR6.** Send route: re-call `isGranted(serviceClient, founderId, message.action_class)` at click-time. Branch on returned `tier`:
- `draft_one_click` → write `action_sends` row; perform outbound effect (or stub if no integration); flip `messages.status` to `archived`.
- `approve_every_time` → return `409 requires_confirmation` if request body lacks `confirmed_typed=true` AND `typed_value === "SEND"`; otherwise proceed as `draft_one_click` PLUS capture `approval_signature_sha256 = sha256(founderId || messageId || typedValue || timestamp)`.
- `auto` or `auto_with_digest` → reject 400 ("Send is not the founder-initiated path for this tier"). Sends for these tiers fire from the producer; the today-card Send button is for human-in-the-loop tiers only.

**FR7.** Typed-confirm modal component at `apps/web-platform/components/dashboard/typed-confirm-modal.tsx`. Renders: recipient identifier (e.g., email address, Bluesky handle, channel name), content excerpt (first 200 chars + ellipsis), action_class label, tier label. Input field with placeholder "Type SEND to confirm". Submit button disabled until input value equals "SEND" (case-sensitive). On submit, POST to send route with `confirmed_typed=true` + `typed_value` + `messageId`.

**FR8.** `action_sends` WORM table at mig 051:
```sql
CREATE TABLE public.action_sends (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  founder_id               uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  message_id               uuid NOT NULL REFERENCES public.messages(id),
  action_class             text NOT NULL CHECK (length(action_class) BETWEEN 1 AND 64),
  tier_at_send             text NOT NULL CHECK (tier_at_send IN ('auto', 'draft_one_click', 'approve_every_time', 'auto_with_digest')),
  template_hash            text NOT NULL,
  per_send_body_sha256     text NOT NULL,
  recipient_id_hash        text NOT NULL,
  clicked_at               timestamptz NOT NULL DEFAULT now(),
  confirmed_typed          boolean NOT NULL DEFAULT false,
  approval_signature_sha256 text NULL,
  grant_id                 uuid NOT NULL REFERENCES public.scope_grants(id)
);
ALTER TABLE public.action_sends ENABLE ROW LEVEL SECURITY;
-- Owner-select RLS + shape-validated WORM trigger (no role check). Pattern from mig 037 + 048.
```
Per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`: NO role-check bypass; shape-validation only.

**FR9.** `messages.action_class text NULL` column added at mig 051. CFO function (`cfo-on-payment-failed.ts`) updated to populate it; existing draft rows backfilled to `'finance.payment_failed'` on migration.

**FR10.** Inngest scheduled function `server/inngest/functions/digest-infra-actions.ts`. Cron: daily 09:00 founder-local-tz (or UTC if tz unset). Aggregates `action_sends` rows where `tier_at_send='auto_with_digest'` AND `founder_id=<f>` AND `clicked_at > now() - 24h`. Persists a digest entry surfaced in the founder's Today section. Sentry-on-error.

**FR11.** Article 30 PA-15 drafted via `legal-document-generator` agent. DPD §2.3(p) + (q) added. Privacy §8.3 template-authorization sub-clause + Art. 22(3) digest-clarification one-liner added.

**FR12.** ADR-NN (next free number) "Action-class registry is code-static, declared at producer call sites" + ADR-NN+1 "Money/legal/credentials category enforced by enum-absence" drafted via `/soleur:architecture create`.

## Technical Requirements

**TR1.** Migration `051_action_sends.sql` (or first free number — verify with `ls apps/web-platform/supabase/migrations/`). Action_sends WORM table + `messages.action_class` column + `scope_grants.tier` CHECK widening to include `auto_with_digest`. Shape-validated trigger, no role-check bypass.

**TR2.** Lint test asserts every `inngest.send` / `isGranted` call passes a typed `ActionClass` literal, not a `string`. Pattern: AST grep over `apps/web-platform/server/` and `apps/web-platform/app/api/`.

**TR3.** Union-widening parity test asserts `ACTION_CLASS_DEFAULTS` and `ACTION_CLASS_CATEGORY` cover every `ACTION_CLASSES` entry. Test fails if a new entry is added without parity updates.

**TR4.** Enum-absence regression test asserts that no `ACTION_CLASSES` entry matches the prefix regex `/^(payment|legal|auth)\./` (5th-category prefix list). Failure message points to ADR.

**TR5.** Live-DB integration test for the `action_sends` WORM trigger. Mocked tests are insufficient per learning `2026-05-17-mocked-tests-miss-shared-table-schema-gaps.md`. Gated by `TENANT_INTEGRATION_TEST=1`; runs against dev Supabase.

**TR6.** Send route server-side re-validation of typed string: `request.body.typed_value === "SEND"` (case-sensitive). Reject 422 otherwise. Test fixture confirms client-side bypass attempt fails.

**TR7.** Cross-tenant Send-route denial: founder A cannot send a message owned by founder B. RLS + belt-and-suspenders `.eq("founder_id", user.id)` per PR-G's `route.ts:437` precedent.

**TR8.** Send route re-checks `isGranted` at click-time even if the draft was created under a valid grant. The grant may have been revoked between draft-write and click. Test asserts revoked-mid-flight returns 403.

**TR9.** Typed-confirm modal accessibility: keyboard-only operation (Tab + Enter + Esc), screen-reader-announced via ARIA, mobile-tap-friendly (44×44 px minimum tap targets, no hover-only affordances). Web platform is PWA-first per roadmap T1.

**TR10.** Digest-emitter Sentry-on-error per `cq-silent-fallback-must-mirror-to-sentry`. If digest emission fails, founder sees no digest entry; runbook entry "if Sentry alerts on `digest-infra-actions`, manually trigger via Inngest UI within 12h."

**TR11.** Transparency-surface re-audit per learning `2026-05-12-brainstorm-re-audit-inherited-transparency-surfaces.md`. PR-G's `RuntimeExplainerBanner`, AUP §5.4, T&C 2.0.0, Art. 22(3) mailto/Change-authorization links: evaluate each for PR-H cohort fit; drop the ones a cheaper channel could replace.

**TR12.** Classifier-collision discipline per learning `2026-05-15-classifier-prose-table-row-ordering-collision.md`. Enumerate every existing class trigger description (currently 1 — `finance.payment_failed` from Stripe webhook) for keyword overlap with each new class; place more-specific classes first in any prose table.

**TR13.** No new env flag. Per learning `2026-05-19-doppler-env-hot-reload-limitation.md` (Pending — sibling-branch commit `59b79a53`): env flags are global kill-switches, not per-tenant gates. PR-H relies on the per-grant DB predicate (`is-granted.ts:25`) for tenant isolation.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1.** All FR1-FR12 implemented.
- **AC2.** All TR1-TR13 verified by passing tests.
- **AC3.** `bun test` clean (`apps/web-platform` unit + component suites).
- **AC4.** `tsc --noEmit` clean.
- **AC5.** Live-DB integration test (`TENANT_INTEGRATION_TEST=1`) passes against dev Supabase for action_sends WORM trigger.
- **AC6.** Multi-agent review (≥9 agents) returns 0 P1, ≤2 P2 findings; all fixed inline.
- **AC7.** `semgrep-sast` returns 0 findings.
- **AC8.** Article 30 PA-15 drafted; DPD §2.3(p)+(q) added; Privacy §8.3 amendments added. Both DPD mirrors updated.
- **AC9.** 2 ADRs drafted and `status: accepted`.
- **AC10.** `apps/web-platform/components/dashboard/today-card.tsx` Send/Edit/Discard buttons are NO LONGER `disabled`; `title="Wires in PR-G (#3947)"` removed.
- **AC11.** `user-impact-reviewer` agent invoked at PR review-time (required under `brand_survival_threshold: single-user incident`).

### Post-merge (operator)
- **POST-1.** Apply mig 051 to dev + prd via `web-platform-release.yml` CI `migrate` job. `verify-migrations` job confirms.
- **POST-2.** Set `SOLEUR_FR5_ENABLED=true` in Doppler `prd` (already flipped by PR-G post-merge step — confirm still true).
- **POST-3.** Synthetic smoke against prd: send Stripe TEST-mode `invoice.payment_failed`; verify CFO Today card appears with new Send button enabled; verify typed-confirm modal renders.
- **POST-4.** Verify `action_sends` row written on synthetic 1-click send.
- **POST-5.** Verify `infra.*` digest scheduled function is registered with Inngest.
- **POST-6.** Operator closes #3244 unchecked AC.

## Risks & Sharp Edges

- **The `action_sends` WORM trigger** must use shape-validation, NOT role-check, per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`. Live-DB integration test is the only catch surface (mocked tests miss this).
- **Migration numbering conflict** at 048/049/050. PR-H uses 051. Renumbering applied migrations is destructive; file separate hygiene issue for the duplicate.
- **`messages.tier='digest'` widening** — open question 2 in brainstorm. If digest persists as a `messages` row, the `messages_external_tier_status_check` constraint may need widening. Verify before mig 051.
- **Typed-confirm modal bypass via client-side script.** Server-side re-validation of `typed_value === "SEND"` is the load-bearing safety net (TR6).
- **PR-G `today-card.tsx` button stub** is the hidden incomplete AC. Without wiring, PR-H ships an unobservable registry. AC10 verifies removal of the `disabled` + title stub.
- **Doppler hot-reload limitation** (Pending learning, sibling-branch). PR-H plan-time should re-verify the learning file lands on main before PR-H references it in tests.
- **5th-class enum-absence drift.** A future PR could add `payment.refund` to `ACTION_CLASSES` without code review catching the violation. TR4 enforces; the test failure message points to the ADR.

## Dependencies

- Umbrella: #3244 (OPEN — `feat: Command Center server-side agentic runtime (alignment + hardening)`).
- PR-F: #3940 (merged 2026-05-17) — trust-tier 3-tier MVP, DB CHECK, CFO function.
- PR-G: #3984 (merged 2026-05-19) — scope-grants substrate, audit viewer, 3-radio UI.
- Pending sibling-branch learning: `docs-compliance-posture-pr-g-post-merge-gates` (commit `59b79a53`).

## Out of scope (separate issue candidates)

- Migration numbering hygiene (048/049/050 duplicate) — file as tech-debt issue.
- LLM-based runtime classifier — Phase-2 evolution after 5+ orgs.
- Outbound delivery integrations (Bluesky, marketing email, X publish, blog publish) — separate issues per producer; PR-H ships the gating layer, producers ship the wire.
