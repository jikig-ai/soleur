---
title: PR-I — Template authorizations + per-template registry + Art-17 cascade
date: 2026-05-21
tracking_issue: 4078
parent_issue: 3244
predecessor_pr: 4065
brainstorm: knowledge-base/project/brainstorms/2026-05-21-pr-i-template-authorizations-brainstorm.md
spec: knowledge-base/project/specs/feat-pr-i-template-authorizations-4078/spec.md
draft_pr: 4213
branch: feat-pr-i-template-authorizations-4078
worktree: .worktrees/feat-pr-i-template-authorizations-4078/
followups: [4216, 4217]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
domains_assessed: [Product, Legal, Engineering]
detail_level: A_LOT
plan_review_revision: 2026-05-21-v2
status: draft
---

# PR-I — Template authorizations + per-template registry + Art-17 cascade

Implements the spec at `knowledge-base/project/specs/feat-pr-i-template-authorizations-4078/spec.md`. Single PR (Approach A), atomic ship of the canonical template registry, the `template_authorizations` WORM table, the **single-query two-probe predicate** with **first-send-as-authorization** semantics, founder-initiated revoke surface, Art-17 cascade, and four legal artifacts. Classifier-feedback retroactive UI is pre-wired and deferred to PR-I+1 (#4216). Bound calibration is deferred to #4217.

Closes #4078. Ref #3244.

## Plan Review (v1 → v2) — 5-agent panel changes

Applied 2026-05-21 after DHH + Kieran + code-simplicity + architecture-strategist + spec-flow-analyzer review. Key v1→v2 deltas:

- **First-send-IS-authorization** (spec-flow P0 #12): v1 had `authorize_template` RPC with no writer path; predicate would deny forever for new templates. v2 specifies: send route auto-calls `authorize_template` in the same transaction as `action_sends` INSERT on `template_unauthorized`. Subsequent sends gate on the existing row. Art. 7(3) defense: the Send click IS the explicit consent act.
- **Single-query predicate** (DHH P0 + Kieran P1 + Simplicity + Architecture): one SELECT returns the row + computed flags (`expired`, `quota_exhausted`); TS branches on the columns. Eliminates Phase 4.1 fallback double-query AND the architectural need for a non-partial covering index.
- **Auto-revoke on quota / expired**: predicate-time side effect flips `revoked_at` + `revocation_reason='quota_exhausted'`/`'expired'` so the UI in Phase 7 doesn't display lying rows. Resolves spec-flow P1 #3 + #4.
- **3 ADRs → 1 ADR**: ADR-035 only (template-registry-code-static). ADR-036 (revocation enum) + ADR-037 (two-probe ordering) fold into legal §2.3(t) + Sharp Edges.
- **2 files cut**: `deny-reason.ts` inlined into `is-template-authorized.ts`; `template-hash.ts` merged into `template-registry.ts`.
- **Speculative index cut**: `template_authorizations_expires_idx` removed (add when retention sweep arrives).
- **Sentry mirror on predicate denials cut**: denials are *expected* under Art. 7(3), not silent fallbacks. Pino structured log only.
- **AC7 threshold tightened**: `≥2` → `≥5` (actual count of `session_replication_role` literals in mig 053 is 6+).
- **Phase 8 cascade rationale rewritten**: ON DELETE RESTRICT doesn't fire on UPDATE (anonymise is UPDATE); ordering is semantic (`dsr_erasure` reason set on children before grant nulled).
- **AC5 bypass-grep exclusion** extended to `test/` and `migrations/`.
- **Phase 7 query** joins `scope_grants` and filters `sg.revoked_at IS NULL` (architecture P1).
- **Mig 053 wrapped in `BEGIN;…COMMIT;`** for partial-apply isolation.
- **Revoke RPC failure UX specified** (pessimistic update, revalidatePath, error toast).
- **Review agent roster trimmed** from 11 to 6.

## Overview

PR-H (#4077, merged via #4065 on 2026-05-19) shipped the trust-tier external classes, the `action_sends` WORM signature ledger (mig 051), and the Send/Edit/Discard wiring at `today-card.tsx`. PR-H carried forward two structural gaps:

1. `templateHashFor` at `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:70-80` is a placeholder computing `sha256(action_class:owning_domain:tier)` — collapsing every send for a given (class, domain, tier) into one bucket. No per-template granularity → "authorize THIS template" defense is structurally weak under Art. 7(3).
2. No template-level revocation surface. Founder can revoke a whole-class `scope_grant` but cannot revoke single-template authorization. Art. 7(3) "as easily withdrawable as given" requires template-level revoking when granting is template-level.

PR-I closes both:

- Code-static canonical template registry mirroring `action-class-map.ts` (literal-union + parity test).
- `messages.template_id` column (mig 053) with `default_legacy` backfill.
- Real `getTemplateHash(message)` returning `sha256(TEMPLATE_REGISTRY[template_id].body_template)`.
- `template_authorizations` WORM table parallel to `scope_grants`, NOT NULL bound columns with provisional defaults `100 sends / 30-day soft re-confirm / 90-day hard expiry` (calibration #4217 tunes).
- **Auto-authorize on first send**: send route writes `template_authorizations` row + `action_sends` row in one transaction. Founder click IS the authorization act.
- **Single-query predicate** `isTemplateAuthorized` two-probe (after `isGranted`) with discriminated `DenyReason` channel back to the today-card.
- **Auto-revoke on quota/expired**: predicate-time side effect keeps UI honest.
- Art-17 cascade extension in `account-delete.ts` between `anonymise_action_sends` and `anonymise_scope_grants` (semantic ordering, not FK-driven).
- Article 30 PA-16, DPD §2.3(t), Privacy §8.3 extension, AUP one-liner.

`USER_BRAND_CRITICAL=true` carry-forward from brainstorm Phase 0.1. CPO sign-off required at plan time; `user-impact-reviewer` agent fires at review time.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| ACs reference "bun test" | `package.json scripts.test = "vitest"`; `bunfig.toml:7-12` `pathIgnorePatterns=["**"]` blocks bun-test discovery (#1469 precedent). No `test:integration` script — integration tests use `TENANT_INTEGRATION_TEST=1` env gate (precedent: `action-sends-worm.test.ts:39`). | Phase 9 prescribes `vitest run <path>` + `TENANT_INTEGRATION_TEST=1` env gate for the 4 integration tests. |
| Spec FR6 prescribes WORM trigger anonymise bypass without naming mechanism | Mig 050 (scope_grants) uses `current_user='service_role'` which learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` documents as silently always-false under PostgREST. Mig 051 (action_sends) uses `SET LOCAL session_replication_role='replica'` (line 224) — the working mechanism. | Phase 3 explicitly cites mig 051 mechanism, rejects mig 050 pattern. |
| Spec FR3 "templateHashFor is replaced" implies the function moves | The function is `function templateHashFor(...)` private at `send/route.ts:70-80`. Producer/consumer hash drift possible if not extracted. | Phase 1 extracts into `apps/web-platform/server/templates/template-registry.ts` (merged with the hash function per simplicity review) BEFORE Phase 2 introduces the table. |
| Spec FR13 "scope-grants page gains a Template authorizations tab" | `app/(dashboard)/dashboard/settings/scope-grants/page.tsx` is a server component with single flat list — no tabs. | Phase 7 appends a "Template authorizations" SECTION (not tab) to existing page. |
| (Plan review v2) `authorize_template` RPC is unwired — predicate denies forever for new templates | spec-flow P0: no first-time writer path | **v2 fix:** send route auto-calls `authorize_template` on `template_unauthorized`, in the same transaction as `action_sends` INSERT. First send IS the authorization. |

## Open Code-Review Overlap

3 open `code-review` issues touch files PR-I will modify:

- **#3739** (extract `reportSilentFallbackWithUser` helper) — PR-I adds ~3 new fail-closed sites that call `warnSilentFallback`. **Acknowledge** — use existing helpers; #3739's sweep folds PR-I sites + the 11 existing sites.
- **#3370** (Dev Supabase `_schema_migrations` drifts) — affects mig apply infra, not PR-I content. **Acknowledge.**
- **#3364** (postgres-role ownership guard) — affects mig apply infra. **Acknowledge** — PR-I mig follows REVOKE FROM PUBLIC + GRANT TO authenticated/service_role conventions per mig 051 pattern.

## Domain Review (carry-forward from brainstorm)

**Domains relevant:** Product, Engineering, Legal (mandatory triad at `USER_BRAND_CRITICAL=true`).

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward 2026-05-21).
**Summary:** Single deny-channel via discriminated `DenyReason` prevents "why did this fail?" opacity. Classifier-feedback deferred to PR-I+1 (#4216). Scope-grants page lists active template authorizations with revoke button. **v2 plan-review addition:** first-send-IS-authorization preserves founder mental model (Send IS consent).

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward 2026-05-21).
**Summary:** GO conditional on (a) NOT NULL bound columns with provisional defaults 100/30/90/30 (Art. 7(3) — Phase 2 FR4); (b) revocation enum expanded to 8 reasons for Art. 5(2) attribution (Phase 2 FR15 — over Simplicity's request to cut to 5, the legal-attribution argument is load-bearing); (c) `dsr_erasure` cascade founder-scoped (Phase 8); (d) Article 30 PA-16 + DPD §2.3(t) + Privacy §8.3 + AUP (Phase 10). **v2 plan-review:** first-send-IS-authorization satisfies Art. 7(3) "specific" + "informed" — the Send click on a labeled `draft_one_click` button (with PR-H's typed-confirm context) is informed consent.

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward 2026-05-21).
**Summary:** Schema mirrors `scope_grants` partial UNIQUE + `action_sends` WORM trigger patterns. Two-probe ordering preserved. P0 real per-template registry lifted into PR-I. Mig 053 (052 taken). **v2 plan-review:** single-query predicate eliminates Phase 4 fallback; transactional `BEGIN;…COMMIT;` envelope on mig 053 for partial-apply safety.

### Product/UX Gate

**Tier:** advisory (modifies existing UI; no new pages/modals). Mechanical escalation does not apply.
**Decision:** auto-accepted (pipeline) — copywriter NOT recommended.
**Brainstorm-recommended specialists:** none for PR-I (CPO recommended specialists for PR-I+1).
**Skipped specialists:** none.
**Pencil available:** N/A.

## User-Brand Impact

(Carry-forward verbatim from brainstorm Phase 0.1 — operator selected "All".)

**If this lands broken, the user experiences:** a `template_authorizations` row written without bounds (or bounds bypassed by predicate ordering bug) sends a `draft_one_click` message to a recipient under stale or implicit consent, OR a legitimate `draft_one_click` send silently fails because the predicate denied without surfacing why.

**If this leaks, the user's [data / workflow / money] is exposed via:** (a) consent-waiver under Art. 7(3) when NULL bounds slip through, (b) cross-tenant linkage if `recipient_id_hash` overlap triggers cascade on the wrong founder's authorizations, (c) silent send-blocking with no audit trail telling the founder what to do.

**Brand-survival threshold:** `single-user incident` (carry-forward from #3244; PR-F/PR-G/PR-H; operator re-affirmed 2026-05-21).

CPO sign-off required before `/work`. `user-impact-reviewer` agent fires at PR review.

## Observability

```yaml
liveness_signal:
  what: "predicate denial rate (DenyReason histogram) per route per day"
  cadence: "real-time via pino structured logs; aggregated via Supabase advisor / dashboard"
  alert_target: "pino logs to journald (web-platform PM2 unit); Sentry tags ONLY for errors (kind:template_worm_bypass_failed, kind:dsr_cascade_ordering, kind:template_predicate_timeout, kind:template_authorization_race) — NOT for routine denials"
  configured_in: "apps/web-platform/server/templates/is-template-authorized.ts (denial emit via pino) + apps/web-platform/server/observability.ts (Sentry mirror reserved for actual errors only)"
error_reporting:
  destination: "Sentry via warnSilentFallback (server) for actual errors per cq-silent-fallback-must-mirror-to-sentry. Routine deny paths are pino-only (denials are expected behavior under Art. 7(3), not silent fallbacks)."
  fail_loud: "yes — schema migration apply failure halts; predicate exception aborts request with 500 + Sentry capture; partial-UNIQUE 42P10 from PostgREST upsert routed via SECURITY DEFINER RPC fails fast with named error"
failure_modes:
  - mode: "PostgREST 42P10 on partial UNIQUE upsert"
    detection: "RPC return shape check; TR8 integration asserts exactly one active row after parallel authorize_template calls"
    alert_route: "Sentry kind:template_authorization_race"
  - mode: "WORM trigger reject on legitimate anonymise (session_replication_role bypass fails under PostgREST)"
    detection: "TR3 PostgREST-routed integration test under self-DSAR authenticated grant"
    alert_route: "test failure blocks merge; runtime Sentry kind:template_worm_bypass_failed"
  - mode: "Cascade ordering inversion"
    detection: "TR7 integration test verifies semantic ordering (children carry dsr_erasure reason before grant nulled)"
    alert_route: "Sentry kind:dsr_cascade_ordering"
  - mode: "isTemplateAuthorized exception (DB connection lost, query timeout)"
    detection: "5s request-level timeout wraps the predicate; on exception the send route returns 500 + Sentry capture; **fail-closed against authorization, fail-loud to the user**"
    alert_route: "Sentry kind:template_predicate_timeout"
  - mode: "Hash collision (two distinct canonical templates hash to same value)"
    detection: "TR8 collision regression test pairwise asserts distinct hashes for all registry pairs"
    alert_route: "build-time assertion via parity test; not a runtime concern (registry is code-static)"
logs:
  where: "pino structured log via @/server/observability — `{template_hash, action_class, deny_reason, founder_id_hash}` (founder_id pseudonymized at boundary per PR-H precedent)"
  retention: "standard pino → journald; PII-scrub allowlist enforced"
discoverability_test:
  command: "cd apps/web-platform && vitest run test/server/templates/ test/server/account-delete-template-authorizations-cascade.test.ts"
  expected_output: "all PASS; DenyReason discriminated values asserted; cascade semantic ordering verified"
```

## Files to Create

- `apps/web-platform/server/templates/template-registry.ts` — code-static `TEMPLATE_IDS` literal-union + `TEMPLATE_REGISTRY` Record + `isKnownTemplateId` typeguard + `getTemplateHash(message)` (merged here per Simplicity review — no separate `template-hash.ts`). Mirrors `action-class-map.ts:23-45`. **Tests:** `test/server/templates/template-registry.test.ts` (hash determinism + collision regression).
- `apps/web-platform/server/templates/is-template-authorized.ts` — single-query predicate returning a row with computed flags `{ id, sends_used, expired, quota_exhausted, revoked, expires_at } | null`. Inlines the `DenyReason` type at top of file (per Simplicity review — no separate `deny-reason.ts`).
- `apps/web-platform/supabase/migrations/053_template_authorizations.sql` — full schema + indexes + WORM trigger + 3 SECURITY DEFINER RPCs. **Wrapped in single `BEGIN;…COMMIT;` envelope** per architecture review (partial-apply isolation). Uses mig 051's `session_replication_role='replica'` mechanism throughout.
- `apps/web-platform/supabase/migrations/053_template_authorizations.down.sql` — DROP order: TRIGGERS → RPCs → trigger function → table → ALTER messages DROP COLUMN template_id (reverse of CREATE).
- `apps/web-platform/components/scope-grants/template-authorization-row.tsx` — server component, sibling to existing `scope-grant-row.tsx` (verified at `components/scope-grants/scope-grant-row.tsx` — NOT under `dashboard/`). Per-row "Revoke" button with pessimistic update + `revalidatePath` + error toast + disabled-during-flight (per spec-flow review).
- `apps/web-platform/test/server/templates/template-registry.test.ts` — TR8 collision regression + hash determinism (vitest unit project).
- `apps/web-platform/test/server/templates/is-template-authorized.test.ts` — TR4 two-probe ordering + DenyReason discrimination (vitest unit).
- `apps/web-platform/test/server/template-authorizations-worm.test.ts` — `TENANT_INTEGRATION_TEST=1`-gated. TR3 PostgREST-routed anonymise bypass test (service-role JWT + self-DSAR authenticated grant). TR5 parallel-grant race test.
- `apps/web-platform/test/server/account-delete-template-authorizations-cascade.test.ts` — `TENANT_INTEGRATION_TEST=1`-gated. TR7 cascade semantic ordering verification.
- `apps/web-platform/test/server/scope-grants/revocation-reason-exhaustive.test.ts` — TR6 enum parity test mirroring `action-class-exhaustive.test.ts`.
- `knowledge-base/engineering/architecture/decisions/ADR-035-template-registry-code-static.md` — single ADR (ADR-036 + ADR-037 from v1 folded into legal §2.3(t) + Sharp Edges below, per DHH+Simplicity review).

## Files to Edit

- `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts` — replace inline `templateHashFor` (lines 70-80) with `import { getTemplateHash } from "@/server/templates/template-registry"`; insert `isTemplateAuthorized` two-probe at line 155 after existing `isGranted` 403 branch; on `template_unauthorized` (no existing row), **auto-call `authorize_template` RPC in the same DB transaction as `action_sends` INSERT** (first-send-IS-authorization); on other DenyReasons return 403 with discriminated reason; wrap predicate in 5s timeout + fail-closed exception handler.
- `apps/web-platform/server/action-sends/write-action-send.ts` — change `template_hash` source to `getTemplateHash(message)` from `template-registry.ts`.
- `apps/web-platform/server/account-delete.ts` — insert `anonymise_template_authorizations(p_user_id)` between line 211 (`anonymise_action_sends`) and line 238 (`anonymise_scope_grants`); error handling matches surrounding pattern; inline comment cites SEMANTIC ordering reason (not FK-driven): `dsr_erasure` reason must be set on child rows before the grant's `user_id` is nulled or audit-trail breaks.
- `apps/web-platform/lib/messages/trust-tier-copy.ts` — append `REVOCATION_REASON_COPY` sibling export (8 keys, each `{ label, description }`).
- `apps/web-platform/components/dashboard/today-card.tsx` — render deny note when send is disabled; sourced from response body `error.deny_reason` + DenyReason copy map. Reuse `disabled` + `title=""` pattern. Per-DenyReason copy strategy (resolves spec-flow review deep-link gaps):
  - `no_scope_grant` → "You need a scope grant first. Visit Settings → Scope grants."
  - `template_unauthorized` → (unreachable in v2 — first send auto-authorizes; if seen, indicates predicate exception)
  - `template_revoked` → "This template was revoked. Click Send again to re-authorize."
  - `template_expired` → "This template authorization expired (90-day limit). Click Send again to re-authorize."
  - `template_quota_exhausted` → "You've sent 100 messages with this template. Click Send again to re-authorize for another 100."
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` — append "Template authorizations" section below existing scope-grants list. Query: `template_authorizations` rows WHERE `founder_id = auth.uid()` AND `revoked_at IS NULL` **AND** `EXISTS (SELECT 1 FROM scope_grants sg WHERE sg.id = template_authorizations.grant_id AND sg.revoked_at IS NULL)` (architecture-strategist P1 — exclude template_auths under revoked scope_grants). Empty-state copy: static "When you 1-click send a draft, the template will be authorized for up to 100 sends over 90 days."
- `apps/web-platform/server/dsar-export.ts` — add `template_authorizations` to `DSAR_TABLE_ALLOWLIST`.
- `apps/web-platform/docs/legal/data-protection-disclosure.md` — append §2.3(t) "Template-authorization ledger". Body includes the un-revocability + Art. 5(2) attribution rationale for the 8-value enum (replaces former ADR-036).
- `apps/web-platform/docs/legal/privacy-policy.md` — extend §8.3 with template-level authorization + forward-reference to retroactive-reclassification (PR-I+1).
- `apps/web-platform/docs/legal/acceptable-use-policy.md` — one-line addition listing `policy_violation` as a revocation outcome.
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — Eleventy mirror per learning `2026-03-20-eleventy-mirror-dual-date-locations.md`; update hero `<p>` Last-Updated + body `**Last Updated:**`.
- `plugins/soleur/docs/pages/legal/privacy-policy.md` — Eleventy mirror.
- `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` — Eleventy mirror.
- `knowledge-base/legal/article-30-register.md` — append PA-16 mirroring PA-15 pattern.

## Implementation Phases

Phase ordering follows `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`.

### Phase 0 — Preconditions Verification

```bash
# T0.1 — Confirm test runner.
jq -r '.scripts.test, .scripts["test:ci"]' apps/web-platform/package.json
# Expected: "vitest" and "vitest run"

# T0.2 — Confirm bunfig.toml blocks bun test discovery.
grep -A2 '\[test\]' apps/web-platform/bunfig.toml
# Expected: pathIgnorePatterns = ["**"]

# T0.3 — Confirm next-free migration number.
ls apps/web-platform/supabase/migrations/ | sort | tail -5
# Expected: highest is 052_*.sql

# T0.4 — Confirm anonymise_action_sends bypass mechanism.
grep -n 'SET LOCAL session_replication_role' apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql
# Expected: line 224
```

If any check fails, STOP.

### Phase 1 — Template Registry + Hash Extract + `messages.template_id` Backfill

**Goal:** introduce registry + extract `templateHashFor` BEFORE Phase 2 introduces the table consumer.

**Tasks:**

1. Create `apps/web-platform/server/templates/template-registry.ts`:
   - `export const TEMPLATE_IDS = ['default_legacy'] as const;`
   - `export type TemplateId = typeof TEMPLATE_IDS[number];`
   - `export const TEMPLATE_REGISTRY: Record<TemplateId, { id; body_template; action_class; owning_domain }> = { default_legacy: { ... } } satisfies Record<TemplateId, ...>;`
   - `export function isKnownTemplateId(value: string): value is TemplateId { return TEMPLATE_IDS.includes(value as TemplateId); }`
   - `export function getTemplateHash(message: { template_id: TemplateId | string }): string` returning `sha256(TEMPLATE_REGISTRY[template_id ?? 'default_legacy'].body_template)`. For unknown template_id, falls through to `default_legacy` and emits `warnSilentFallback({ kind: 'template_hash_unknown_template_id' })`.
   - **No `canonicalize` abstraction** (per DHH review — add when templates have versioning).

2. Add `messages.template_id` via mig 053 part A (column add + backfill + NOT NULL). Order per learning `2026-04-17`: ADD nullable → UPDATE → SET NOT NULL → ADD CHECK.
   ```sql
   ALTER TABLE public.messages ADD COLUMN template_id text;
   UPDATE public.messages SET template_id = 'default_legacy' WHERE template_id IS NULL;
   ALTER TABLE public.messages ALTER COLUMN template_id SET NOT NULL;
   ALTER TABLE public.messages ADD CONSTRAINT messages_template_id_check
     CHECK (template_id ~ '^[a-z][a-z0-9_]*$' AND length(template_id) BETWEEN 1 AND 64);
   ```

3. Replace inline `templateHashFor` at `send/route.ts:70-80` with `import { getTemplateHash } from "@/server/templates/template-registry"`. Replace inline call at line 244 with `getTemplateHash(message)`. Verify `message` SELECT projection at line 111-116 includes `template_id`; add if missing.

4. Update `write-action-send.ts` to compute `template_hash` via `getTemplateHash(message)` from shared module.

**Files:** create `template-registry.ts`; edit `send/route.ts`, `write-action-send.ts`; mig 053 part A.

### Phase 2 — `template_authorizations` Table + WORM Trigger + Indexes (mig 053 part B)

All within the mig 053 `BEGIN;…COMMIT;` envelope (architecture review).

1. `CREATE TABLE public.template_authorizations` with columns per spec FR4 (id, founder_id, template_hash, action_class, authorized_at, expires_at NOT NULL DEFAULT now()+90d, soft_reconfirm_at NOT NULL DEFAULT now()+30d, max_sends NOT NULL DEFAULT 100, revoked_at NULL, revocation_reason NULL, grant_id FK → scope_grants(id) ON DELETE RESTRICT, created_at).

2. Constraint pair: `CHECK ((revoked_at IS NULL) = (revocation_reason IS NULL))`.

3. Indexes:
   - `CREATE UNIQUE INDEX template_authorizations_active_unique ON public.template_authorizations (founder_id, template_hash) WHERE revoked_at IS NULL;`
   - `CREATE INDEX template_authorizations_founder_revoked_idx ON public.template_authorizations (founder_id, revoked_at);`
   - **NO** `template_authorizations_expires_idx` (cut per Simplicity — speculative; add when retention sweep arrives).

4. WORM trigger `template_authorizations_no_mutate()`:
   - Pure reject UPDATE/DELETE except when `current_setting('session_replication_role') = 'replica'`. **DO NOT** use `current_user='service_role'` (learning 2026-05-18 — silently always-false under PostgREST).
   - SECURITY DEFINER, `SET search_path = public, pg_temp`.
   - REVOKE ALL FROM PUBLIC, anon, authenticated, service_role.

5. RLS:
   - `ENABLE ROW LEVEL SECURITY;`
   - `template_authorizations_owner_select` (FOR SELECT TO authenticated USING founder_id = auth.uid()).
   - `template_authorizations_owner_insert` (FOR INSERT TO authenticated WITH CHECK founder_id = auth.uid()).
   - No `FOR UPDATE` or `FOR DELETE` policies — writes go through SECURITY DEFINER RPCs.

### Phase 3 — SECURITY DEFINER RPCs (mig 053 part C)

All within the same `BEGIN;…COMMIT;`. All `SECURITY DEFINER`, all `SET search_path = public, pg_temp`. All use `SET LOCAL session_replication_role='replica'` for the WORM bypass (NOT `current_user`).

1. **`authorize_template(p_template_hash text, p_action_class text, p_grant_id uuid) RETURNS uuid`**
   - Validates inputs (template_hash length 1-128, action_class regex match).
   - Inserts row with NOT NULL bound defaults.
   - Returns new row's `id`.
   - GRANT EXECUTE TO authenticated; REVOKE FROM PUBLIC, anon, service_role.
   - On 23505 (partial UNIQUE conflict — concurrent grant), return the existing active row's id (idempotent first-writer-wins per learning `2026-05-03-postgrest-on-conflict-cannot-infer-partial-index.md`).

2. **`revoke_template_authorization(p_template_hash text, p_reason text) RETURNS integer`**
   - Validates `p_reason IN (8-value enum)`.
   - **Bypass justification (Kieran P0):** founder owns the row via RLS, but the WORM trigger blocks ALL UPDATEs including founder-initiated revoke. Inline SQL comment: `-- WORM trigger blocks all UPDATEs including founder-initiated revoke; bypass is required.`
   - `SET LOCAL session_replication_role = 'replica';`
   - `UPDATE public.template_authorizations SET revoked_at = now(), revocation_reason = p_reason WHERE founder_id = auth.uid() AND template_hash = p_template_hash AND revoked_at IS NULL;`
   - `RESET session_replication_role;`
   - Returns ROW_COUNT.

3. **`anonymise_template_authorizations(p_user_id uuid) RETURNS integer`**
   - Authorization: rejects unless `auth.uid() IS NULL && current_user IN ('service_role','postgres')` OR `auth.uid() = p_user_id` (self-DSAR) — mirror mig 051:236-243.
   - `SET LOCAL session_replication_role = 'replica';`
   - `UPDATE public.template_authorizations SET founder_id = NULL, revoked_at = COALESCE(revoked_at, now()), revocation_reason = COALESCE(revocation_reason, 'dsr_erasure') WHERE founder_id = p_user_id;`
   - `RESET session_replication_role;`
   - GRANT TO authenticated, service_role.

### Phase 4 — `isTemplateAuthorized` Predicate + First-Send-IS-Authorization

**Goal (v2 plan-review architectural pivot):** single-query predicate + auto-authorize on first send + auto-revoke on quota/expired.

1. Create `apps/web-platform/server/templates/is-template-authorized.ts`. Top of file inlines the `DenyReason` type (per Simplicity review — no separate file):
   ```ts
   export type DenyReason =
     | 'no_scope_grant'
     | 'template_unauthorized'
     | 'template_quota_exhausted'
     | 'template_expired'
     | 'template_revoked';

   export type PredicateResult =
     | { status: 'authorized'; rowId: string; sendsUsed: number }
     | { status: 'first_send'; grantId: string }  // no row → caller must auto-authorize
     | { status: 'denied'; reason: Exclude<DenyReason, 'no_scope_grant'> };

   export async function isTemplateAuthorized(
     client: SupabaseClient,
     founderId: string,
     templateHash: string,
     grantId: string,
   ): Promise<PredicateResult>
   ```
   Single SELECT returns the most recent row by (founder_id, template_hash) regardless of revoked/expired state, plus a JOIN to count of `action_sends` with the same template_hash for sends_used. TS branches:
   - No row → `{ status: 'first_send', grantId }`.
   - Row exists with `revoked_at IS NOT NULL` → `{ status: 'denied', reason: 'template_revoked' }`.
   - Row exists with `expires_at <= now()` → trigger auto-revoke (Phase 4.3) → `{ status: 'denied', reason: 'template_expired' }`.
   - Row exists with `sends_used >= max_sends` → trigger auto-revoke (Phase 4.3) → `{ status: 'denied', reason: 'template_quota_exhausted' }`.
   - Otherwise → `{ status: 'authorized', rowId, sendsUsed }`.

   **Single query, no fallback. Common path (authorized) AND deny paths each cost one SELECT + one JOIN.**

2. **Fail-closed on exception** (spec-flow P0): wrap the SELECT in try/catch. On any exception, throw a typed `PredicateException` that the send route catches as 500 + Sentry capture (kind:template_predicate_timeout). Caller MUST NOT treat exception as "authorized" — fail-closed against authorization, fail-loud to user.

3. **Auto-revoke side effect** (spec-flow P1 #3 + #4): when the predicate detects an expired or quota-exhausted row that has `revoked_at IS NULL`, fire `revoke_template_authorization(template_hash, 'expired' | 'quota_exhausted')` in a background-safe call. Best-effort: if revoke fails, log via pino but still return the denial. Subsequent visits to `/dashboard/settings/scope-grants` won't show the lying row.

4. Edit `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:155`:
   - After existing `isGranted` 403 branch (line 150-155), and BEFORE the tier switch (line 163):
   - Only for `requires_template_auth` action_classes (currently: any class where `tier === 'draft_one_click'`):
   - Call `isTemplateAuthorized(client, user.id, getTemplateHash(message), grant.id)`.
   - On `status === 'denied'` → 403 with `{ error: { code: 'template_not_authorized', deny_reason } }`.
   - On `status === 'first_send'` → call `authorize_template(template_hash, message.action_class, grant.id)` RPC; on success, proceed to write `action_sends` row in the same Supabase transaction. **First send IS the authorization act.**
   - On `status === 'authorized'` → proceed directly.
   - Wrap all of the above in 5s `Promise.race` timeout; on timeout → 500 + Sentry capture.

5. Emit pino structured log on every denial: `{ template_hash, action_class, deny_reason, founder_id_hash }`. **No Sentry mirror on routine denials** (per Simplicity — denials are expected behavior, not silent fallbacks; Sentry tags reserved for actual errors).

**Files:** create `is-template-authorized.ts`; edit `send/route.ts`.

### Phase 5 — Today-Card Deny Surface + Revocation Reason Copy

1. Edit `apps/web-platform/lib/messages/trust-tier-copy.ts` — append `REVOCATION_REASON_COPY: Record<RevocationReason, { label: string; description: string }>`. 8 keys with concise founder-facing copy.

2. Edit `apps/web-platform/components/dashboard/today-card.tsx`:
   - On 403 response with `error.deny_reason`, render inline note below disabled button. Source from per-DenyReason copy strategy in Files to Edit above.
   - Reuse `disabled` + `title=""` pattern; no new modal.
   - **Sequential deny note** (spec-flow P2): predicates short-circuit; founder sees one DenyReason at a time. If `no_scope_grant` resolves to `template_unauthorized` on next try, that's two sequential clicks, not stacked errors.

### Phase 6 — DSAR Allowlist Extension

Edit `apps/web-platform/server/dsar-export.ts` — add `'template_authorizations'` to `DSAR_TABLE_ALLOWLIST`. Confirm column allowlist (if per-table) excludes hash-derived columns without founder-relevant meaning.

### Phase 7 — Scope-Grants Settings Section + Revoke Surface

1. Create `apps/web-platform/components/scope-grants/template-authorization-row.tsx`:
   - Server component receiving `{ id, template_hash, action_class, authorized_at, expires_at, soft_reconfirm_at, max_sends, sends_used }` props.
   - Renders row: template label (action_class + truncated hash), authorization date, expiry date, sends remaining.
   - "Revoke" button = server action calling `revoke_template_authorization(template_hash, 'founder_revoked')`.
   - **Failure UX (spec-flow P1):** pessimistic update (button disabled during in-flight), `revalidatePath('/dashboard/settings/scope-grants')` on success, error toast with retry on failure.

2. Edit `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`:
   - Append new `<section>` heading "Template authorizations" below existing scope-grants list.
   - Query (architecture review P1 — JOIN scope_grants to exclude template_auths under revoked grants):
     ```sql
     SELECT ta.*
       FROM template_authorizations ta
       JOIN scope_grants sg ON sg.id = ta.grant_id
      WHERE ta.founder_id = auth.uid()
        AND ta.revoked_at IS NULL
        AND sg.revoked_at IS NULL
      ORDER BY ta.authorized_at DESC;
     ```
   - Empty-state copy (spec-flow P2 — static): "No template authorizations yet. When you 1-click send a draft, the template will be authorized for up to 100 sends over 90 days."

### Phase 8 — Account-Delete Cascade Extension (semantic ordering, NOT FK-driven)

Edit `apps/web-platform/server/account-delete.ts:200-251`:
- Between line 211 (`anonymise_action_sends`) and line 238 (`anonymise_scope_grants`), insert `anonymise_template_authorizations(p_user_id)` call.
- Error handling matches surrounding `try/catch`; on failure return `{ status: 'failed', step: 'template_authorizations' }`.

**Cascade rationale (Kieran P1 fix):** ordering is **semantic, not FK-driven**. `anonymise_*` RPCs perform UPDATE (not DELETE), so `ON DELETE RESTRICT` does not fire on UPDATE. The required ordering is: `template_authorizations.revocation_reason = 'dsr_erasure'` MUST be set on child rows BEFORE the parent `scope_grant`'s `user_id` is nulled — otherwise the audit trail attribution breaks (Art. 5(2)). The inline comment in `account-delete.ts` must cite this reason verbatim, NOT the old "FK RESTRICT requires this ordering" comment.

### Phase 9 — Tests

All tests use vitest. Integration tests gated by `TENANT_INTEGRATION_TEST=1`.

1. **`test/server/templates/template-registry.test.ts`** (TR8 collision regression):
   - Pairwise distinct hashes for all `(a, b)` where `a !== b` in `TEMPLATE_IDS`.
   - Deterministic output for a given `template_id`.
   - `default_legacy` fallback on unknown template_id.
   - Vitest unit project.

2. **`test/server/templates/is-template-authorized.test.ts`** (TR4 + exception path):
   - Mock `isGranted` → null; assert `isTemplateAuthorized` NOT called.
   - Mock predicate returning each `PredicateResult` variant; assert send-route branches correctly.
   - Mock DB exception; assert predicate throws + send route returns 500 + Sentry capture (fail-closed).
   - First-send-IS-authorization test: predicate returns `first_send`; assert `authorize_template` RPC called; assert `action_sends` row written.
   - Vitest unit project.

3. **`test/server/template-authorizations-worm.test.ts`** (`TENANT_INTEGRATION_TEST=1`):
   - **TR3**: PostgREST-routed integration — call `anonymise_template_authorizations` via service-role JWT AND via authenticated JWT (self-DSAR); assert WORM bypass succeeds in BOTH paths.
   - **TR5**: parallel `authorize_template` calls for same (founder, template_hash); assert exactly one row has `revoked_at IS NULL`.
   - Auto-revoke on quota/expired: insert row with `sends_used = max_sends - 1`, write one `action_sends` row to push count over limit, call predicate, assert `revoked_at` is set after.

4. **`test/server/account-delete-template-authorizations-cascade.test.ts`** (`TENANT_INTEGRATION_TEST=1`):
   - **TR7**: insert scope_grant + template_authorization + action_send for synthetic founder; call `account-delete.ts`; assert ordering `action_sends → template_authorizations → scope_grants` AND assert `dsr_erasure` reason landed on template_authorization BEFORE grant was nulled (semantic check, not FK check).

5. **`test/server/scope-grants/revocation-reason-exhaustive.test.ts`** (TR6):
   - Mirror `action-class-exhaustive.test.ts` structure: `satisfies Record<RevocationReason, ...>` parity gate, compile-time `_exhaustive: never` switch, runtime CHECK regex, count locked at 8.

6. **Update `test/api/dashboard/today/send-route.test.ts`**: add cases for first-send-IS-authorization happy path + each DenyReason 403 path.

### Phase 10 — Legal Artifacts + ADR-035 (combined per Simplicity)

1. **Article 30 register** (`knowledge-base/legal/article-30-register.md`): append PA-16 mirroring PA-15.
2. **DPD §2.3(t)** (`apps/web-platform/docs/legal/data-protection-disclosure.md`): "Template-authorization ledger". Include the 8-value enum un-revocability + Art. 5(2) attribution rationale (replaces former ADR-036).
3. **Privacy §8.3** (`apps/web-platform/docs/legal/privacy-policy.md`): extend with template-level authorization + forward-reference to PR-I+1.
4. **AUP** (`apps/web-platform/docs/legal/acceptable-use-policy.md`): one-line `policy_violation` revocation outcome.
5. **Eleventy mirror dual-write** per `2026-03-20-eleventy-mirror-dual-date-locations.md`: same 3 changes to `plugins/soleur/docs/pages/legal/*.md`. Update hero `<p>` Last-Updated + body `**Last Updated:**`.
6. **NO T&C amendment**.
7. **ADR-035** (`knowledge-base/engineering/architecture/decisions/ADR-035-template-registry-code-static.md`): single ADR for the code-static template registry pattern (mirror of ADR-034 lineage). Two-probe ordering rationale and 8-value enum rationale fold into legal §2.3(t) + this plan's Sharp Edges (former ADR-036/ADR-037 cut per DHH+Simplicity).

### Phase 11 — PR Body + Post-merge Automation

1. PR body: summary citing brainstorm + spec + plan-review v2 deltas; semver:minor; `Closes #4078`; "Splits #4216 and #4217 will follow"; link to ADR-035.

2. **Pre-merge acceptance criteria** (see Acceptance Criteria section below).

3. **Post-merge automation** (NO operator-only steps per `2026-05-15-operator-only-step-canonical-list.md`):
   - Mig 053 applies on prd via `apply-web-platform-migrations.yml` (auto on merge).
   - `gh issue close 4078` via `Closes #4078`.
   - Sentry watch for `kind:template_*` tags via existing `/soleur:ship` post-merge verification.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** All vitest unit + component tests green: `cd apps/web-platform && vitest run` exits 0.
- [ ] **AC2** Integration tests green: `cd apps/web-platform && TENANT_INTEGRATION_TEST=1 vitest run test/server/template-authorizations-worm.test.ts test/server/account-delete-template-authorizations-cascade.test.ts test/server/templates/` exits 0.
- [ ] **AC3** `bun run typecheck` and `next lint` both exit 0.
- [ ] **AC4** Mig 053 applies cleanly on dev: `doppler run -p soleur -c dev -- bun run db:migrate` exits 0; `psql ... -c "\d template_authorizations"` shows all columns + indexes.
- [ ] **AC5** Predicate centralization two-grep (helper-routed + bypass):
  - Helper-routed: `rg "isTemplateAuthorized\(" apps/web-platform/` returns calls only from `app/api/dashboard/today/[id]/send/route.ts` and the predicate's own test file.
  - Bypass: `rg "from\\.*template_authorizations" apps/web-platform/server/ apps/web-platform/app/api/ | grep -v is-template-authorized | grep -v dsar-export | grep -v account-delete | grep -v scope-grants/page.tsx | grep -v test/ | grep -v migrations/` returns ZERO.
- [ ] **AC6** Revocation reason enum cardinality: `psql -c "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname LIKE '%template_authorizations%revocation_reason%';"` returns a CHECK with exactly 8 quoted values. Implementation-invariant against TS form choice (union vs const enum).
- [ ] **AC7** WORM mechanism check: `grep -c 'session_replication_role' apps/web-platform/supabase/migrations/053_template_authorizations.sql` returns `≥5` (trigger body + 2 `SET LOCAL` + 2 `RESET` per revoke + anonymise RPCs; mig has ~6 literal occurrences). `grep -c "current_user = 'service_role'" apps/web-platform/supabase/migrations/053_template_authorizations.sql` returns `0`.
- [ ] **AC8** Eleventy mirror dual-write (`2026-03-20-eleventy-mirror-dual-date-locations.md`): for each of 3 mirrored legal docs, both `apps/web-platform/docs/legal/` AND `plugins/soleur/docs/pages/legal/` contain `Last Updated[: *]+May 21, 2026` (tolerant regex matches both `Last Updated May 21, 2026` and `**Last Updated:** May 21, 2026`).
- [ ] **AC9** PR body contains `Closes #4078` (NOT `Ref #4078`); title does NOT title-side Closes (per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **AC10** Multi-agent review at single-user-incident threshold completes — 6 agents (architecture-strategist, data-migration-expert, security-sentinel, gdpr-gate cross-reconcile, user-impact-reviewer, code-simplicity-reviewer). Trimmed from v1's 11 per DHH review.
- [ ] **AC11** CPO sign-off comment on PR.
- [ ] **AC12** First-send-IS-authorization integration test passes (test/server/template-authorizations-worm.test.ts asserts: synthetic founder with active scope_grant + no template_auth → first 1-click Send writes BOTH `template_authorizations` row AND `action_sends` row in same transaction → second 1-click Send increments sends_used).

### Post-merge (operator-NO-ops)

- [ ] **AC13** Mig 053 applied on prd via `apply-web-platform-migrations.yml`.
- [ ] **AC14** Issue #4078 auto-closes via `Closes #4078` link.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `session_replication_role='replica'` bypass fails under PostgREST | Medium (recurring per learning 2026-05-18) | TR3 integration test gates merge by exercising the bypass under both service-role AND self-DSAR paths. Fix-forward: fall back to a row-state ("anonymising") flag column. |
| Provisional bounds 100/30/90/30 turn out wrong post-cohort | Medium | Calibration follow-up #4217 tunes. Existing rows UPDATE-able. |
| Hash collision via canonicalize misconfiguration | Low | TR8 collision regression test asserts pairwise distinct hashes. |
| `messages.template_id` backfill on a large table | Low | All rows → `default_legacy`. Fast at current scale; future partial index if table grows >>1M rows. |
| Cross-tenant `recipient_id_hash` overlap in cascade | Low | Cascade scoped to `founder_id` only (Phase 8). Confirmed founder-scoped semantics. |
| `templateHashFor` rename breaks in-flight `action_sends` writes during deploy | Low | Both old and new producers compute same hash for `default_legacy`; backfill ensures every existing `messages` row has valid template_id. |
| Predicate-vs-write TOCTOU race (architecture P2) | Low | Pre-existing PR-H risk; not regressed. Acknowledged in plan; capture in ADR-035 risks section. Worst case: 1-request RTT window. |
| Auto-revoke side effect adds latency to predicate | Low | Auto-revoke runs async-best-effort; if revoke RPC fails, denial still returned. Background. |
| Mig 053 partial-apply between CREATE TABLE and CREATE INDEX | Low | Wrapped in `BEGIN;…COMMIT;` envelope per architecture review. Down migration drops in reverse order. |
| Cap coupling with PR-H (learning 2026-05-06) | Low | PR-H ships no cap surface to align with (action_sends has no time-bound expiry); PR-I introduces its own. |
| Sentry helper consolidation #3739 interference | Low | PR-I uses helpers as-shipped; #3739 sweeps later. |
| First-send transaction failure mid-flow (authorize_template succeeds, action_sends INSERT fails) | Low | Single Supabase transaction wraps both writes; if action_sends INSERT fails, template_authorizations INSERT also rolls back. No orphaned row. |

## Dependencies

- PR-H (#4077) merged via #4065 — ✅
- `action_sends.template_hash` + `grant_id` (mig 051 L113/L119) — ✅
- ADR-034 code-static registry decision — ✅
- `compliance/critical` label — ✅

## Sharp Edges

- **`## User-Brand Impact` section MUST persist through implementation phases** (deepen-plan Phase 4.6 halts on empty section).
- **First-send-IS-authorization rationale (former ADR-037 content):** the predicate-and-write sequence at `send/route.ts:155` IS the authorization act. Founder click on a labeled `draft_one_click` button (with PR-H typed-confirm context) constitutes Art. 7(3) informed consent. Subsequent gating by `isTemplateAuthorized` enforces bounds; UI-driven revoke at scope-grants page provides "as easily withdrawable as given". This sequencing was reviewed by spec-flow-analyzer at plan-review v2 and is the load-bearing fix.
- **8-value revocation_reason enum is deliberate over-provision (former ADR-036 content):** Simplicity review wanted 5; brainstorm CLO + this plan keep 8 (`founder_revoked`, `quota_exhausted`, `expired`, `dsr_erasure`, `regulator_ordered`, `vendor_tos_revoked`, `policy_violation`, `quarantine_retroactive`). Each value distinguishes un-revocability + Art. 5(2) attribution. Cheaper to add at mig 053 than ALTER later. Three values (`regulator_ordered`, `vendor_tos_revoked`, `policy_violation`) have no v1 producer; `quarantine_retroactive` reserved for PR-I+1 (#4216).
- **Two-probe ordering rationale (former ADR-037 content):** `isGranted` runs FIRST at `send/route.ts:155`. Three reasons: (i) preserves existing fail-closed trust model; (ii) some tiers (`auto_with_digest`, `approve_every_time`) don't carry template authorizations, short-circuit saves the second probe; (iii) `template_quarantined` (PR-I+1) is a child of `scope_grant` revocation semantically.
- **WORM bypass mechanism is `SET LOCAL session_replication_role='replica'`** (mig 051 precedent), NOT `current_user='service_role'` (mig 050 broken per learning `2026-05-18`).
- **Auto-revoke on quota/expired is a predicate-time side effect.** If the implementer worries about "read query writing," document this is best-effort: failure to write the revoke row still returns the correct DenyReason; UI stays honest on the next read. Not a transactional invariant.
- **Mig 053 down migration DROP order:** TRIGGER → trigger function → 3 RPCs → table → ALTER messages DROP COLUMN template_id. Reverse of CREATE.
- **AC5 bypass-grep exclusion list:** test/, migrations/, is-template-authorized, dsar-export, account-delete, scope-grants/page.tsx — these are legitimate readers. New legitimate readers must update the AC.
- **AC6 uses SQL CHECK constraint cardinality**, NOT TS source grep — implementation-invariant against union-vs-enum form choice.
- **Phase 0 preconditions T0.1-T0.4 are mandatory at `/work` Phase 0**; do not assume they passed at plan-write time.
- **`TENANT_INTEGRATION_TEST=1` is a STRING compare** (`process.env.TENANT_INTEGRATION_TEST === "1"`). Setting to `"true"` or `"yes"` is silently false.
- **`components/scope-grants/` is the existing directory** (verified by repo-research). NOT `components/dashboard/scope-grants/`. DHH + Kieran plan-review v1 misread this; the path in the plan matches the codebase.
- **Eleventy mirror requires updating BOTH hero `<p>` Last-Updated line AND body `**Last Updated:**` line** in each of 3 mirrored docs.
- For any `gh issue create` follow-up command, use `--label compliance/critical` (no `single-user-incident` label exists).
- The `dsr_erasure` cascade is **semantic ordering** (must set reason on children before nulling parent grant), NOT FK-driven (anonymise UPDATE doesn't trigger ON DELETE RESTRICT). The inline `account-delete.ts` comment must say this; do not regress to the old FK-driven rationale.

## Resume Prompt (after plan-review v2 apply)

```text
/soleur:work knowledge-base/project/plans/2026-05-21-feat-pr-i-template-authorizations-plan.md. Branch: feat-pr-i-template-authorizations-4078. Worktree: .worktrees/feat-pr-i-template-authorizations-4078/. Issue: #4078. PR: #4213. Plan-review v2 applied (11 cuts + 11 fixes + first-send-IS-authorization pivot). Implementation next.
```
