---
title: PR-I — Template authorizations tasks
date: 2026-05-21
tracking_issue: 4078
plan: knowledge-base/project/plans/2026-05-21-feat-pr-i-template-authorizations-plan.md
spec: knowledge-base/project/specs/feat-pr-i-template-authorizations-4078/spec.md
branch: feat-pr-i-template-authorizations-4078
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan_review_revision: 2026-05-21-v2
---

# PR-I tasks

## Phase 0 — Preconditions Verification

- [x] 0.1 Run `jq -r '.scripts.test, .scripts["test:ci"]' apps/web-platform/package.json` → expect `"vitest"` and `"vitest run"`.
- [x] 0.2 Run `grep -A2 '\[test\]' apps/web-platform/bunfig.toml` → expect `pathIgnorePatterns = ["**"]`.
- [x] 0.3 Run `ls apps/web-platform/supabase/migrations/ | sort | tail -5` → confirm highest is `052_*.sql`.
- [x] 0.4 Run `grep -n 'SET LOCAL session_replication_role' apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql` → confirm line 224.
- [x] 0.5 STOP and resolve if any check fails.

## Phase 1 — Template Registry + Hash + `messages.template_id`

- [x] 1.1 Create `apps/web-platform/server/templates/template-registry.ts` with `TEMPLATE_IDS = ['default_legacy'] as const`, `TEMPLATE_REGISTRY` Record, `isKnownTemplateId` typeguard, and `getTemplateHash(message)` (merged from former template-hash.ts per v2 plan-review).
- [x] 1.2 Write `apps/web-platform/test/server/templates/template-registry.test.ts` — hash determinism + pairwise collision regression (TR8).
- [x] 1.3 In mig 053 (NO outer BEGIN/COMMIT per mig 051 Kieran P1-4 precedent), Part A — `ALTER TABLE public.messages ADD COLUMN template_id text` → `UPDATE … SET template_id = 'default_legacy' WHERE template_id IS NULL` → `ALTER TABLE … ALTER COLUMN template_id SET NOT NULL` → `ADD CONSTRAINT messages_template_id_check`.
- [x] 1.4 Edit `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts:70-80` — delete inline `templateHashFor`; import `getTemplateHash`.
- [x] 1.5 Edit `send/route.ts:111-116` SELECT projection to include `template_id`.
- [x] 1.6 Edit `send/route.ts:244` — replace inline call with `getTemplateHash(message)`.
- [x] 1.7 Edit `apps/web-platform/server/action-sends/write-action-send.ts` — `template_hash` via shared `getTemplateHash`.

## Phase 2 — `template_authorizations` Table + WORM Trigger + Indexes

- [x] 2.1 Continue mig 053 Part B (NO outer BEGIN/COMMIT — Supabase runner wraps; mig 051 precedent).
- [x] 2.2 `CREATE TABLE public.template_authorizations` with columns per plan FR4: `id`, `founder_id`, `template_hash`, `action_class`, `authorized_at DEFAULT now()`, `expires_at NOT NULL DEFAULT now()+90d`, `soft_reconfirm_at NOT NULL DEFAULT now()+30d`, `max_sends NOT NULL DEFAULT 100`, `revoked_at NULL`, `revocation_reason NULL`, `grant_id REFERENCES scope_grants(id) ON DELETE RESTRICT`, `created_at`.
- [x] 2.3 Add `CHECK ((revoked_at IS NULL) = (revocation_reason IS NULL))`.
- [x] 2.4 Add `CHECK (revocation_reason IS NULL OR revocation_reason IN ('founder_revoked','quota_exhausted','expired','dsr_erasure','regulator_ordered','vendor_tos_revoked','policy_violation','quarantine_retroactive'))` — 8 values.
- [x] 2.5 Create `template_authorizations_active_unique` partial UNIQUE on `(founder_id, template_hash) WHERE revoked_at IS NULL`.
- [x] 2.6 Create `template_authorizations_founder_revoked_idx` on `(founder_id, revoked_at)`.
- [x] 2.7 Create WORM trigger `template_authorizations_no_mutate()` — pure-reject UPDATE/DELETE except when `current_setting('session_replication_role') = 'replica'`. SECURITY DEFINER, `SET search_path = public, pg_temp`. REVOKE ALL FROM PUBLIC/anon/authenticated/service_role.
- [x] 2.8 `ALTER TABLE … ENABLE ROW LEVEL SECURITY`.
- [x] 2.9 `CREATE POLICY template_authorizations_owner_select` (SELECT TO authenticated USING `founder_id = auth.uid()`).
- [x] 2.10 `CREATE POLICY template_authorizations_owner_insert` (INSERT TO authenticated WITH CHECK `founder_id = auth.uid()`).

