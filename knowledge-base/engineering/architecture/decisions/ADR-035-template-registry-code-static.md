---
adr: ADR-035
title: Template registry — code-static literals + first-send-IS-authorization
status: accepted
date: 2026-05-21
related: [4078]
related_adrs: [ADR-034-action-class-registry-static-literals-and-enum-absence, ADR-033-per-tenant-scope-grants]
related_plans:
  - knowledge-base/project/plans/2026-05-21-feat-pr-i-template-authorizations-plan.md
brand_survival_threshold: single-user incident
---

# ADR-035: Template registry — code-static literals + first-send-IS-authorization

## Context

PR-H (#4077, merged via #4065 on 2026-05-19) shipped the trust-tier external classes (`external_low_stakes`, `external_brand_critical`, `auto_with_digest`), the `action_sends` WORM signature ledger (mig 051), and the Send/Edit/Discard wiring at `today-card.tsx`. PR-H deliberately deferred the per-template authorization layer — `templateHashFor` at `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:70-80` was a placeholder computing `sha256(action_class:owning_domain:tier)`, collapsing every send for a given (class, domain, tier) into one hash bucket. Under Art. 7(3) ("specific" + "informed" consent), a per-template authorization defense is structurally weak when the hash is not per-template.

PR-I (#4078) closes this. Two architectural questions emerge with the per-template layer:

1. **How are templates identified at producer call sites?** A free-text `template_id` admits typos; a DB-table registry adds a roundtrip on every webhook; a runtime classifier mints templates dynamically and reopens the un-revocability question that Art. 7(3) is designed to close (consent must be specific to a template the founder can see ahead of time).

2. **When does the founder consent to a per-template authorization?** Requiring a separate authorize-this-template UI step on top of the existing scope-grant grant-this-class UI doubles the consent friction without changing the Art. 7(3) substance — the founder already chose to authorize the action class at the tier level. The Send click is itself a deliberate UI act with a typed-confirm context applied to brand-critical classes.

## Decision

(1) **Code-static template registry.** Define `TEMPLATE_IDS` as a frozen `as const` literal union at `apps/web-platform/server/templates/template-registry.ts`, mirroring ADR-034's `ACTION_CLASSES` pattern. Each template_id has a `TEMPLATE_REGISTRY` row keyed off the literal; `getTemplateHash(message)` returns `sha256(body_template)` where `body_template` is the canonical pre-personalisation template text. A new template requires:

- A code edit (adding the new literal to `TEMPLATE_IDS`).
- A passing parity test (`test/server/templates/template-registry.test.ts` covers pairwise hash collision regression + determinism + unknown-id fallback).
- The same migration discipline as `messages.template_id` shape CHECK (DB-side enum-absence by regex — defense-in-depth).

This is NOT runtime-mintable. A new template that did not pass code review cannot exist.

(2) **First-send-IS-authorization.** The founder's Send click on a labeled `draft_one_click` button — with PR-H's typed-confirm context for higher-friction tiers — IS the Art. 7(3) "specific" + "informed" consent act. The send route at `app/api/dashboard/today/[id]/send/route.ts` implements this:

- After `isGranted` succeeds (the founder has authorized the action_class at a tier), the route calls `isTemplateAuthorized(supabase, founderId, templateHash, grantId)`.
- On `status === 'first_send'` (no existing row), the route calls `authorize_template` RPC then proceeds to write the `action_sends` row.
- On subsequent sends, `isTemplateAuthorized` returns `authorized` (with bounds in range) and the existing row gates the request.
- On `status === 'denied'`, the route returns 403 with `deny_reason` (one of `template_revoked` / `template_expired` / `template_quota_exhausted`); the today-card surfaces a per-DenyReason note.

## Consequences

(a) **Type-safe template lookup at every call site.** `getTemplateHash` reads `messages.template_id` from the SELECT projection (added at mig 053 Part A); producers MUST set `template_id` to a registry-known value or fall through to `default_legacy` with a `warnSilentFallback` emit. The TS layer narrows; the DB shape CHECK enforces.

(b) **Single deny channel.** The discriminated `PredicateResult` union (`authorized | first_send | denied`) carries the deny_reason to the route; the route emits a pino structured log per denial (`{template_hash, action_class, deny_reason, founder_id_hash}`) but NO Sentry mirror — denials are expected Art. 7(3) behavior, not silent fallbacks. Sentry tags are reserved for actual errors (`template_predicate_timeout`, `template_authorization_race`, `template_worm_bypass_failed`, `dsr_cascade_ordering`).

(c) **Auto-revoke best-effort.** On expired / quota-exhausted detection inside the predicate, the system fires `revoke_template_authorization(template_hash, 'expired'|'quota_exhausted')` fire-and-forget so the scope-grants UI does not display lying rows. Failure logs via `warnSilentFallback` but does NOT mask the denial — the founder sees the right inline note regardless.

(d) **Un-revocability + Art. 5(2) attribution (former ADR-036, folded here per plan v2 review).** The `revocation_reason` enum has 8 values (`founder_revoked`, `quota_exhausted`, `expired`, `dsr_erasure`, `regulator_ordered`, `vendor_tos_revoked`, `policy_violation`, `quarantine_retroactive`). The over-provision distinguishes Art. 5(2) attribution for future revocation drivers (regulator orders, vendor TOS, AUP enforcement, classifier feedback). Cheaper to add at mig 053 than ALTER later. The parity test reads the mig 053 source and asserts set-equality with the TS keys in `REVOCATION_REASON_COPY` — drift on either side fails the build.

(e) **Two-probe ordering (former ADR-037, folded here per plan v2 review).** `isGranted` runs FIRST at `send/route.ts`. Three reasons: (i) preserves the existing fail-closed trust model — no scope grant means no template auth has any meaning; (ii) some tiers (`auto_with_digest`, `approve_every_time`) don't carry template authorizations in v1 — short-circuit saves the second probe; (iii) `template_quarantined` (PR-I+1, #4216) is a child of `scope_grant` revocation semantically — if the grant is revoked, all template auths under it are reachable for cleanup via the cascade.

(f) **WORM bypass mechanism.** `SET LOCAL session_replication_role='replica'` at the SECURITY DEFINER RPC layer (mig 051 §(h) precedent). NOT `current_user='service_role'` — that pattern is silently always-false under PostgREST routing per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`. The `template_authorizations_no_mutate` trigger is pure-reject (raises P0001); only the three SECURITY DEFINER RPCs (`authorize_template`, `revoke_template_authorization`, `anonymise_template_authorizations`) traverse it.

(g) **Semantic cascade ordering at account-delete.ts.** `anonymise_template_authorizations` runs BETWEEN `anonymise_action_sends` and `anonymise_scope_grants`. The ordering is **semantic, not FK-driven** — `anonymise_*` performs UPDATE so the ON DELETE RESTRICT FK on `template_authorizations.grant_id → scope_grants.id` does not fire. The load-bearing invariant is that `dsr_erasure` reason must be set on these child rows BEFORE the parent grant's `founder_id` is nulled, otherwise Art. 5(2) attribution breaks. The inline comment in `account-delete.ts` cites this rationale verbatim — do not regress to the old "FK RESTRICT requires this ordering" wording.

(h) **TOCTOU race acknowledged.** The predicate's read and the action_sends INSERT are not atomic at the supabase-js layer. Worst case: a one-RTT window where a concurrent revoke between probe and write admits one over-quota send. This is a pre-existing PR-H risk class (`isGranted` has the same race) and is acceptable at single-user-incident threshold. The auto-revoke side effect closes the visible state on the next read.

## Rejected alternatives

- **Runtime template classifier** — would mint templates dynamically and reopen Art. 7(3) un-specificity. Producers must declare the literal up-front at the `inngest.send` boundary; classifier-style guessing is an explicit non-goal.
- **DB-table registry** — adds a roundtrip on every webhook + introduces drift between table content and producer code that tsc cannot see. Code-static literals are reviewer-visible and parity-tested.
- **Separate authorize-this-template UI step** — doubles consent friction without changing the Art. 7(3) substance. The founder already chose to grant the action_class at a tier; the Send click on a labeled `draft_one_click` button IS the per-template "specific" + "informed" act.
- **Inner BEGIN/COMMIT envelope on mig 053** — proposed by plan v2 architecture review. Rejected at /work execution time: mig 051 line 28 explicitly directs NO outer transaction (Supabase runner already wraps). Inner BEGIN would either no-op under savepoint semantics or prematurely COMMIT the outer envelope.

## Open follow-ups

- **#4216** (PR-I+1) — Classifier-feedback retroactive UI; introduces the `quarantine_retroactive` revocation_reason value into production code (the enum value is pre-provisioned in mig 053 to avoid an ALTER later).
- **#4217** — Bound calibration. The provisional defaults (100 sends / 30-day soft re-confirm / 90-day hard expiry) are educated guesses; cohort-based tuning lives downstream. Existing rows are UPDATE-able through the bypass RPC if needed.
- **#3739** — Sentry helper consolidation (`reportSilentFallbackWithUser`). PR-I uses helpers as-shipped; #3739 will sweep the PR-I sites alongside the 11 existing sites.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-21-feat-pr-i-template-authorizations-plan.md`
- Spec: `knowledge-base/project/specs/feat-pr-i-template-authorizations-4078/spec.md`
- Article 30 register: Processing Activity 18 (`knowledge-base/legal/article-30-register.md`)
- DPD §2.3(t): `docs/legal/data-protection-disclosure.md`
- Privacy Policy §8.3 extension: `docs/legal/privacy-policy.md`
- AUP §5.4 extension: `docs/legal/acceptable-use-policy.md`
- Predicate: `apps/web-platform/server/templates/is-template-authorized.ts`
- Registry: `apps/web-platform/server/templates/template-registry.ts`
- Migration: `apps/web-platform/supabase/migrations/053_template_authorizations.sql`
- Send route: `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`
- Cascade: `apps/web-platform/server/account-delete.ts` step 3.83

---

> **See also (2026-07-20, #6781):** the `plain-insert-catch-23505` dedup idiom and its
> send-boundary extension (branch-derived tick keys, fail-open, the recipient-grain
> constraint) live in the ADR whose frontmatter is `adr: 035` — the file
> `ADR-037-messages-source-ref-composite-unique-for-multi-source-dedup.md`, **not** this one.
> The ordinal collision between that frontmatter value and this file's name is tracked
> separately; no decision content here is affected.
