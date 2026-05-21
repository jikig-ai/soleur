---
title: PR-I — Template authorizations (structural ship)
date: 2026-05-21
tracking_issue: 4078
parent_issue: 3244
predecessor_pr: 4065
brainstorm: knowledge-base/project/brainstorms/2026-05-21-pr-i-template-authorizations-brainstorm.md
draft_pr: 4213
lane: cross-domain
brand_survival_threshold: single-user incident
domains_assessed: [Product, Legal, Engineering]
triad_mandated: true
status: draft
---

# PR-I — Template authorizations + per-template registry + Art-17 cascade (classifier-feedback deferred to PR-I+1)

Closes umbrella #3244 §3.4 follow-through: the durable per-1-click E&O substrate that satisfies GDPR Art. 7(3) "as easily as given" for `draft_one_click` sends. Single PR (Approach A), atomic ship of registry + WORM table + predicate + bounds + revocation + surface + cascade + legal artifacts.

## Problem Statement

PR-H (#4077, merged via #4065 on 2026-05-19) shipped the trust-tier external classes (`external_low_stakes`, `external_brand_critical`, `auto_with_digest`), the `action_sends` WORM signature table, the Send/Edit/Discard wiring at `today-card.tsx`, the `typed-confirm-modal`, and four legal artifact landings (PA-15, DPD §2.3(p)+(q), Privacy §8.3, ADR-034). It deliberately deferred the `template_authorizations` substrate to keep the review surface under the 11-agent brand-survival ceiling.

Two consequences leave Art. 7(3) defensibility incomplete:

1. **`templateHashFor` is a placeholder.** `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:70-80` computes `sha256(action_class:owning_domain:tier)`. Every send for the same (class, domain, tier) collides into one bucket. No per-template granularity exists today — meaning "authorize THIS template for THIS recipient" is not yet a representable concept.
2. **No template-level revocation surface.** A founder can revoke a `scope_grant` (whole action_class) but cannot revoke authorization for a single template they later regret. Under Art. 7(3) "as easily withdrawable as given," granting at template-level requires revoking at template-level.

PR-I closes both by introducing a canonical template registry, a `template_authorizations` WORM table parallel to `scope_grants`, and a two-probe predicate path. Classifier-feedback (retroactive reclassification via `/dashboard/audit`) is deferred to PR-I+1; all primitives are pre-wired so PR-I+1 is a UI-only addition.

## Goals

1. Replace the placeholder `templateHashFor` with `sha256(canonical_template_body)` where `canonical_template_body` is resolved from a code-static template registry.
2. Persist per-template authorization with bound calibration parameters (sends, hard expiry, soft re-confirm) in a WORM table.
3. Provide a two-probe predicate (`isGranted` + `isTemplateAuthorized`) at every send call site with a single discriminated `DenyReason` channel back to the today-card.
4. Wire founder-initiated revocation through `/dashboard/settings/scope-grants`.
5. Extend the Art-17 cascade in `account-delete.ts` to anonymise `template_authorizations` between `action_sends` and `scope_grants` (preserves FK chain).
6. Land legal artifacts (PA-16, DPD §2.3(t), Privacy §8.3 extension, AUP one-liner).
7. Pre-wire the `quarantine_retroactive` reserved enum value, the WORM table, and the predicate so PR-I+1 ships only the audit-page reclassification UI.

## Non-Goals

1. Retroactive classifier-feedback UI (`/dashboard/audit` reclassification + QUARANTINE typed-confirm) — deferred to PR-I+1.
2. Activating the `quarantine_retroactive` revocation reason — reserved in CHECK but no consumer in PR-I.
3. Tuning the provisional bound defaults (100 sends / 90-day hard expiry / 30-day soft re-confirm) — deferred to the calibration follow-up issue once ≥1 founder has executed ≥10 `draft_one_click` sends.
4. LLM-runtime template classifier — explicitly out per ADR-034 (code-static registry).
5. Cross-tenant `recipient_id_hash` salt review — `recipient_id_hash` derivation is per-tenant scoped already (see PR-H ADR); no re-architecture needed.
6. Outbound delivery integrations (Bluesky, marketing-email-blast, X publish, blog) — deferred per PR-H plan §"Out of Scope" line 560.
7. T&C amendment — §3a Agent Command Authority already tier-agnostic.

## Functional Requirements

| ID | Requirement |
|---|---|
| FR1 | A canonical template registry `apps/web-platform/server/templates/template-registry.ts` exports a literal-union `TEMPLATE_IDS` + a record `TEMPLATE_REGISTRY: Record<TemplateId, CanonicalTemplate>` containing `{ id, body_template, action_class, owning_domain }`. Mirrors `action-class-map.ts:23-45` pattern. |
| FR2 | `messages.template_id text NOT NULL REFERENCES nothing` (registry is code-static; CHECK constraint validates against enum-absence pattern matching `TEMPLATE_IDS`). Historical messages backfilled to `default_legacy`. |
| FR3 | `templateHashFor(message)` in `send/route.ts` is replaced by `getTemplateHash(message)` returning `sha256(canonicalize(TEMPLATE_REGISTRY[message.template_id].body_template))`. |
| FR4 | A `template_authorizations` table exists (mig 053) with columns: `id uuid PK DEFAULT gen_random_uuid()`, `founder_id uuid NOT NULL`, `template_hash text NOT NULL`, `action_class text NOT NULL` (enum-absence CHECK matching `ACTION_CLASSES`), `authorized_at timestamptz NOT NULL DEFAULT now()`, `expires_at timestamptz NOT NULL DEFAULT (now() + interval '90 days')`, `soft_reconfirm_at timestamptz NOT NULL DEFAULT (now() + interval '30 days')`, `max_sends integer NOT NULL DEFAULT 100`, `revoked_at timestamptz NULL`, `revocation_reason text NULL` (CHECK in 8-value enum), `grant_id uuid NOT NULL REFERENCES scope_grants(id) ON DELETE RESTRICT`. |
| FR5 | Partial UNIQUE index `template_authorizations_active_unique (founder_id, template_hash) WHERE revoked_at IS NULL`. |
| FR6 | WORM trigger `template_authorizations_no_mutate()` SECURITY DEFINER, FOR EACH STATEMENT, pure-reject on UPDATE/DELETE — except via `SET LOCAL session_replication_role='replica'` inside the anonymise RPC (mig 051 L224 pattern). |
| FR7 | RLS: `template_authorizations_owner_select` (cookie-scoped SELECT WHERE founder_id = auth.uid()); `template_authorizations_owner_insert` (cookie-scoped INSERT). No FOR ALL USING. |
| FR8 | Three SECURITY DEFINER RPCs (all with `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`): `authorize_template(p_template_hash, p_action_class)`, `revoke_template_authorization(p_template_hash, p_reason)`, `anonymise_template_authorizations(p_user_id) RETURNS integer`. |
| FR9 | `isTemplateAuthorized(client, founderId, templateHash): Promise<{ id; sends_used } \| null>` at `apps/web-platform/server/templates/is-template-authorized.ts`. Returns null on: missing row, revoked row, expired (now() ≥ expires_at), quota exhausted (count of action_sends with same template_hash for founder ≥ max_sends). |
| FR10 | At `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:155`, after the existing `isGranted` 403 branch, when `action_class` falls into a tier that requires template authorization (`draft_one_click` initially — registry can opt in others), call `isTemplateAuthorized`. If null, return 403 with discriminated `DenyReason`. |
| FR11 | `DenyReason` type at `apps/web-platform/server/templates/deny-reason.ts`: `'no_scope_grant' \| 'template_unauthorized' \| 'template_quota_exhausted' \| 'template_expired' \| 'template_revoked'`. Send route returns this in error response body. |
| FR12 | `today-card.tsx` renders a deny-explanation note when the send button is disabled, sourced from `DenyReason` + `trust-tier-copy.ts`'s new `revocationReasonCopy` export. Reuse `disabled` + `title=""` pattern from PR-H — no new modal. |
| FR13 | `/dashboard/settings/scope-grants` page gains a "Template authorizations" tab listing the founder's active rows (founder_id = auth.uid() AND revoked_at IS NULL). Per-row "Revoke" button calls `revoke_template_authorization` with `'founder_revoked'`. |
| FR14 | `account-delete.ts:200-251` cascade extended: `anonymise_template_authorizations(p_user_id)` called between line 211 (`anonymise_action_sends`) and line 238 (`anonymise_scope_grants`). FK chain `template_authorizations.grant_id → scope_grants.id ON DELETE RESTRICT` enforces this ordering. |
| FR15 | Revocation reasons enum CHECK: `'founder_revoked' \| 'quota_exhausted' \| 'expired' \| 'dsr_erasure' \| 'regulator_ordered' \| 'vendor_tos_revoked' \| 'policy_violation' \| 'quarantine_retroactive'` — last value reserved (no producer in PR-I; PR-I+1 activates). |
| FR16 | Article 30 register gains PA-16; DPD §2.3 gains subsection (t); Privacy Policy §8.3 extended; AUP gains one line listing `policy_violation` as a revocation outcome. **No T&C amendment.** |

## Technical Requirements

| ID | Requirement |
|---|---|
| TR1 | Migration number is **053** (052 taken by `052_multi_source_dedup.sql`). Up + down migrations both required. |
| TR2 | All new SECURITY DEFINER functions MUST `SET search_path = public, pg_temp` and REVOKE EXECUTE FROM PUBLIC + GRANT to specific role (per `cq-pg-security-definer-search-path-pin-pg-temp`). |
| TR3 | WORM trigger anonymise bypass MUST be verified via a PostgREST-routed integration test (per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`). Test uses real Supabase + service-role JWT; asserts the anonymise RPC succeeds and the row is updated. |
| TR4 | Two-probe predicate ordering test: mock `isGranted` returning null; assert `isTemplateAuthorized` is NOT called (short-circuit). |
| TR5 | Partial UNIQUE race test: parallel `authorize_template` calls for the same (founder, template_hash); assert exactly one row has `revoked_at IS NULL`. |
| TR6 | Exhaustive-enum parity test for `revocation_reason` mirroring `test/server/scope-grants/action-class-exhaustive.test.ts` pattern: literal-union + `satisfies Record<RevocationReason, ...>` + compile-time exhaustive switch + runtime CHECK regex. Locks count at 8. |
| TR7 | DSR cascade ordering integration test in `test/server/account-delete-template-authorizations-cascade.test.ts` (real DB) — asserts anonymise runs in order action_sends → template_authorizations → scope_grants. |
| TR8 | Collision regression test: two distinct (template_id, message_id) pairs produce distinct `template_hash` values. Fails until real registry lands (gates FR1-FR3). |
| TR9 | `messages.template_id` NOT NULL constraint is added AFTER a covering backfill UPDATE in the same migration (per learning `2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md`). |
| TR10 | The `template_authorizations` send-route consumer MUST land in the same PR as mig 053 (per learning `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`). No stub handlers. |
| TR11 | `recipient_id_hash` derivation is verified to be per-tenant salted (verify existing PR-H implementation or flag pre-PR-I prerequisite). |
| TR12 | Sentry mirror on every fail-closed predicate denial (per `cq-silent-fallback-must-mirror-to-sentry`). |

## Acceptance Criteria

1. A founder can authorize a template via `draft_one_click` Send button → row appears in `template_authorizations` with `revoked_at IS NULL` and provisional bounds.
2. A second send for the same template_hash within bounds → succeeds, increments derived send count.
3. A send for the same template_hash AFTER `expires_at` → 403 with `DenyReason='template_expired'`, today-card shows inline note.
4. A send for the same template_hash AFTER quota exhausted (count ≥ max_sends) → 403 with `DenyReason='template_quota_exhausted'`.
5. Founder clicks "Revoke" in `/dashboard/settings/scope-grants` → row updated with `revoked_at=now(), revocation_reason='founder_revoked'`. Next send → 403 with `DenyReason='template_revoked'`.
6. Founder deletes account → `anonymise_template_authorizations` runs between action_sends and scope_grants anonymise; all founder's template_authorization rows have `founder_id` zeroed.
7. CHECK constraint accepts all 8 revocation_reason values + rejects any 9th value.
8. Article 30 register contains PA-16; DPD §2.3(t) present; Privacy §8.3 extension present; AUP updated.
9. Bound-calibration follow-up issue exists and references PR-I as predecessor.
10. PR-I+1 follow-up issue exists for classifier-feedback UI.

## Out of Scope (deferred or rejected)

- Retroactive classifier-feedback UI → PR-I+1 (separate issue).
- `quarantine_retroactive` activation → PR-I+1.
- Bound calibration → calibration follow-up issue.
- LLM template classifier → rejected (ADR-034 code-static).
- T&C amendment → not needed.
- Cross-tenant cohort revocation → CLO confirmed must NOT cascade across founders.

## Risk Notes

| Risk | Likelihood | Mitigation |
|---|---|---|
| `templateHashFor` change breaks in-flight authorizations | Medium | No existing template_authorizations rows to migrate (PR-I introduces the table). `messages.template_id` backfilled to `default_legacy` for historical rows. |
| WORM trigger bypass silently fails under PostgREST | High (known pattern, learning `2026-05-18`) | TR3 integration test gates merge. |
| Partial UNIQUE PostgREST 42P10 on upsert | Medium | All writes go through SECURITY DEFINER RPC (FR8), not raw PostgREST upsert. |
| Cross-tenant template_hash collision (two founders authorize same canonical template) | Low | Row-scoped by founder_id. Hash collision is *expected* across founders; revocation/quota math is per-founder. |
| Provisional bounds 100/30/90/30 turn out wrong post-cohort | Medium | Calibration follow-up issue tunes once ≥1 founder ≥10 sends. Existing rows can be UPDATE'd (revocation enum supports `expired` reissue if needed). |
| `recipient_id_hash` salt regression | Low | TR11 verification. |

## Dependencies

- PR-H (#4077) merged via #4065 — ✅ already satisfied.
- `action_sends.template_hash` + `grant_id` columns present — ✅ verified mig 051 L113/L119.
- ADR-034 code-static registry decision — ✅ applies to template registry as well.

## Sequencing

Single PR (Approach A). Plan-time will decompose into commits matching:

1. Template registry + `messages.template_id` + replace `templateHashFor` (foundation).
2. Mig 053: `template_authorizations` table + indexes + WORM trigger + RPCs.
3. `isTemplateAuthorized` predicate + send-route two-probe wiring + `DenyReason` channel.
4. `today-card.tsx` deny surface + `trust-tier-copy.ts` revocationReasonCopy.
5. `/dashboard/settings/scope-grants` template-authorizations tab.
6. `account-delete.ts` cascade extension.
7. Legal artifacts (PA-16, DPD §2.3(t), Privacy §8.3, AUP).
8. Tests (TR3, TR4, TR5, TR6, TR7, TR8).
9. ADRs to draft (3 per brainstorm).

## User-Brand Impact

**Threshold:** `single-user incident` (carry-forward from #3244, PR-F #3940, PR-G #3984, PR-H #4077; operator re-affirmed 2026-05-21 with "All" framing answer — trust breach + cross-tenant leak + silent send-block all flagged).

**Artifact:** `template_authorizations` row + `isTemplateAuthorized` predicate output.

**Vector:**
- (a) Consent-waiver under Art. 7(3) if bounds aren't enforced — mitigated by FR4 NOT NULL bounds.
- (b) Cross-tenant data leak via shared `recipient_id_hash` in classifier-feedback — deferred to PR-I+1.
- (c) Silent send-blocking via predicate denying without surfaced reason — mitigated by FR11/FR12 `DenyReason` channel.

The `user-impact-reviewer` agent fires conditionally at PR review per the single-user-incident threshold contract.