## Phase 3 — SECURITY DEFINER RPCs

Continue mig 053 (same `BEGIN;…COMMIT;`). All use `SET LOCAL session_replication_role='replica'` for WORM bypass.

- [x] 3.1 RPC `authorize_template(p_template_hash, p_action_class, p_grant_id)` — input validation, INSERT, return id, idempotent 23505 (first-writer-wins). GRANT TO authenticated; REVOKE FROM PUBLIC/anon/service_role.
- [x] 3.2 RPC `revoke_template_authorization(p_template_hash, p_reason)` — validate `p_reason IN (8-value enum)`. Inline comment-of-record: `-- WORM trigger blocks all UPDATEs including founder-initiated revoke; bypass is required.` `SET LOCAL session_replication_role='replica'`; UPDATE WHERE `founder_id = auth.uid() AND template_hash = p_template_hash AND revoked_at IS NULL`; `RESET session_replication_role`. Return ROW_COUNT.
- [x] 3.3 RPC `anonymise_template_authorizations(p_user_id)` — auth: `auth.uid() IS NULL && current_user IN ('service_role','postgres')` OR `auth.uid() = p_user_id`. UPDATE founder_id = NULL + revoked_at COALESCE + revocation_reason COALESCE 'dsr_erasure'. GRANT TO authenticated, service_role.
- [x] 3.4 Close `BEGIN;…COMMIT;` envelope.
- [x] 3.5 Write `apps/web-platform/supabase/migrations/053_template_authorizations.down.sql` — DROP order: TRIGGER → 3 RPCs → trigger function → table → ALTER messages DROP COLUMN template_id.

## Phase 4 — Predicate + First-Send-IS-Authorization + Send-Route Wiring

- [x] 4.1 Create `apps/web-platform/server/templates/is-template-authorized.ts`:
  - Inline `DenyReason` type at top (no separate file).
  - `PredicateResult` discriminated union: `authorized | first_send | denied`.
  - Single SELECT returns most-recent row (founder_id, template_hash) JOIN action_sends count; TS branches.
  - **Fail-closed exception:** wrap SELECT in try/catch; rethrow as `PredicateException`.
  - **Auto-revoke side effect:** on expired or quota-exhausted detection, fire `revoke_template_authorization` (best-effort, async-safe).
- [x] 4.2 Write `test/server/templates/is-template-authorized.test.ts`:
  - Mock isGranted=null → assert predicate NOT called.
  - Mock each PredicateResult variant → assert send-route branches correctly.
  - Mock DB exception → assert 500 + Sentry (fail-closed).
  - First-send-IS-auth happy path: predicate returns first_send → authorize_template called → action_sends written.
- [x] 4.3 Edit `send/route.ts:155` — after isGranted 403 branch, before tier switch:
  - If `tier === 'draft_one_click'` (only tier currently requiring template auth), call `isTemplateAuthorized`.
  - On `denied` → 403 with `{ error: { code: 'template_not_authorized', deny_reason } }`.
  - On `first_send` → `authorize_template` RPC then write `action_sends` in same Supabase transaction.
  - On `authorized` → proceed to tier switch.
  - Wrap predicate in `Promise.race` 5s timeout.
- [x] 4.4 Emit pino `{template_hash, action_class, deny_reason, founder_id_hash}` on every denial. NO Sentry mirror on routine denials (v2 cut).

## Phase 5 — Today-Card Deny Surface + Revocation Reason Copy

- [x] 5.1 Edit `apps/web-platform/lib/messages/trust-tier-copy.ts` — append `REVOCATION_REASON_COPY` sibling export (8 keys, `{label, description}` each).
- [x] 5.2 Edit `apps/web-platform/components/dashboard/today-card.tsx`:
  - On 403 with `error.deny_reason`, render inline note below disabled button.
  - Per-DenyReason copy:
    - `no_scope_grant`: "You need a scope grant first. Visit Settings → Scope grants."
    - `template_revoked`: "This template was revoked. Click Send again to re-authorize."
    - `template_expired`: "This template authorization expired (90-day limit). Click Send again to re-authorize."
    - `template_quota_exhausted`: "You've sent 100 messages with this template. Click Send again to re-authorize for another 100."
    - `template_unauthorized`: unreachable in v2 — first send auto-authorizes (if seen, indicates predicate exception → user sees 500).
  - Reuse `disabled` + `title=""` pattern.

## Phase 6 — DSAR Allowlist Extension

- [x] 6.1 Edit `apps/web-platform/server/dsar-export.ts` — add `'template_authorizations'` to `DSAR_TABLE_ALLOWLIST`.

## Phase 7 — Scope-Grants Settings Section + Revoke Surface

- [x] 7.1 Create `apps/web-platform/components/scope-grants/template-authorization-row.tsx`:
  - Server component with props `{id, template_hash, action_class, authorized_at, expires_at, soft_reconfirm_at, max_sends, sends_used}`.
  - Renders row + per-row "Revoke" button (server action calling `revoke_template_authorization(template_hash, 'founder_revoked')`).
  - Failure UX: pessimistic update (button disabled in-flight), `revalidatePath('/dashboard/settings/scope-grants')` on success, error toast with retry on failure.
- [x] 7.2 Edit `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`:
  - Append `<section>` "Template authorizations" below existing scope-grants list.
  - Query JOINs scope_grants and filters `sg.revoked_at IS NULL` AND `ta.revoked_at IS NULL`.
  - Empty-state copy: static "No template authorizations yet. When you 1-click send a draft, the template will be authorized for up to 100 sends over 90 days."

## Phase 8 — Account-Delete Cascade Extension

- [x] 8.1 Edit `apps/web-platform/server/account-delete.ts:200-251` — insert `anonymise_template_authorizations(p_user_id)` call between line 211 and line 238.
- [x] 8.2 Inline comment-of-record citing SEMANTIC ordering (NOT FK-driven): `dsr_erasure` reason MUST be set on child rows BEFORE parent scope_grant's user_id is nulled — otherwise Art. 5(2) attribution breaks. (NOT "FK ON DELETE RESTRICT requires this ordering" — that rationale is wrong per Kieran v2 review.)
- [x] 8.3 Error handling matches surrounding try/catch; on failure `{status: 'failed', step: 'template_authorizations'}`.

## Phase 9 — Tests

All tests via vitest. Integration tests gated by `TENANT_INTEGRATION_TEST=1`.

- [x] 9.1 Write `test/server/templates/template-registry.test.ts` (TR8 collision + determinism).
- [x] 9.2 Write `test/server/templates/is-template-authorized.test.ts` (TR4 two-probe + first-send + exception fail-closed).
- [x] 9.3 Write `test/server/template-authorizations-worm.test.ts` (`TENANT_INTEGRATION_TEST=1`):
  - TR3 PostgREST-routed anonymise bypass under service-role AND self-DSAR authenticated.
  - TR5 parallel-grant race: exactly one row revoked_at IS NULL.
  - Auto-revoke: row with sends_used = max_sends - 1; write 1 action_send; predicate; assert revoked_at set.
  - First-send-IS-auth (AC12): synthetic founder + active scope_grant + no template_auth → first Send writes BOTH rows → second Send increments sends_used.
- [x] 9.4 Write `test/server/account-delete-template-authorizations-cascade.test.ts` (`TENANT_INTEGRATION_TEST=1`):
  - TR7 cascade semantic ordering verification (children carry `dsr_erasure` reason BEFORE grant nulled).
- [x] 9.5 Write `test/server/scope-grants/revocation-reason-exhaustive.test.ts` (TR6):
  - Mirror `action-class-exhaustive.test.ts`. Parity + exhaustive switch + runtime regex. Count locked at 8.
- [x] 9.6 Update `test/api/dashboard/today/send-route.test.ts` — add cases for first-send-IS-authorization + each DenyReason 403 path.

## Phase 10 — Legal Artifacts + ADR-035

- [x] 10.1 Edit `knowledge-base/legal/article-30-register.md` — append PA-16 mirroring PA-15 pattern.
- [x] 10.2 Edit `apps/web-platform/docs/legal/data-protection-disclosure.md` — append §2.3(t) "Template-authorization ledger". Include 8-value enum un-revocability + Art. 5(2) rationale (replaces former ADR-036).
- [x] 10.3 Edit `apps/web-platform/docs/legal/privacy-policy.md` — extend §8.3 with template-level authorization + forward-reference to PR-I+1.
- [x] 10.4 Edit `apps/web-platform/docs/legal/acceptable-use-policy.md` — one-line `policy_violation` revocation outcome.
- [x] 10.5 Eleventy mirror dual-write per `2026-03-20-eleventy-mirror-dual-date-locations.md`:
  - Mirror 10.2, 10.3, 10.4 to `plugins/soleur/docs/pages/legal/*.md`.
  - Update BOTH hero `<p>` Last-Updated AND body `**Last Updated:**` lines in each file. Date: `May 21, 2026`.
- [x] 10.6 Confirm NO T&C amendment needed (§3a already tier-agnostic).
- [x] 10.7 Create `knowledge-base/engineering/architecture/decisions/ADR-035-template-registry-code-static.md` — single ADR (others folded into legal §2.3(t) + plan Sharp Edges per v2 plan-review).

## Phase 11 — Pre-flight + PR Body

- [x] 11.1 Run all preflight checks: `vitest run`, `bun run typecheck`, `next lint`, mig 053 dry-run via `db:migrate` against dev.
- [x] 11.2 Run `/soleur:preflight` to catch migration / security-header / lockfile issues.
- [ ] 11.3 Update PR #4213 body:
  - Summary citing brainstorm + spec + plan v2 changes.
  - `## Changelog` section (semver:minor).
  - `Closes #4078` line in body (NOT title).
  - "Splits #4216 (PR-I+1 classifier UI) and #4217 (bound calibration) will follow."
  - Link to ADR-035.
- [ ] 11.4 Move PR #4213 from draft → ready: `gh pr ready 4213` (after all ACs satisfied).
- [ ] 11.5 Apply `semver:minor` label.

## Phase 12 — Multi-Agent Review (single-user-incident threshold)

- [ ] 12.1 Run `/soleur:review` with 6 agents (trimmed from v1's 11 per DHH review):
  - architecture-strategist
  - data-migration-expert
  - security-sentinel
  - gdpr-gate cross-reconcile
  - user-impact-reviewer (auto-fires per threshold)
  - code-simplicity-reviewer
- [ ] 12.2 Resolve all P0/P1 findings inline.
- [ ] 12.3 Obtain CPO sign-off comment on PR (single-user-incident threshold).
- [ ] 12.4 Verify AC1-AC12 all checked.

## Phase 13 — Ship

- [ ] 13.1 Run `/soleur:ship` to gate-check and auto-merge.
- [ ] 13.2 Verify post-merge: mig 053 applied on prd via `apply-web-platform-migrations.yml`.
- [ ] 13.3 Verify `gh issue close 4078` auto-fired via `Closes #4078`.
- [ ] 13.4 Monitor Sentry for `kind:template_*` tags for 24h post-merge.
- [ ] 13.5 Run `/soleur:postmerge` for production health verification.
