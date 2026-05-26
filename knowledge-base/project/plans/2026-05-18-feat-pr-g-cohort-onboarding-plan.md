---
title: "feat: PR-G — cohort onboarding (scope-grant UX, audit-log viewer, onboarding flow) (#3244 §G)"
date: 2026-05-18
issue: 3947
umbrella_issue: 3244
predecessor_prs: [3240, 3395, 3854, 3883, 3922, 3940]
spec: knowledge-base/project/specs/feat-pr-g-cohort-onboarding/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-18-pr-g-cohort-onboarding-brainstorm.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
draft_pr: 3984
branch: feat-pr-g-cohort-onboarding
detail_level: A_LOT
---

# PR-G — Cohort onboarding (scope-grant UX, audit-log viewer, onboarding flow)

## Overview

Seventh slice of the agent-runtime umbrella ([#3244](https://github.com/jikig-ai/soleur/issues/3244)). PR-A→F shipped substrate (tenant isolation, BYOK lease, sibling-query migration, attachments RLS, `audit_byok_use` writer sweep, Inngest trigger layer + CFO autonomous-draft). PR-G ships the **cohort-exposure surface** in a single bundled PR (Approach A per brainstorm K1):

1. `scope_grants` substrate (append-only WORM ledger + SECURITY DEFINER RPCs + RLS self-select + code-constant denylist).
2. Webhook predicate change at `apps/web-platform/app/api/webhooks/stripe/route.ts:437`: `flag === "true"` → `flag === "true" && isGranted(founderId, 'finance.payment_failed') && !isDenied(actionClass)`.
3. Three new user-facing surfaces: scope-grant settings page, audit-log viewer, runtime onboarding explainer banner.
4. Art. 22(3) "request human review" affordance (added at plan time per spec-flow-analyzer finding — see §Research Reconciliation).
5. Four legal-doc amendments (× 2 mirror paths = 8 files): ToS §3a "Agent Command Authority", AUP "Automated agent actions taken on your behalf", Privacy Policy Art. 22 disclosure, DPD §2.3(o) extension.
6. T&C version bump with enforcement-surface parity sweep (per `2026-03-20-tc-version-enforcement-surface-parity.md`).
7. ADR-031 (per-tenant scope grants as Supabase substrate).
8. Doppler `prd` `SOLEUR_FR5_ENABLED=true` flip as final **post-merge** operator step (K14 — operator override of CTO/CPO test-now/flip-later; the per-grant deny-by-default predicate is the load-bearing replacement safety primitive).

Brand-survival threshold: **single-user incident**. CPO sign-off required before `/work` begins.

## Research Reconciliation — Spec vs. Codebase

The spec was authored from the brainstorm with high confidence; plan-time research surfaced four claims that need adjustment vs. installed reality.

| # | Spec claim | Codebase reality | Plan response |
|---|------------|------------------|---------------|
| 1 | FR8 references "Inngest HTTP API" without naming the env var carrying the API base URL. Brainstorm/best-practices guessed `INNGEST_API_BASE_URL`. | `apps/web-platform/server/inngest/client.ts:18` uses `INNGEST_BASE_URL` (not `INNGEST_API_BASE_URL`). Set to `http://127.0.0.1:8288` per ADR-030 self-hosted Hetzner deploy. | Plan uses `INNGEST_BASE_URL` verbatim; the new `lib/inngest/list-runs.ts` helper reads the same env var as the SDK client. |
| 2 | FR3 RPC parameter ordering and signature. | Migration 044 `accept_terms(p_user_id, p_version, p_doc_sha)` ordering shows: caller-attributed user_id is first parameter (not `auth.uid()` — service-role caller attributes on behalf of authenticated user). Migration 037 `write_byok_audit` follows same shape. | `grant_action_class(p_action_class text, p_tier text)` and `revoke_action_class(p_action_class text, p_reason text)` use `auth.uid()` inside the function body (founder writes own grants directly — no service-role wrapper). Adjusted from spec FR3 to remove the `p_user_id` parameter; the body guards on `auth.uid() = founder_id` and rejects if NULL. This is the right shape because the founder IS the authenticated caller (unlike `accept_terms` which is called from `/api/accept-terms` server route with service-role). |
| 3 | NG6 says "no Supabase mirror table for Inngest function executions." | Confirmed: `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` writes a `messages` row in `persist-draft` step, but the run-history itself lives only in Inngest backend. | Plan honors NG6. `/api/dashboard/runs` proxies to `${INNGEST_BASE_URL}/v1/events?name=finance.payment_failed&cel=event.data.founderId=='<uuid>'` then fans out per event id to `/v1/events/{id}/runs`. |
| 4 | `cfo-on-payment-failed.ts:13` says `RV4 — TIER constant inlined; ACTION_CLASS_DEFAULTS lifts to a map when PR-G's 2nd consumer arrives (follow-up #3947).` Spec didn't list this lift. | PR-F's `RV4` named PR-G (this PR) as the consumer that triggers extraction of `ACTION_CLASS_DEFAULTS` to a typed map. | Plan adds `apps/web-platform/server/scope-grants/action-class-map.ts` as the canonical map; webhook predicate and audit viewer both consume from this file. PR-F's inlined constant in `cfo-on-payment-failed.ts` is replaced with an import from this map. |

Additional plan-time discoveries:

- **CTO substrate delta (brainstorm K4):** load-bearing safety primitive is now the per-grant deny-by-default predicate. Plan adds a precondition test (TR3) that MUST pass on main BEFORE the post-merge Doppler flip.
- **Spec-flow-analyzer (BLOCKING tier):** critical FR omission — Art. 22(3) "request human review" affordance has no FR. **New FR15** added below.
- **CPO advisory (page-flow):** scope-grant page entry points must be specified (Today banner CTA, audit-row deep-link, settings nav). **New FR16** added. Pessimistic-UI invariant added to FR6.
- **Learnings-researcher (2026-05-06-supabase-default-privileges...):** every SECURITY DEFINER RPC needs explicit `REVOKE EXECUTE FROM PUBLIC, anon, authenticated` because Supabase auto-grants to all three wire roles. **TR11** added.
- **Learnings-researcher (2026-05-16-migration-mandates...):** `anonymise_scope_grants` RPC MUST be wired into `apps/web-platform/server/account-delete.ts` in the same PR. **New FR17** added.
- **Learnings-researcher (2026-05-15-worm-trigger-blocks-pg-cron):** future retention sweep on scope_grants must use row-state-based bypass, not role-gated. Captured in §Sharp Edges; no current sweep ships in PR-G.

## User-Brand Impact

> Carried forward from brainstorm + augmented with vector 5 promotion to first-class FR (Art. 22(3) affordance was implicit; plan promotes it to FR15).

**If this lands broken, the user experiences:**
1. **Cross-tenant read** via `/dashboard/audit` — founder A sees founder B's BYOK history, Inngest run output, or scope-grant state. Single-user incident: one cross-render = brand-ending.
2. **Unauthorized agent action** — `finance.payment_failed` triggers `inngest.send` for a founder who never granted the action-class, because the webhook predicate honors `SOLEUR_FR5_ENABLED=true` alone (the brainstorm K14 risk if K4's per-grant predicate is mis-implemented).
3. **PII exposure** in the audit viewer — raw `authorizing_event` rendered with Stripe customer_email visible.
4. **Credential leak** — `INNGEST_SIGNING_KEY` bundled to the client because `/api/dashboard/runs` is mis-marked as client-callable, or scope-grant write tokens leak via Server Action response payload.
5. **Trust breach via Art. 22(3) gap** — founder sees a draft they never authorized (or worse, an auto-sent message under `auto` tier) and has no UI affordance to "request human review" or contest the action.

**If this leaks, the user's data is exposed via:**
- `audit_byok_use` rows (founder_id, agent_role, token_count, unit_cost_cents, ts) cross-rendered to another tenant
- Inngest run history with `event.data` payload containing `customerEmailHash`, invoice metadata, draft text excerpts
- `scope_grants` rows revealing which action-classes a founder has authorized (a forensic signal about founder business state — e.g., "founder Y has auto-tier money-class actions" leaks business posture)

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan-time (this document); `user-impact-reviewer` agent invoked at PR review per `plugins/soleur/skills/review/SKILL.md`.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)

**Status:** reviewed (carry-forward).
**Assessment:** No existing `scope_grants` substrate — confirmed via `git grep -l scope_grants apps/web-platform/ → 0 matches`. Migration 048 (append-only WORM ledger + SECURITY DEFINER RPCs + RLS self-select) is the right shape. Audit viewer reads via cookie-scoped RLS client (NOT service-role); Inngest runs via server-only proxy. Onboarding extends existing `useOnboarding` hook + new column. Precondition test (`flag && no_grant → no_send`) must pass on main before flip. Substrate delta: webhook predicate must require BOTH flag AND grant existence; flag alone is unsafe.

### Product (CPO)

**Status:** reviewed (plan-time + carry-forward).
**Assessment:** User-Brand threshold holds; vector list expands to 5 (read-path tenancy + Art. 22(3) affordance gap promoted to FR). Page-flow advisory: 3 entry points per surface, pessimistic-UI invariant on grant changes, second-click acknowledgement on `auto` tier (money-class), audit-row pins grant-tier-at-time-of-event. Recommends spawning ux-design-lead for wireframes + spec-flow-analyzer for flow gaps — **both invoked at plan time** (see Product/UX Gate below).

### Legal (CLO)

**Status:** reviewed (carry-forward).
**Assessment:** Four legal doc amendments become load-bearing for PR-G that were dormant in PR-F: ToS §3a "Agent Command Authority", AUP "Automated agent actions taken on your behalf", Privacy Policy Art. 22 disclosure, DPD §2.3(o) extension. "Drafts everywhere, sends nowhere" is the binding invariant for tier defaults; any auto-send tier requires Art. 22(3) human-review affordance (FR15). Audit viewer must satisfy Art. 15 right of access; MUST NOT show other tenants' rows, BYOK key material, or raw `customer_email`. Sub-processor disclosure: Inngest is self-hosted (DPD §2.3(o)) — no new entry on public sub-processor page.

### Product/UX Gate

**Tier:** blocking (mechanical escalation — new files in `components/**/*.tsx` AND `app/**/page.tsx`).
**Decision:** reviewed.
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead.
**Skipped specialists:** copywriter (no domain leader recommended; brand voice carried forward from brand-guide.md — Tesla/SpaceX, no gamification, "You decide. Agents execute.").
**Pencil available:** yes (ux-design-lead produced `.pen` + 6 screenshots; see §Files to Create).
**Brainstorm-recommended specialists:** spec-flow-analyzer ✓ invoked; ux-design-lead ✓ invoked; copywriter — not recommended by brainstorm domain leaders, skipped.

#### Findings

**spec-flow-analyzer:** Surfaced 7 flow gaps. Critical: Art. 22(3) "request human review" affordance is missing — **promoted to FR15** below. Other gaps addressed inline:
- Empty-state copy for audit viewer (zero rows) and scope-grants (no grant yet) — FR6/FR7 amended with explicit copy lines.
- Partial-degradation contract when Inngest API fails but BYOK succeeds — FR7 amended.
- Cross-surface "Change authorization" link from audit row → scope-grants page — **promoted to FR16**.
- In-flight revocation UX copy — added to FR6 ("Revoking won't stop runs already in progress").
- Denylist rejection copy — added to FR6 (unreachable in PR-G's one-class scope, but ships for forward compat).
- Banner re-trigger when new action classes ship — deferred per NG2.

**CPO:** Page-flow advisory with three entry points per surface (Today banner, audit-row deep-link, settings nav) — **promoted to FR16**. Pessimistic-UI invariant on grant changes (no optimistic update) — added to FR6. Second-click acknowledgement on `auto` tier before write fires — added to FR6 ("Auto" tier reveals an inline acknowledgement: "Soleur will execute this action without your review. Confirm."). Audit-row pins grant-tier-at-time-of-event (read from Inngest event metadata, not current grant state) — added to FR7.

**ux-design-lead:** `.pen` wireframe + 6 screenshots at `knowledge-base/product/design/scope-grants/`. Tokens: `bg-page #0A0A0A`, `gold #C9A962`, `success #4ADE80`, `danger #F87171` (auto-tier rendered in red as "Consequential"). Cost disclosure on every authorize footer. Today-banner extension pattern matches existing `today-banner.tsx`.

## Infrastructure (IaC)

PR-G introduces **no new infrastructure**. Verifications:

- No new Terraform resources, no new providers, no new vendor accounts, no new DNS/TLS/firewall rules.
- One Doppler secret flip (`SOLEUR_FR5_ENABLED=false → true` in `prd`) — handled as post-merge operator step per K14 with explicit justification.
- Supabase migrations 048 + 049 land via the established `supabase/migrations/` pattern (Vercel deploy hook applies on merge to main).

### Apply path

(N/A — no Terraform changes.)

### Doppler flag flip — automation feasibility note

**Detection:** Phase 2.8 keyword scan matches `doppler secrets set` in the post-merge operator step.

**Automation: not feasible because** cohort go-live is a subjective brand-survival risk assessment requiring CPO sign-off + first dogfood founder selection, not API-verifiable state. Per `hr-all-infrastructure-provisioning-servers` Sharp Edge carve-out: "Genuinely operator-only steps (CAPTCHA-gated portal config, interactive OAuth consent on a third-party site, **subjective decisions requiring human judgment — design taste, strategy, prioritization**) MAY remain in `### Post-merge (operator)` with a one-line `Automation: not feasible because <X>` justification." The flip IS API-callable but its decision criterion is not API-verifiable.

## Implementation Phases

> **Phase ordering rule (Sharp Edge):** contract-changing edits ship BEFORE consumer edits. Migrations 048 + 049 (Phase 1) ship before webhook predicate (Phase 2); webhook predicate ships before scope-grant UX (Phase 4). All phases are pre-merge except Phase 13 (operator-only).

### Phase 0 — Preconditions (no code yet)

Goal: verify every claim the plan rests on; surface any drift before code.

- [ ] **0.1 Migration number availability.** `ls apps/web-platform/supabase/migrations/047_*.sql 2>/dev/null` returns empty (047 is the next number after the merged 046). Plan uses 048 and 049 to leave 047 open for any sibling PR in flight.
- [ ] **0.2 Substrate absence verification.** `git grep -lE "scope_grants|scope_grant|grant_action_class|revoke_action_class|runtime_explainer_dismissed_at" apps/web-platform/` returns zero matches.
- [ ] **0.3 Doppler `prd` pre-flip state.** `doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain` returns `false` (confirm we're not flipping an already-flipped flag). Read-only probe per `hr-menu-option-ack-not-prod-write-auth`.
- [ ] **0.4 Inngest SDK version + env vars.** Confirm `apps/web-platform/package.json` dependencies pin `inngest@^3.54.2`. Confirm `INNGEST_BASE_URL`, `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY` are set in Doppler `dev` and `prd`.
- [ ] **0.5 Inngest REST API probe (DEV ONLY).** Against `dev` Doppler:
  ```bash
  curl -sS -H "Authorization: Bearer $INNGEST_SIGNING_KEY" \
    "$INNGEST_BASE_URL/v1/events?name=finance.payment_failed&limit=1"
  ```
  MUST return HTTP 200 with `{ "data": [...], "metadata": {...} }`. If 404, the self-hosted instance's API path differs from `/v1/*` — plan must pivot to `/v0/*` or GraphQL. (Best-practices research says `/v1/*` is canonical for 2026; verify before writing the proxy.) Cite verified output in §Test Plan.
- [ ] **0.6 Existing cascade pattern read.** Read `apps/web-platform/server/account-delete.ts:200-230` to confirm the cascade ordering (currently: tc_acceptances → auth.admin.deleteUser). Plan adds `anonymise_scope_grants` BEFORE `anonymise_tc_acceptances` per migration 044's `ON DELETE RESTRICT` FK semantic (Phase 1.4 below).
- [ ] **0.7 `gdpr-gate` skill invocation.** Per `hr-gdpr-gate-on-regulated-data-surfaces` (canonical regex matches: new schema, migrations, auth flows, API routes, .sql files — PR-G hits all five). Invoke `/soleur:gdpr-gate` against this plan doc + spec.md. Capture findings in `knowledge-base/legal/compliance-posture.md` Active Items. Any `compliance/critical` issue MUST be addressed inline (folded into FRs) before Phase 1 begins.
- [ ] **0.8 `gh label list --limit 200`.** Verify `domain/product`, `domain/legal`, `domain/engineering`, `priority/p2-medium`, `type/feature` exist. None of these are new — sanity check.
- [ ] **0.9 Code-review overlap.** Already run (see §Open Code-Review Overlap). Zero matches.

**Phase 0 exit:** all checks pass; gdpr-gate's compliance findings folded; brainstorm `## User-Brand Impact` carried forward to plan.

### Phase 1 — Substrate (migrations + denylist + action-class map)

Goal: ship the data + safety primitives the webhook predicate and UI consume.

#### 1.1 Migration 048 — `scope_grants`

File: `apps/web-platform/supabase/migrations/048_scope_grants.sql`

Shape (mirror `037_audit_byok_use.sql` for WORM + `044_add_tc_acceptances_ledger.sql` for SECURITY DEFINER RPC patterns):

```sql
-- 048_scope_grants.sql
-- PR-G (#3947) — Per-action-class scope grants. Append-only WORM ledger
-- gating `inngest.send` in the Stripe webhook predicate (#3940 §F).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp (public FIRST).
-- Precedent: 044_add_tc_acceptances_ledger.sql.
--
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT to
-- service_role (or authenticated, as appropriate) on each caller-facing
-- RPC.

CREATE TABLE IF NOT EXISTS public.scope_grants (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  founder_id      uuid         NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  action_class    text         NOT NULL CHECK (length(action_class) BETWEEN 1 AND 64),
  tier            text         NOT NULL CHECK (tier IN ('auto','draft_one_click','approve_every_time')),
  granted_at      timestamptz  NOT NULL DEFAULT now(),
  revoked_at      timestamptz  NULL,
  revoked_reason  text         NULL CHECK (revoked_reason IS NULL OR length(revoked_reason) BETWEEN 1 AND 256),
  created_at      timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.scope_grants ENABLE ROW LEVEL SECURITY;

-- Founder-readable SELECT only. INSERT routed through grant_action_class
-- RPC; UPDATE only via revoke_action_class (column flip on revoked_at).
CREATE POLICY scope_grants_owner_select ON public.scope_grants
  FOR SELECT USING (auth.uid() = founder_id);

-- WORM trigger: only `revoked_at` and `revoked_reason` columns may be
-- updated, and only when transitioning NULL → non-NULL (revocation).
-- DELETE is unconditionally rejected (use anonymise_scope_grants for
-- Art. 17 cascade).
CREATE OR REPLACE FUNCTION public.scope_grants_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
AS $$
DECLARE
  v_anonymise_flag text;
BEGIN
  v_anonymise_flag := current_setting('app.scope_grants_anonymise_in_progress', true);
  -- Bypass gate: GUC set AND caller is service_role. `session_user` is the
  -- original connection role (unaffected by SECURITY DEFINER context shift);
  -- `current_user` is the effective role. Anonymise RPC is SECURITY DEFINER
  -- (typically owner = postgres), so we need session_user OR current_user
  -- to catch both Supabase-default and self-hosted ownership patterns.
  -- Mirrors migration 044's pattern; if 044's role check is broken so is
  -- this — see Sharp Edges for the latent risk note.
  IF v_anonymise_flag <> ''
     AND (current_user = 'service_role' OR session_user = 'service_role')
  THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'scope_grants is append-only; use anonymise_scope_grants for Art. 17 cascade' USING ERRCODE = 'P0001';
  END IF;

  -- TG_OP = 'UPDATE': allow only revoked_at / revoked_reason transitions
  -- from NULL to non-NULL.
  IF OLD.founder_id IS DISTINCT FROM NEW.founder_id
     OR OLD.action_class IS DISTINCT FROM NEW.action_class
     OR OLD.tier IS DISTINCT FROM NEW.tier
     OR OLD.granted_at IS DISTINCT FROM NEW.granted_at
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
     OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at)
     OR (OLD.revoked_reason IS NOT NULL AND NEW.revoked_reason IS DISTINCT FROM OLD.revoked_reason)
  THEN
    RAISE EXCEPTION 'scope_grants is append-only; only NULL→value revocation is permitted' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.scope_grants_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS scope_grants_no_update ON public.scope_grants;
CREATE TRIGGER scope_grants_no_update
  BEFORE UPDATE ON public.scope_grants
  FOR EACH ROW EXECUTE FUNCTION public.scope_grants_no_mutate();

DROP TRIGGER IF EXISTS scope_grants_no_delete ON public.scope_grants;
CREATE TRIGGER scope_grants_no_delete
  BEFORE DELETE ON public.scope_grants
  FOR EACH ROW EXECUTE FUNCTION public.scope_grants_no_mutate();

-- Covering index for the webhook predicate's "is there an active grant for
-- (founder_id, action_class)?" hot path. Filters on revoked_at IS NULL
-- via partial index keeps the index small.
CREATE INDEX scope_grants_active_idx
  ON public.scope_grants (founder_id, action_class, granted_at DESC)
  WHERE revoked_at IS NULL;

-- grant_action_class: founder-callable INSERT (NOT service-role-only —
-- unlike accept_terms, the founder is the authenticated caller).
CREATE OR REPLACE FUNCTION public.grant_action_class(
  p_action_class text,
  p_tier         text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_grant_id   uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated' USING ERRCODE = '28000';
  END IF;

  IF p_tier NOT IN ('auto','draft_one_click','approve_every_time') THEN
    RAISE EXCEPTION 'invalid tier: %', p_tier USING ERRCODE = '22P02';
  END IF;

  -- INSERT a fresh row; revoke the previous active grant for the same
  -- (founder_id, action_class) atomically. Tier change is a re-grant
  -- by design — preserves the chain of consent.
  UPDATE public.scope_grants
     SET revoked_at = now(),
         revoked_reason = 'tier_change'
   WHERE founder_id = v_founder_id
     AND action_class = p_action_class
     AND revoked_at IS NULL;

  INSERT INTO public.scope_grants (founder_id, action_class, tier)
       VALUES (v_founder_id, p_action_class, p_tier)
       RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_action_class(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_action_class(text, text)
  TO authenticated;

-- revoke_action_class: founder-callable UPDATE (NULL → value transition
-- per WORM trigger).
CREATE OR REPLACE FUNCTION public.revoke_action_class(
  p_action_class text,
  p_reason       text
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_rows int;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated' USING ERRCODE = '28000';
  END IF;

  UPDATE public.scope_grants
     SET revoked_at = now(),
         revoked_reason = p_reason
   WHERE founder_id = v_founder_id
     AND action_class = p_action_class
     AND revoked_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_action_class(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_action_class(text, text)
  TO authenticated;

-- anonymise_scope_grants: Art. 17 cascade. Mirror migration 044's
-- anonymise_tc_acceptances pattern. Called from account-delete.ts
-- BEFORE auth.admin.deleteUser() per ON DELETE RESTRICT FK ordering.
CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL app.scope_grants_anonymise_in_progress = 'on';

  UPDATE public.scope_grants
     SET founder_id = NULL
   WHERE founder_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_scope_grants(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_scope_grants(uuid)
  TO service_role;

COMMENT ON TABLE public.scope_grants IS
  'Append-only per-action-class scope grants. PR-G (#3947). One active '
  'row per (founder_id, action_class); tier change = revoke previous + '
  'insert new. WORM-gated; only revoked_at/revoked_reason mutable. '
  'auth.uid() = founder_id RLS self-select. Anonymise cascade via '
  'anonymise_scope_grants(user_id).';
```

**WORM-trigger note:** the trigger function is `INVOKER` semantics (no `SECURITY DEFINER`) so that `current_user` correctly reflects the calling role for the anonymise bypass — mirrors migration 044's reasoning (lines 105-108).

**FK ordering:** `founder_id REFERENCES users(id) ON DELETE RESTRICT` — preserves audit trail; offboarding MUST call `anonymise_scope_grants` first.

#### 1.2 Migration 049 — `users.runtime_explainer_dismissed_at`

File: `apps/web-platform/supabase/migrations/049_runtime_explainer_state.sql`

```sql
-- 049_runtime_explainer_state.sql
-- PR-G (#3947) — Track first-time dismissal of the runtime onboarding
-- explainer banner. Nullable timestamptz; NULL = not yet dismissed.
--
-- Mirrors migration 012_onboarding_state.sql pattern (onboarding_completed_at,
-- pwa_banner_dismissed_at).

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS runtime_explainer_dismissed_at timestamptz NULL;

COMMENT ON COLUMN public.users.runtime_explainer_dismissed_at IS
  'NULL = banner shows on Today section first render. Non-NULL = dismissed. '
  'Set via useOnboarding.updateUserField. PR-G (#3947).';
```

#### 1.3 Scope-grants server module + CFO function import swap

**Collapsed from 4 files to 2 per code-simplicity + DHH review.** Denylist is empty in PR-G — no separate file. Grant-RPC wrappers were one-line `.rpc(...)` calls — inline into the route handlers (Phase 3.2).

File: `apps/web-platform/server/scope-grants/action-class-map.ts`

```typescript
// PR-G (#3947) — Canonical action-class map. Lifts PR-F's inlined
// `ACTION_CLASS_DEFAULTS` constant (cfo-on-payment-failed.ts:13 RV4 named
// PR-G as the 2nd-consumer trigger for this extraction).

export const ACTION_CLASSES = ["finance.payment_failed"] as const;
export type ActionClass = (typeof ACTION_CLASSES)[number];

export const ACTION_CLASS_DEFAULTS: Record<ActionClass, "auto" | "draft_one_click" | "approve_every_time"> = {
  "finance.payment_failed": "approve_every_time", // most restrictive default
};

export function isKnownActionClass(s: string): s is ActionClass {
  return (ACTION_CLASSES as readonly string[]).includes(s);
}
```

File: `apps/web-platform/server/scope-grants/is-granted.ts`

```typescript
// PR-G (#3947) — Webhook predicate's grant probe. Reads scope_grants via
// service-role client because the webhook handler is service-role-context
// (no founder JWT). The .eq("founder_id", founderId) is load-bearing
// here (not belt-and-suspenders) — service-role bypasses RLS.

import type { SupabaseClient } from "@supabase/supabase-js";
import * as Sentry from "@sentry/nextjs";

// Code-constant denylist. Inlined per Code Simplicity review — PR-G ships
// with empty denylist; when the first entry lands, extract to a sibling
// file alongside an unmocked rejection test.
const ACTION_CLASS_DENYLIST: ReadonlySet<string> = new Set<string>();
const isDenied = (ac: string) => ACTION_CLASS_DENYLIST.has(ac);

export interface ActiveGrant {
  tier: "auto" | "draft_one_click" | "approve_every_time";
}

export async function isGranted(
  serviceClient: SupabaseClient,
  founderId: string,
  actionClass: string,
): Promise<ActiveGrant | null> {
  if (isDenied(actionClass)) return null;

  const { data, error } = await serviceClient
    .from("scope_grants")
    .select("tier")
    .eq("founder_id", founderId)
    .eq("action_class", actionClass)
    .is("revoked_at", null)
    .order("granted_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  // Distinguish no-grant (silent null) from DB error (Sentry + null).
  // Fail-closed in both cases per single-user-incident threshold:
  // if we can't confirm a grant exists, we don't fire inngest.send.
  // But DB errors are a regression signal — surface to Sentry per
  // FR8 / TR9 / Kieran P1-5.
  if (error) {
    Sentry.captureException(error, {
      tags: { surface: "is-granted", action_class: actionClass },
    });
    return null;
  }
  if (!data) return null;
  return { tier: data.tier as ActiveGrant["tier"] };
}
```

**CFO function import swap (RV4 cleanup) — same Phase 1.3 commit.**

Edit `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` lines 12-13 + the inlined `ACTION_CLASS_DEFAULTS` reference (whichever line). Replace with `import { ACTION_CLASS_DEFAULTS, type ActionClass } from "@/server/scope-grants/action-class-map";`. Per `hr-type-widening-cross-consumer-grep`: grep `ACTION_CLASS_DEFAULTS` across the repo and verify all consumers import from the new map.

#### 1.4 Wire `anonymise_scope_grants` into `account-delete.ts`

Edit `apps/web-platform/server/account-delete.ts:200-230` — insert `anonymise_scope_grants` call BEFORE the existing `anonymise_tc_acceptances` call (per migration 044's ordering documentation: anonymise cascade RPCs run BEFORE `auth.admin.deleteUser`).

```typescript
// 5.4 anonymise-scope-grants — anonymise_scope_grants RPC (migration 048).
// Runs BEFORE anonymise_tc_acceptances per FK ordering (both target
// public.users with ON DELETE RESTRICT).
const { error: anonymiseScopeGrantsError } = await service.rpc(
  "anonymise_scope_grants",
  { p_user_id: userId },
);
if (anonymiseScopeGrantsError) {
  // Match existing reportSilentFallback signature at account-delete.ts:214
  // (verify exact shape at /work time): (err, { feature, op, message, extra }).
  reportSilentFallback(anonymiseScopeGrantsError, {
    feature: "account-delete",
    op: "anonymise-scope-grants",
    message: "anonymise_scope_grants failed — aborting deletion to avoid FK-block",
    extra: { userId },
  });
  return { ok: false, error: anonymiseScopeGrantsError };
}
```

**Note:** the exact `reportSilentFallback` signature must be re-verified against `apps/web-platform/server/observability.ts` at /work time per Kieran P1-6 — sibling sites use the (err, opts) form, not (opts) alone.

Test: extend `apps/web-platform/test/server/account-delete.test.ts` (if exists) or write new test `account-delete-scope-grants-cascade.test.ts` asserting cascade order.

#### 1.5 Trust-tier copy file

File: `apps/web-platform/lib/messages/trust-tier-copy.ts` (mirror `lib/messages/tiers.ts:5-8` single-source pattern).

```typescript
// PR-G (#3947) — Single source of truth for trust-tier human-readable
// labels + descriptions. Per messages/tiers.ts:5-8 pattern: a typo at
// any consumer silently propagates to the UI. Every consumer (scope-grant
// page, audit viewer, onboarding banner) imports from here.

export const TRUST_TIER_COPY = {
  auto: {
    label: "Auto",
    badge: "Consequential",
    description:
      "Soleur executes this action without your review. Use only for actions you want fully automated.",
    confirmText:
      "Confirm: Soleur will execute this action without your review. You can revoke at any time, but revoking will not stop runs already in progress.",
  },
  draft_one_click: {
    label: "Draft, one click",
    badge: "Standard",
    description:
      "Soleur prepares a draft; you approve with one click. Recommended for most actions.",
    confirmText: null,
  },
  approve_every_time: {
    label: "Approve every time",
    badge: "Safest",
    description:
      "Soleur proposes; you authorize each time. Highest oversight.",
    confirmText: null,
  },
} as const;

export type TrustTier = keyof typeof TRUST_TIER_COPY;
```

**Phase 1 exit:** migrations 048 + 049 apply locally (`supabase db reset`); all four new server-side files compile; account-delete cascade wired; `tsc --noEmit` clean.

### Phase 2 — Webhook predicate change + precondition test

Goal: make `inngest.send` deny-by-default per tenant; ship the load-bearing safety primitive that compensates for K14's flip-in-PR-G decision.

#### 2.1 Edit `apps/web-platform/app/api/webhooks/stripe/route.ts`

Current shape at line 428-466:

```typescript
// Default OFF at merge per Phase 0 ops task (SOLEUR_FR5_ENABLED=false ...)
if (process.env.SOLEUR_FR5_ENABLED === "true" && customerId) {
  // ... lookup founder by stripe_customer_id, then:
  await inngest.send({ name: "finance.payment_failed", data: { ... } });
}
```

New shape:

```typescript
import { isGranted } from "@/server/scope-grants/is-granted";

// ... existing customer lookup → founderId (uses the service-role
// `supabase` client at route.ts:~120; verify exact symbol name at /work) ...

if (process.env.SOLEUR_FR5_ENABLED === "true" && customerId && founderId) {
  // Per-grant deny-by-default: ALL of (flag=on, grant exists, not denylisted)
  // must hold. This is the load-bearing safety primitive (brainstorm K4)
  // — the env flag alone is NOT a tenant-level gate. Pass the existing
  // service-role `supabase` client (NOT `service` — Kieran P0-2 caught
  // a variable-name drift in plan v1).
  const grant = await isGranted(supabase, founderId, "finance.payment_failed");
  if (!grant) {
    // No active grant OR DB error — fail-closed silently at the webhook.
    // DB errors are mirrored to Sentry inside isGranted (FR8 / TR9).
    return new Response("ok", { status: 200 });
  }

  // Future: tier-conditional dispatch (auto vs draft_one_click vs
  // approve_every_time). PR-G's first action class ships at the founder's
  // chosen tier; the CFO function reads tier from event.data.tier and
  // sets messages.tier accordingly per "drafts everywhere, sends nowhere".
  await inngest.send({
    name: "finance.payment_failed",
    data: {
      founderId,
      invoiceId: ...,
      customerEmailHash: ...,
      amount: ...,
      currency: ...,
      tier: grant.tier, // <-- pin grant-tier-at-time-of-event
    },
  });
}
```

#### 2.2 Precondition test (TR3)

File: extend `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts`. Add test case:

```typescript
it("does NOT call inngest.send when SOLEUR_FR5_ENABLED=true and no scope_grants row exists", async () => {
  process.env.SOLEUR_FR5_ENABLED = "true";
  // Seed user but NO scope_grants row.
  const { user } = await seedTestUser(service);
  const event = makeStripeInvoicePaymentFailedEvent({
    customerId: user.stripe_customer_id,
  });

  const sendSpy = vi.spyOn(inngest, "send");
  const res = await POST(makeRequest(event));

  expect(res.status).toBe(200);
  expect(sendSpy).not.toHaveBeenCalled();
});
```

#### 2.3 Webhook predicate denylist test (TR5)

Same file, add:

```typescript
it("does NOT call inngest.send when action_class is in ACTION_CLASS_DENYLIST", async () => {
  // Seed grant; mock denylist to include finance.payment_failed for this test only.
  // (PR-G's real denylist is empty; this test asserts the denylist check IS wired.)
  vi.spyOn(denylistModule, "isDenied").mockReturnValue(true);
  // ... assert inngest.send NOT called
});

it("DOES call inngest.send when SOLEUR_FR5_ENABLED=true AND scope_grants row exists AND not denylisted", async () => {
  // Seed grant at 'draft_one_click' tier. Assert sendSpy called with
  // data.tier === 'draft_one_click'.
});
```

**Phase 2 exit:** all webhook tests pass locally; `bun test apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts` green; TR3 + TR5 covered.

### Phase 3 — Scope-grant UX

Goal: founder-facing page to grant/revoke per-action-class authorization with pessimistic UI and second-click acknowledgement on `auto`.

#### 3.1 Page + component

**Collapsed from 3 component files to 1 per code-simplicity review.** List wrapper + empty-state inlined into the page (one action class, no iteration overhead worth a module boundary).

Files (new):

- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` — server component. Fetches current grants via cookie-scoped Supabase client + belt-and-suspenders `.eq("founder_id", user.id)`. Inline maps `ACTION_CLASSES` to `<ScopeGrantRow>`; inline conditional renders the explicit empty state ("No grants yet — Soleur will not act on your behalf for any action class.") above the row(s).
- `apps/web-platform/components/scope-grants/scope-grant-row.tsx` — client component. Three-radio tier picker. On `auto` selection: reveals inline acknowledgement with confirmText from `TRUST_TIER_COPY.auto.confirmText`. Submit button disabled until acknowledgement checked. **Pessimistic UI** — no optimistic state; radio reverts to server-confirmed state on success/failure. This friction is load-bearing at single-user-incident threshold (DHH P0.3 argued against; rejected per CPO brand-survival framing).

#### 3.2 Server route handlers

Files (new):

- `apps/web-platform/app/api/scope-grants/grant/route.ts` — POST handler. **Inlines** the `.rpc("grant_action_class", { p_action_class, p_tier })` call (no separate `grant-rpc.ts` wrapper module — code-simplicity collapse). Returns `{ id, tier, granted_at }` on success.
- `apps/web-platform/app/api/scope-grants/revoke/route.ts` — POST handler. Inlines `.rpc("revoke_action_class", { p_action_class, p_reason })`. Returns `{ rows_revoked }`.

Both routes emit Sentry breadcrumbs per TR9 (`scope.grant.created`, `scope.grant.revoked`).

Per `cq-nextjs-route-files-http-only-exports`: route files export only HTTP verbs + dynamic config; no helper functions.

#### 3.3 Settings nav entry

Edit `apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx` (or similar nav file): add "Scope Grants" entry. **Verify path at /work time** — read the actual settings layout to confirm the nav-entry pattern.

#### 3.4 Sentry breadcrumb integration

Per TR9, each grant/revoke RPC call emits structured breadcrumb. Use existing `reportSilentFallback` / Sentry mirror pattern from `server/observability.ts`. Do NOT introduce a new helper — reuse the established surface.

**Phase 3 exit:** founder can grant/revoke `finance.payment_failed` end-to-end against `dev` Supabase; Sentry breadcrumbs visible; pessimistic UI behavior validated manually.

### Phase 4 — Audit-log viewer (both sections)

Goal: founder-facing `/dashboard/audit` rendering `audit_byok_use` + Inngest run history with redacted authorizing-event summary.

#### 4.1 BYOK section

File: `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` — server component.

Fetches via cookie-scoped Supabase client per `app/api/dashboard/today/route.ts` precedent:

```typescript
const supabase = await createClient(); // cookie-scoped, RLS-bounded
const { data: { user } } = await supabase.auth.getUser();
if (!user) redirect("/login");

// Belt-and-suspenders: .eq("founder_id", user.id) defends against any
// future RLS loosening on audit_byok_use. Comment cites the protection
// reason per today/route.ts precedent (lines TBD — verify at /work).
const { data: byokRows } = await supabase
  .from("audit_byok_use")
  .select("ts, agent_role, token_count, unit_cost_cents")
  .eq("founder_id", user.id)
  .order("ts", { ascending: false })
  .limit(50);
```

Pagination via cursor (`?page=2` reads `?cursor=<ts>` and applies `.lt("ts", cursor)`).

#### 4.2 Inngest section

File: `apps/web-platform/app/api/dashboard/runs/route.ts` — server-only proxy.

```typescript
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { listInngestRunsForFounder } from "@/lib/inngest/list-runs";

export async function GET(req: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new NextResponse("unauthorized", { status: 401 });

  try {
    const runs = await listInngestRunsForFounder({
      founderId: user.id,
      limit: 50,
    });
    return NextResponse.json({ runs });
  } catch (e) {
    // Sentry alert per FR8. Surface a 502 to the client so the audit
    // viewer can degrade gracefully (Inngest panel error card, BYOK
    // panel unaffected — partial degradation per spec-flow finding).
    Sentry.captureException(e, { tags: { surface: "audit-runs-proxy" } });
    return new NextResponse("inngest_api_error", { status: 502 });
  }
}
```

File: `apps/web-platform/lib/inngest/list-runs.ts` — server-only helper.

```typescript
// PR-G (#3947) — Server-only Inngest HTTP API proxy. INNGEST_SIGNING_KEY
// is the read-API auth credential (event key is write-only for SDK
// ingestion). Self-hosted Inngest exposes /v1/* at INNGEST_BASE_URL.

const BASE_URL = process.env.INNGEST_BASE_URL;
const SIGNING_KEY = process.env.INNGEST_SIGNING_KEY;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface ListRunsParams {
  founderId: string;
  limit: number;
}

export async function listInngestRunsForFounder({
  founderId,
  limit,
}: ListRunsParams): Promise<RunSummary[]> {
  // Defense-in-depth env-guard. Doppler drift would otherwise surface
  // as a cryptic URL/fetch error.
  if (!BASE_URL) throw new Error("INNGEST_BASE_URL not set");
  if (!SIGNING_KEY) throw new Error("INNGEST_SIGNING_KEY not set");

  // UUID shape check before composing the CEL filter. founderId is
  // sourced from supabase.auth.getUser() today (UUID-shaped), but the
  // helper is exported — defend against future callers passing
  // user-controlled data into a CEL string interpolation (Kieran P1-2).
  if (!UUID_RE.test(founderId)) {
    throw new Error("invalid founderId shape");
  }

  // Step 1: list events whose data.founderId == this founder.
  // CEL filter is the canonical Inngest 2026 path per best-practices research.
  const eventsUrl = new URL("/v1/events", BASE_URL);
  eventsUrl.searchParams.set("name", "finance.payment_failed");
  eventsUrl.searchParams.set("cel", `event.data.founderId=='${founderId}'`);
  eventsUrl.searchParams.set("limit", String(limit));

  const eventsRes = await fetch(eventsUrl, {
    headers: { Authorization: `Bearer ${SIGNING_KEY}` },
  });
  if (!eventsRes.ok) {
    throw new Error(`inngest_api_error: ${eventsRes.status}`);
  }
  const events = (await eventsRes.json()).data as InngestEvent[];

  // Step 2: fan out to runs per event.
  const runs: RunSummary[] = [];
  for (const event of events) {
    const runsUrl = new URL(`/v1/events/${event.id}/runs`, BASE_URL);
    const runsRes = await fetch(runsUrl, {
      headers: { Authorization: `Bearer ${SIGNING_KEY}` },
    });
    if (!runsRes.ok) continue; // partial: one event's runs may 404
    const eventRuns = (await runsRes.json()).data as InngestRun[];
    for (const run of eventRuns) {
      // Return raw (masked) customer-id, NOT the formatted string.
      // Single-source-of-truth: `redacted-event-summary.tsx` is the
      // SOLE site that composes the user-facing summary text.
      // (Kieran P2-2 + Code Simplicity #3 cleanup.)
      runs.push({
        id: run.id,
        startedAt: run.started_at,
        endedAt: run.ended_at,
        status: run.status,
        actionClass: "finance.payment_failed",
        tierAtTimeOfEvent: event.data.tier, // pin grant-tier-at-time
        // Mask server-side so we never ship the raw customer_id to client.
        customerIdMasked: maskCustomerId(event.data.customerId),
      });
    }
  }

  return runs;
}

function maskCustomerId(id: string | undefined): string {
  if (!id || id.length < 4) return "cus_***";
  return `${id.slice(0, 4)}***`;
}
```

#### 4.3 Components

**Collapsed from 6 component files to 2 per code-simplicity + DHH review.** BYOK and Inngest sections share the same row shape — merged into one `<AuditSections source={...}>`. Page composition + empty state inlined into `page.tsx`. Mailto: anchor inlined into row (FR15, no separate modal file).

- `apps/web-platform/components/audit/audit-sections.tsx` — single component taking `source: "byok" | "inngest"` prop. Renders the section header, paginated row list, error card (Inngest 5xx → degrade to error state; BYOK section unaffected). Each Inngest row inlines: `<RedactedEventSummary masked={row.customerIdMasked} eventName={row.actionClass} />` + a plain `<a href="mailto:legal@jikigai.com?subject=...&body=...">` for the request-review affordance + a `<Link href="/dashboard/settings/scope-grants">` for "Change authorization →".
- `apps/web-platform/components/audit/redacted-event-summary.tsx` — single source of truth for the `authorizing_event` user-facing string. Composes `"Stripe invoice.payment_failed for {masked}"` from the server-supplied masked id. Lint guard (AC10) ensures no other component constructs this string.

#### 4.4 Server-only enforcement (TR7)

File: `apps/web-platform/test/lint/inngest-key-server-only.test.ts`

```typescript
// PR-G (#3947) — Lint test: INNGEST_SIGNING_KEY must not appear in any
// file under app/(dashboard)/ or components/. Server-only.

import { glob } from "glob";
import { readFile } from "node:fs/promises";
import { describe, expect, it } from "bun:test";

describe("INNGEST_SIGNING_KEY server-only enforcement", () => {
  it("does not appear in client-bundle paths", async () => {
    const files = await glob([
      "apps/web-platform/app/(dashboard)/**/*.{ts,tsx}",
      "apps/web-platform/components/**/*.{ts,tsx}",
    ]);
    const violations: string[] = [];
    for (const file of files) {
      const content = await readFile(file, "utf8");
      if (content.includes("INNGEST_SIGNING_KEY")) {
        violations.push(file);
      }
    }
    expect(violations).toEqual([]);
  });
});
```

**Phase 4 exit:** `/dashboard/audit` renders for a seeded founder with mixed BYOK + Inngest rows; cross-tenant probe returns zero rows; Inngest API 502 simulated and partial-degradation rendered correctly.

### Phase 5 — Onboarding explainer banner

Goal: dismissable first-run banner on Today section.

#### 5.1 Widen `useOnboarding` hook union

Per `cq-union-widening-grep-three-patterns` and `hr-type-widening-cross-consumer-grep`:

Edit `apps/web-platform/hooks/use-onboarding.ts:48`:

```typescript
// Before:
.select("onboarding_completed_at, pwa_banner_dismissed_at")
// After:
.select("onboarding_completed_at, pwa_banner_dismissed_at, runtime_explainer_dismissed_at")
```

Widen `updateUserField`'s typed field union. Run `tsc --noEmit` and chase every TS2322 / TS2345 — fix each by widening the consumer.

#### 5.2 Banner component

File: `apps/web-platform/components/dashboard/runtime-explainer-banner.tsx`

Three beats per FR10:
1. **What runs while you sleep** — names the action classes currently grant-able (from `ACTION_CLASSES`).
2. **You authorize each class explicitly** — links to `/dashboard/settings/scope-grants`.
3. **Budget disclosure** — uses existing `RUNTIME_COST_DISCLOSURE` constant from `lib/legal/disclosures.ts`.

Visual: mirror `apps/web-platform/components/dashboard/today-banner.tsx` (existing precedent — same gold-accent + dismiss-X pattern per ux-design-lead wireframe).

#### 5.3 Mount in Today section

Edit `apps/web-platform/app/(dashboard)/dashboard/page.tsx:591-606`: insert `<RuntimeExplainerBanner />` above the existing `<TodayBanner />` (or merge into the existing banner if visual cohesion warrants — defer to /work time after reading the actual page structure).

**Phase 5 exit:** banner renders for users with `runtime_explainer_dismissed_at IS NULL`; dismiss persists; banner does not re-show after dismiss; `tsc --noEmit` clean.

### Phase 6 — Art. 22(3) human-review affordance (FR15 + FR16)

Goal: surface the "request human review" path per Art. 22(3) — promoted to FR from spec-flow-analyzer critical gap.

#### 6.1 Audit-row affordance (inlined)

**No separate component file** (DHH P2.2 + code-simplicity review). Each Inngest row in `<AuditSections source="inngest">` inlines a plain `<a href="mailto:legal@jikigai.com?subject=...&body=...">` with `encodeURIComponent`-wrapped subject + body. Subject: `"Request human review: <actionClass> (<runId>)"`. Body: `"I'd like a human to review this automated action.\n\nRun: <runId>\nAction class: <actionClass>\nTier at time: <tier>\n\n[Your perspective]"`.

Per CLO advisory: closed-preview channel is `legal@jikigai.com`. Per best-practices research: ≤1 click from decision surface, plain language; the audit trail is the email inbox + outbound reply (sufficient for closed-preview cohort).

#### 6.2 Cross-surface "Change authorization" link (inlined)

In `audit-sections.tsx`, each Inngest run row inlines `<Link href="/dashboard/settings/scope-grants">Change authorization →</Link>` adjacent to the mailto: link. Per spec-flow finding.

#### 6.3 Inline acknowledgement on `auto` selection (FR6 amendment)

Already covered in Phase 3.1 — `<ScopeGrantRow>` reveals confirmText from `TRUST_TIER_COPY.auto.confirmText` and disables submit until checked.

**Phase 6 exit:** Art. 22(3) affordance reachable in ≤1 click from any audit row; CLO sign-off on copy.

### Phase 7 — Legal doc amendments (4 amendments × 2 mirror paths = 8 files)

Goal: ship the four legal-doc amendments alongside the enforcement UX.

#### 7.1 Files to edit

For each amendment, edit BOTH locations:

1. **ToS §3a "Agent Command Authority" (new section)**
   - `docs/legal/terms-and-conditions.md`
   - `plugins/soleur/docs/pages/legal/terms-and-conditions.md`

   Per CLO carry-forward: bind (a) grant scope = drafts only unless explicitly upgraded, (b) revocation takes effect before next trigger, (c) Soleur is not an agent-in-fact for third parties, (d) BYOK cost cap is the founder's ceiling. Tighten existing §9 to cross-reference §3a.

2. **AUP "Automated agent actions taken on your behalf" (new section)**
   - `docs/legal/acceptable-use-policy.md`
   - `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`

   Founder remains responsible for sends derived from drafts; circumventing the Send/Edit/Discard human-in-the-loop boundary violates AUP §(c).

3. **Privacy Policy Art. 22 disclosure (new section)**
   - `docs/legal/privacy-policy.md`
   - `plugins/soleur/docs/pages/legal/privacy-policy.md`

   Mirror ToS §9 + link to DPD §2.3(o). Remove or amend the "Buttondown does not involve automated decision-making" line (now misleading once PR-G ships).

4. **DPD §2.3(o) extension**
   - `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
   - `docs/legal/data-protection-disclosure.md`

   Enumerate the new processing surfaces: `scope_grants` ledger, `/dashboard/audit` viewer. Re-confirm Inngest self-hosted (no new sub-processor).

#### 7.2 Copy review

Copywriter NOT invoked (no domain leader recommended; CLO carried forward). CLO sign-off captured in PR body via `gh pr edit` adding a comment with the 4 file paths.

**Phase 7 exit:** all 4 amendments × 2 paths = 8 files edited; eleventy build passes (`bun run docs:build`).

### Phase 8 — T&C version bump + enforcement-surface parity sweep

Goal: bump `TC_VERSION`; verify every enforcement surface (middleware, auth callback, ws-handler, onboarding flow) uses the same `tc_accepted_version !== TC_VERSION` comparison.

#### 8.1 Bump constant

Edit `apps/web-platform/lib/legal/tc-version.ts`: increment version per `knowledge-base/legal/tc-version-bump-policy.md` rubric (read the policy to determine major/minor/patch — likely major because legal doc semantics changed). Compute new `document_sha` for each of the 4 amended docs (used by `tc_acceptances.document_sha` CHECK).

#### 8.2 Enforcement-surface parity grep

Per `2026-03-20-tc-version-enforcement-surface-parity.md`:

```bash
git grep -nE "tc_accepted_version|tc_accepted_at|TC_VERSION" apps/web-platform/ \
  | grep -v "\.test\." \
  | sort > /tmp/tc-enforcement-sites.txt
```

For each site, verify the comparison is `!== TC_VERSION` (not `IS NULL`). Surfaces that historically diverged: middleware, auth callback, ws-handler, onboarding flow. List in plan body for /work to grep.

#### 8.3 Re-acceptance flow validation

The version bump triggers re-acceptance for ALL existing users (middleware redirects to `/accept-terms` on next request). For PR-G: this is the operator + 1 dogfood founder. Document in PR body: re-acceptance is expected behavior for the version bump.

**Phase 8 exit:** TC_VERSION bumped; document_shas updated; enforcement-surface parity verified.

### Phase 9 — Cross-tenant denial + lifecycle tests (TR2, TR4)

Goal: prove brand-survival threshold via tests.

Files:

- `apps/web-platform/test/server/scope-grants/cross-tenant-read-denied.test.ts` (TR2):
  - Seed two users (A, B) via service-role.
  - Insert grant for A; insert `audit_byok_use` rows for both A and B; trigger one Inngest run for each.
  - Authenticated as A, query `/api/dashboard/runs` AND `scope_grants` AND `audit_byok_use` — assert zero rows of B's data in each response.
  - Use `crypto.randomUUID()` for synthetic IDs (per `2026-05-16-rls-deny-tests-payload-must-type-validate.md` — `randomBytes(16).toString("hex")` causes `22P02` type-cast errors before RLS evaluates).

- `apps/web-platform/test/server/scope-grants/lifecycle.test.ts` (TR4):
  - Grant fresh → assert row count = 1, active.
  - Re-grant same class at different tier → assert prior row has `revoked_at`, new row active.
  - Revoke → assert active row has `revoked_at`, total row count = 2 (no DELETE).
  - Re-grant after revoke → assert new active row, total = 3.
  - Assert UPDATE on non-revoke columns rejected (WORM trigger fires).
  - Assert DELETE rejected (WORM trigger fires).

- (denylist behavior is covered in the webhook test TR5; standalone denylist.test.ts deleted per code-simplicity review — it would only assert "the mock works".)

- `apps/web-platform/test/server/scope-grants/account-delete-scope-grants-cascade.test.ts`:
  - Assert `anonymise_scope_grants` runs BEFORE `anonymise_tc_acceptances`.
  - Assert account-delete aborts if cascade RPC fails.

**Phase 9 exit:** all new tests green via `bun test apps/web-platform/test/server/scope-grants/` and via `bun test apps/web-platform/test/lint/`.

### Phase 10 — Documentation + ADR

#### 10.1 ADR-031

File: `knowledge-base/engineering/architecture/decisions/ADR-031-per-tenant-scope-grants.md`

Sibling to ADR-030 (Inngest as durable trigger layer). Captures:
- Context (cohort exposure requires per-tenant gate; env flag alone is insufficient)
- Decision (Supabase `scope_grants` table + SECURITY DEFINER RPCs + RLS self-select)
- Rejected alternatives (Doppler config, in-process registry, JWT claim)
- Consequences (forensic audit trail, revoke-via-column-flip, cascade cost on user delete, future denylist via code constant)

#### 10.2 Runbook update

Edit `knowledge-base/engineering/ops/runbooks/inngest-server.md`: append PR-G flip section.

```markdown
## PR-G post-merge: Flipping SOLEUR_FR5_ENABLED to true

Prerequisites (all must be true before flip):
1. PR-G merged to main; Vercel auto-deploy green.
2. Migrations 048 + 049 applied to prd Supabase (verify via `psql -c "\d+ scope_grants"`).
3. T&C version bump deployed; all enforcement surfaces verified.
4. BetterStack on-call live (per PR-F flip-prerequisite list).
5. Synthetic Stripe smoke against prd webhook passed (see §Synthetic smoke below).
6. CPO sign-off captured in PR body.
7. First dogfood founder selected and onboarding ready (out of scope for PR-G content).

Flip command:
\`\`\`bash
doppler secrets set SOLEUR_FR5_ENABLED=true -p soleur -c prd
\`\`\`

Roll-back command (if first invocation surfaces a regression):
\`\`\`bash
doppler secrets set SOLEUR_FR5_ENABLED=false -p soleur -c prd
\`\`\`

Synthetic smoke procedure (one-off operator command — no separate script file per code-simplicity review):

\`\`\`bash
# Replace <founder-uuid> with the seeded grant's founder_id.
STRIPE_PAYLOAD=$(jq -n --arg fid "<founder-uuid>" '{type: "invoice.payment_failed", data: {object: {customer: "cus_smoke", invoice_id: "in_smoke"}}}')

SIG="t=$(date +%s),v1=$(printf '%s' "$STRIPE_PAYLOAD" | openssl dgst -sha256 -hmac "$STRIPE_WEBHOOK_SECRET" -hex | awk '{print $2}')"

curl -sS -X POST "https://app.soleur.ai/api/webhooks/stripe" \\
  -H "Stripe-Signature: $SIG" -H "Content-Type: application/json" -d "$STRIPE_PAYLOAD"

# Wait ~5s, then query Inngest:
curl -sS -H "Authorization: Bearer $INNGEST_SIGNING_KEY" \\
  "$INNGEST_BASE_URL/v1/events?name=finance.payment_failed&cel=event.data.founderId=='<founder-uuid>'&limit=1"
\`\`\`
```

#### 10.3 Article 30 register

Edit `knowledge-base/legal/article-30-register.md`: add new processing activity row "Scope Grants" — purpose (per-action-class authorization), categories of data (founder_id, action_class, tier), retention (indefinite — append-only ledger), legal basis (Art. 6(1)(b) contract; Art. 22 affordance).

**Phase 10 exit:** ADR + runbook + Art. 30 entries land in same commit.

### Phase 11 — CI green + plan-review pass + final commit

Goal: all checks green, draft PR ready for review.

- [ ] 11.1 `bun test` all green (web-platform suite + lint test).
- [ ] 11.2 `bun run typecheck` clean.
- [ ] 11.3 `bun run lint` clean.
- [ ] 11.4 `bun run docs:build` green (eleventy build passes for legal doc amendments).
- [ ] 11.5 Run `/soleur:preflight` per `hr-before-shipping-ship-phase-5-5-runs`.
- [ ] 11.6 Run `/soleur:gdpr-gate` final pass (re-confirm Phase 0.7 findings remain addressed).
- [ ] 11.7 Mark PR #3984 ready for review: `gh pr ready 3984`.
- [ ] 11.8 Per `wg-after-marking-a-pr-ready-run-gh-pr-merge`: enable auto-merge with squash.

### Phase 12 — Post-merge operator actions (NOT in PR scope)

> Per Sharp Edge "When a PR has post-merge operator actions, split AC into `### Pre-merge` and `### Post-merge (operator)`." These are NOT acceptance criteria for the PR itself — they are operator-execution steps that follow merge.

- [ ] 12.1 (operator) Verify migrations 048 + 049 applied to prd Supabase: `psql -c "\d+ scope_grants"` returns expected shape.
- [ ] 12.2 (operator) Manually seed operator's `scope_grants` row in prd (one row for `finance.payment_failed` at `draft_one_click` tier) so the predicate has a non-empty allowlist for the dry-run. Then briefly toggle `SOLEUR_FR5_ENABLED=true` in a non-prd preview env and fire a synthetic Stripe `invoice.payment_failed` event; assert Inngest dashboard shows the new event AND the predicate would have routed correctly (per Kieran P2-4 — the original POST-2 of "fire against prd with flag=off" proved nothing because the flag short-circuit precedes `isGranted`).
- [ ] 12.3 (operator) Capture CPO sign-off + first dogfood founder selection in `knowledge-base/legal/compliance-posture.md` Active Items.
- [ ] 12.4 (operator, GATE) Flip flag: `doppler secrets set SOLEUR_FR5_ENABLED=true -p soleur -c prd`. Automation: not feasible because cohort go-live is a subjective brand-survival risk assessment requiring CPO sign-off + first dogfood founder selection.
- [ ] 12.5 (operator) Within 1h of 12.4: fire a synthetic Stripe `invoice.payment_failed` against prd via the snippet in `inngest-server.md` runbook; assert Inngest dashboard shows the run; assert founder's `/dashboard/audit` renders it.
- [ ] 12.6 (operator) Close #3947 with `gh issue close 3947 --reason completed` (NOT auto-closed via `Closes #N`; the actual completion gate is the post-merge flip, not PR merge).
- [ ] 12.7 (operator) `/soleur:postmerge` to verify production health.

## Files to Edit

| Path | Change | Phase |
|------|--------|-------|
| `apps/web-platform/app/api/webhooks/stripe/route.ts` | Lines 428-466: predicate `flag && customerId` → `flag && customerId && founderId && isGranted(...) && !isDenied(...)`; pass `tier` in `inngest.send` data. | 2 |
| `apps/web-platform/server/account-delete.ts` | Lines 200-230: insert `anonymise_scope_grants` cascade BEFORE `anonymise_tc_acceptances`. Match `reportSilentFallback` signature against `server/observability.ts` (verify at /work per Kieran P1-6). | 1.4 |
| `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` | Lines 12-13 RV4: replace inlined `ACTION_CLASS_DEFAULTS` constant with import from `server/scope-grants/action-class-map.ts`. Per `hr-type-widening-cross-consumer-grep`: grep all consumers of the constant before swap. | 1.3 |
| `apps/web-platform/hooks/use-onboarding.ts` | Lines 48, 55-56, 66-75: widen union to include `runtime_explainer_dismissed_at`; add `runtimeExplainerDismissed` state + setter. | 5.1 |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | Lines 591-606: mount `<RuntimeExplainerBanner />` above Today section. | 5.3 |
| `apps/web-platform/app/(dashboard)/dashboard/settings/layout.tsx` | Add "Scope Grants" nav entry. | 3.3 |
| `apps/web-platform/lib/legal/tc-version.ts` | Bump TC_VERSION constant; update document_sha values for amended docs. | 8.1 |
| `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts` | Add precondition test (TR3) + denylist test (TR5) + grant-path test cases. | 2.2, 2.3 |
| `docs/legal/terms-and-conditions.md` | New §3a "Agent Command Authority"; tighten existing §9. | 7.1 |
| `plugins/soleur/docs/pages/legal/terms-and-conditions.md` | Mirror of above. | 7.1 |
| `docs/legal/acceptable-use-policy.md` | New "Automated agent actions taken on your behalf" section. | 7.1 |
| `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` | Mirror of above. | 7.1 |
| `docs/legal/privacy-policy.md` | Art. 22 disclosure; remove/amend "no automated decision-making" line. | 7.1 |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | Mirror of above. | 7.1 |
| `docs/legal/data-protection-disclosure.md` | §2.3(o) extension (scope_grants ledger + audit viewer surfaces). | 7.1 |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Mirror of above. | 7.1 |
| `knowledge-base/engineering/ops/runbooks/inngest-server.md` | Append "PR-G post-merge: Flipping SOLEUR_FR5_ENABLED" section. | 10.2 |
| `knowledge-base/legal/article-30-register.md` | Add "Scope Grants" processing activity row. | 10.3 |
| `knowledge-base/legal/compliance-posture.md` | Update Active Items with PR-G findings from gdpr-gate (Phase 0.7). | 0.7 |

## Files to Create

| Path | Purpose | Phase |
|------|---------|-------|
| `apps/web-platform/supabase/migrations/048_scope_grants.sql` | Table + RLS + WORM triggers + RPCs. | 1.1 |
| `apps/web-platform/supabase/migrations/049_runtime_explainer_state.sql` | `users.runtime_explainer_dismissed_at` column. | 1.2 |
| `apps/web-platform/server/scope-grants/action-class-map.ts` | Canonical `ACTION_CLASSES` + `ACTION_CLASS_DEFAULTS` map. | 1.3 |
| `apps/web-platform/server/scope-grants/is-granted.ts` | Webhook predicate's grant probe + inlined empty denylist. | 1.3 |
| `apps/web-platform/lib/messages/trust-tier-copy.ts` | Single-source trust-tier labels + descriptions + confirmText. | 1.5 |
| `apps/web-platform/lib/inngest/list-runs.ts` | Server-only Inngest HTTP API client + UUID shape check. | 4.2 |
| `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` | Scope-grant settings page; inlines list iteration + empty state. | 3.1 |
| `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` | Audit viewer page; inlines page composition + empty state. | 4.1 |
| `apps/web-platform/app/api/scope-grants/grant/route.ts` | POST route inlining `grant_action_class` RPC call. | 3.2 |
| `apps/web-platform/app/api/scope-grants/revoke/route.ts` | POST route inlining `revoke_action_class` RPC call. | 3.2 |
| `apps/web-platform/app/api/dashboard/runs/route.ts` | Server-only Inngest proxy. | 4.2 |
| `apps/web-platform/components/scope-grants/scope-grant-row.tsx` | Three-radio tier picker with auto-confirm acknowledgement (pessimistic UI). | 3.1 |
| `apps/web-platform/components/audit/audit-sections.tsx` | Merged BYOK + Inngest section component (`source` prop); inlines mailto: + change-auth links per row. | 4.3, 6.1, 6.2 |
| `apps/web-platform/components/audit/redacted-event-summary.tsx` | SOLE site composing the masked authorizing_event user-facing string. | 4.3 |
| `apps/web-platform/components/dashboard/runtime-explainer-banner.tsx` | Three-beat onboarding banner. | 5.2 |
| `apps/web-platform/test/server/scope-grants/cross-tenant-read-denied.test.ts` | TR2 — cross-tenant denial + founderId-typo regression. | 9 |
| `apps/web-platform/test/server/scope-grants/lifecycle.test.ts` | TR4 — grant/revoke lifecycle. | 9 |
| `apps/web-platform/test/server/scope-grants/account-delete-scope-grants-cascade.test.ts` | FR17 cascade ordering. | 9 |
| `apps/web-platform/test/lint/inngest-key-server-only.test.ts` | TR7 — server-only enforcement. | 4.4 |
| `knowledge-base/engineering/architecture/decisions/ADR-031-per-tenant-scope-grants.md` | Architectural decision record. | 10.1 |
| `knowledge-base/product/design/scope-grants/pr-g-cohort-onboarding.pen` | ux-design-lead wireframe (already created during plan phase). | (done) |
| `knowledge-base/product/design/scope-grants/screenshots/*.png` | 6 wireframe screenshots (already created). | (done) |

**Total new files: 19** (down from 30 in plan v1 per code-simplicity + DHH review). Files cut: `server/scope-grants/denylist.ts`, `server/scope-grants/grant-rpc.ts`, `components/scope-grants/scope-grant-list.tsx`, `components/scope-grants/scope-grant-empty-state.tsx`, `components/audit/audit-page.tsx`, `components/audit/audit-empty-state.tsx`, `components/audit/byok-section.tsx`, `components/audit/inngest-section.tsx`, `components/audit/request-review-modal.tsx`, `test/server/scope-grants/denylist.test.ts`, `scripts/smoke-stripe-payment-failed.ts`. Behaviors preserved (denylist reject, list iteration, empty state, BYOK+Inngest sections, mailto: link, smoke procedure) — all inlined into surviving files or moved to runbook snippet.

## Open Code-Review Overlap

**None.** The Phase 1.7.5 grep across 74 open code-review issues returned zero matches for any of PR-G's planned files. No fold-in, acknowledge, or defer required.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Inngest REST API path differs from `/v1/*` on installed self-hosted version | Medium | High (Inngest section breaks) | Phase 0.5 probe MUST pass before Phase 4 begins; if 404, pivot to `/v0/*` or GraphQL. |
| Migration 048 deploy ordering: webhook code references `scope_grants` before migration applies | Medium | High (5xx on first prod request) | Standard Supabase deploy ordering — Vercel deploy hook waits for migration apply. Document in runbook. |
| K14 flip-in-PR-G: per-grant deny-by-default is the SOLE safety primitive | High | Critical (single-user incident) | TR3 precondition test MUST pass on main; synthetic smoke before AND after flip; CPO sign-off captured. |
| T&C re-acceptance forces operator + 1 dogfood founder out at first request post-merge | High (intended) | Low (small cohort) | Document in PR body as expected behavior; coordinate dogfood timing. |
| Inngest API rate-limited under load (audit viewer polls aggressively) | Low | Medium (Inngest section degrades) | Cap at 50 runs per page; Sentry alert on 5xx per FR8; client-side caches results for 30s. |
| Server Action / route handler ambiguity in Next.js 15 | Low | Medium (refactor cost) | Use route handlers (`/api/scope-grants/*/route.ts`) — established pattern in this codebase per today/route.ts. |
| Onboarding hook union widening cascades to unseen consumers | Medium | Low | `tsc --noEmit` enumerates every TS2322; widen consumers per `cq-union-widening-grep-three-patterns`. |
| Audit viewer leaks `customerEmailHash` if redaction summary is bypassed | Low | Critical (PII exposure) | `redacted-event-summary.tsx` is the SOLE renderer; lint test asserts no raw `event.data.customerId` in JSX of `components/audit/`. |
| Founder confused by "revoke effective next trigger only" semantics in flight | Medium | Low (UX friction) | Copy in TRUST_TIER_COPY.auto.confirmText explicitly names this; NG8 defers in-flight cancellation semantics. |
| Cross-tenant `account-delete` cascade race: `anonymise_scope_grants` fails after `anonymise_tc_acceptances` succeeds | Low | Medium (orphaned state) | Cascade aborts on first error (existing pattern at account-delete.ts:214); cascade ordering puts scope_grants FIRST. |

## Acceptance Criteria

### Pre-merge (PR)

> Cut from 22 to 14 per code-simplicity + DHH review. Removed paraphrase-of-phase ceremony (own-diff greps, hr-mandated preflight repeats, PR-body-hygiene as ACs). Kept ACs that encode load-bearing post-condition gates.

- [ ] **AC1** Migrations 048 + 049 applied locally; `psql -c "\d+ public.scope_grants"` shows table + RLS + WORM triggers + 3 RPCs with explicit `REVOKE EXECUTE FROM PUBLIC, anon` + `GRANT EXECUTE` to the correct role (`authenticated` for grant/revoke; `service_role` for `anonymise_scope_grants`); `\d users` shows `runtime_explainer_dismissed_at`.
- [ ] **AC2** Precondition test (TR3) passes: `bun test apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts -t "does NOT call inngest.send when SOLEUR_FR5_ENABLED=true and no scope_grants row"` exits 0. Includes denylist-gate test and grant-path test with tier pass-through.
- [ ] **AC3** Cross-tenant denial test (TR2) passes including **founderId-typo regression** case (per Kieran P1-3): swap founderId mid-flow → returns null (no leak). All assertions use `crypto.randomUUID()` for synthetic IDs.
- [ ] **AC4** Lifecycle test (TR4) passes: grant, re-grant (tier change), revoke, re-grant after revoke; WORM invariants (UPDATE on non-revoke columns + DELETE rejected).
- [ ] **AC5** Account-delete cascade test passes: `anonymise_scope_grants` runs BEFORE `anonymise_tc_acceptances`; cascade aborts on RPC failure.
- [ ] **AC6** Server-only `INNGEST_SIGNING_KEY` lint test passes (TR7): `bun test apps/web-platform/test/lint/inngest-key-server-only.test.ts` exits 0.
- [ ] **AC7** `/dashboard/settings/scope-grants` renders end-to-end: founder grants `finance.payment_failed` at `draft_one_click`; revokes; auto-tier confirmation interaction prevents one-click writes (pessimistic UI verified manually).
- [ ] **AC8** `/dashboard/audit` renders BYOK section (paginated) + Inngest section (capped 50). `redacted-event-summary.tsx` is the SOLE renderer of the masked summary; grep `grep -rE "customerId|customerEmailHash|invoice_email" apps/web-platform/components/audit/ | grep -v redacted-event-summary.tsx | grep -v '\.test\.'` returns zero matches.
- [ ] **AC9** Audit row inlines BOTH mailto: ("Request human review →") AND `/dashboard/settings/scope-grants` ("Change authorization →") affordances per FR15/FR16.
- [ ] **AC10** Onboarding banner renders when `runtime_explainer_dismissed_at IS NULL`; dismiss persists; does not re-show.
- [ ] **AC11** All 4 legal-doc amendments × 2 mirror paths = 8 file edits applied; `bun run docs:build` green; TC_VERSION bumped; `document_sha` values match amended docs.
- [ ] **AC12** Enforcement-surface parity grep documented in PR body: `git grep -nE "tc_accepted_version|TC_VERSION" apps/web-platform/ | grep -v '\.test\.'` enumerated; every site uses `!== TC_VERSION` (not null-check).
- [ ] **AC13** ADR-031 + runbook PR-G section + Article 30 "Scope Grants" row all land in same commit as code.
- [ ] **AC14** CI green: `bun test`, `bun run typecheck`, `bun run lint` all exit 0; CPO sign-off captured in PR body or linked compliance-posture entry (single-user-incident threshold).

### Post-merge (operator)

- [ ] **POST-1** Migrations 048 + 049 verified applied on prd: `psql` against prd Supabase shows table + column exist with expected shape (RLS enabled, WORM triggers present, 3 RPCs registered).
- [ ] **POST-2** (rewritten per Kieran P2-4 — the original "fire against prd with flag=false" proved nothing because the flag short-circuit precedes `isGranted`.) Manually seed operator's own `scope_grants` row in prd at `draft_one_click` tier; in a non-prd preview env (Vercel preview deploy), briefly toggle `SOLEUR_FR5_ENABLED=true` and fire the synthetic Stripe event from the runbook snippet; assert Inngest dashboard shows the new event AND the predicate routed (grant honored). Revert the preview-env toggle.
- [ ] **POST-3** CPO sign-off + first dogfood founder identity captured in compliance-posture.md Active Items.
- [ ] **POST-4** Doppler `prd` `SOLEUR_FR5_ENABLED=true` set via `doppler secrets set`; verified via `doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain`.
- [ ] **POST-5** Within 1h of POST-4: synthetic Stripe smoke fired against prd via runbook snippet; Inngest dashboard shows the run; operator's `/dashboard/audit` renders it; no 5xx on `/api/dashboard/runs`.
- [ ] **POST-6** `gh issue close 3947 --reason completed` (manual closure — PR body uses `Ref #3947`, not `Closes`, per ops-remediation class Sharp Edge).
- [ ] **POST-7** `/soleur:postmerge` verification passes.

## Test Plan

> Per `hr-dev-prd-distinct-supabase-projects`: all integration tests run against `dev` Supabase; never `prd`. Test fixtures synthesized only (`cq-test-fixtures-synthesized-only`).

### Inngest API probe (Phase 0.5)

Against `dev` Doppler:

```bash
doppler run -p soleur -c dev -- bash -c '
  curl -sS -H "Authorization: Bearer $INNGEST_SIGNING_KEY" \
    "$INNGEST_BASE_URL/v1/events?name=finance.payment_failed&limit=1"
'
```

**Verified:** 2026-05-18 — output captured at /work time.
**Source:** Inngest REST API docs (https://inngest.rest/) confirmed `/v1/events` path for 2026-current.

### Unit + integration tests

| Test file | Phase | Tests |
|-----------|-------|-------|
| `test/server/webhooks/stripe-payment-failed-inngest.test.ts` | 2 | TR3 (no grant → no send), TR5 (denylist → no send), grant-path (flag+grant+not-denied → send with tier), tier passes through to event.data |
| `test/server/scope-grants/cross-tenant-read-denied.test.ts` | 9 | TR2 — founder A queries scope_grants/audit_byok_use/runs proxy, asserts zero rows of founder B's data; **+ founderId-typo regression** (Kieran P1-3) |
| `test/server/scope-grants/lifecycle.test.ts` | 9 | TR4 — grant, re-grant (tier change), revoke, re-grant after revoke; WORM invariants (UPDATE/DELETE rejection) |
| `test/server/scope-grants/account-delete-scope-grants-cascade.test.ts` | 9 | FR17 — `anonymise_scope_grants` runs before `anonymise_tc_acceptances`; abort on cascade failure |
| `test/lint/inngest-key-server-only.test.ts` | 4.4 | TR7 — `INNGEST_SIGNING_KEY` absent from `app/(dashboard)/**` and `components/**` |

### Manual QA

Per Phase 3, 4, 5, 6 exit criteria. Operator manually exercises:
- Grant → revoke → re-grant on `/dashboard/settings/scope-grants`
- Audit viewer with mixed BYOK + Inngest rows
- Auto-tier confirmation interaction (cannot submit without explicit acknowledgement)
- Banner first-render + dismiss + no-re-show
- Cross-tenant probe (founder B's dashboard shows zero of founder A's data)
- Inngest API failure simulation (Inngest section degrades; BYOK section unaffected)

## Sharp Edges

> Cut from 11 to 8 per code-simplicity review. Removed: pg_cron sweep note (no consumer ships); cascade-ordering note (FR17 + migration comment is sufficient); plain `tsc` reminder. Added: customer→founder lookup risk (hidden assumption surfaced by code-simplicity review).

- **K14 flip-in-PR-G**: the env flag is now a global kill-switch, NOT a per-tenant gate. The per-grant deny-by-default webhook predicate (Phase 2.1) is the SOLE load-bearing safety primitive at the brand-survival threshold. If AC2 (TR3 precondition test) fails or is silently disabled, every Stripe customer in prd triggers Inngest immediately upon the next webhook event. Plan-time mitigation: TR3 in CI; runbook (Phase 10.2) documents the flip prerequisites; POST-2 synthetic dry-run via preview env.
- **Migration 048 WORM trigger semantics**: the trigger function is `INVOKER` (not `SECURITY DEFINER`) so `current_user` reflects the calling role for the anonymise bypass. Bypass gate checks `current_user OR session_user` to handle Supabase's variable ownership patterns. Mirrors migration 044's reasoning. **If migration 044's role-gate check is broken under Supabase's actual ownership semantics, so is 048's — both rely on the same assumption.** Plan-time mitigation: AC5 cascade test exercises the path end-to-end.
- **Customer→founder lookup is the upstream cross-tenant risk the per-grant predicate cannot catch**: the webhook predicate `flag && grant_exists` runs AFTER `customerId` → `founderId` lookup via `users.stripe_customer_id`. If that lookup returns the WRONG founder (stale mapping, duplicate stripe_customer_id, account-merge bug), the predicate honors a grant for the wrong tenant. Per `hr-write-boundary-sentinel-sweep-all-write-sites`: ensure customer→founder lookup is RLS-protected at the source migration (verify at /work). A `unique` constraint on `users.stripe_customer_id` is the minimum invariant.
- **Supabase default privileges defeat REVOKE FROM PUBLIC**: every SECURITY DEFINER RPC needs explicit `REVOKE EXECUTE FROM PUBLIC, anon, authenticated` (not just `REVOKE ALL FROM PUBLIC`). Migration 048 enforces this; AC1 verifies via psql.
- **No backfill of historical grants** per brainstorm K16: alpha-internal pre-PR-G activity is pre-ledger. Do NOT INSERT historical rows for operator/dogfood; they grant fresh through the UX after PR-G ships.
- **Inngest API path drift**: the proxy depends on `/v1/events` + `/v1/events/{id}/runs`. If self-hosted Inngest version drift breaks the API contract, the audit viewer's Inngest section silently goes empty. Plan-time mitigation: Phase 0.5 probe; FR8 Sentry alert on 5xx.
- **T&C version bump is a high-blast-radius operation**: at first request post-merge, the operator + 1 dogfood founder are redirected to `/accept-terms` middleware. Coordinate dogfood timing.
- **Auto-tier acknowledgement is not optional UX polish**: it is the load-bearing UI primitive that makes "Soleur acts without your review" a deliberate-grant decision rather than a one-click slip. Per CPO advisory — single-user-incident threshold permits (and requires) friction here. DHH's plan-review argued this is "kabuki theater" and should ship one-click; **rejected** because the brand-survival threshold makes the friction load-bearing, not optional.
- **Per-grant deny-by-default at the webhook is service-role-context**: `is-granted.ts` reads via service-role (not RLS-bounded — the webhook has no founder JWT). The `.eq("founder_id", founderId)` is the load-bearing tenant filter, NOT belt-and-suspenders. A typo would leak across tenants. Comment at every call site explains this distinction. AC3 includes the founderId-typo regression test (per Kieran P1-3).

## Deferred to follow-up issues

- **Legal-doc mirror transclusion** (per DHH P1.3): currently `docs/legal/*.md` and `plugins/soleur/docs/pages/legal/*.md` are maintained as parallel copies. DHH argued for a single canonical source with Eleventy/plugin-build copy. Out of PR-G scope (would touch every legal doc, not just the 4 amendments). File tracking issue post-merge per `wg-when-deferring-a-capability-create-a` with re-evaluation criterion: "next legal change touches >1 doc, OR mirror drift is caught at review-time."

## References

- **Spec:** `knowledge-base/project/specs/feat-pr-g-cohort-onboarding/spec.md`
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-18-pr-g-cohort-onboarding-brainstorm.md`
- **Umbrella spec:** `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md`
- **PR-F plan:** `knowledge-base/project/plans/2026-05-18-feat-pr-f-inngest-iac-plan.md`
- **PR-F brainstorm (archived):** `knowledge-base/project/brainstorms/archive/20260517-203729-2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md`
- **ADR-030 (Inngest substrate):** `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`
- **T&C consent ledger precedent:** `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql`
- **Audit table precedent:** `apps/web-platform/supabase/migrations/037_audit_byok_use.sql`
- **Account-delete cascade pattern:** `apps/web-platform/server/account-delete.ts:200-230`
- **Inngest client:** `apps/web-platform/server/inngest/client.ts`
- **CFO function (PR-G consumer hook):** `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts:12-13` (RV4)
- **Tenant client primitive:** `apps/web-platform/lib/supabase/tenant.ts:341` (`getFreshTenantClient`)
- **Trust-tier copy precedent:** `apps/web-platform/lib/messages/tiers.ts:5-8` (typo-divergence learning)
- **Onboarding hook:** `apps/web-platform/hooks/use-onboarding.ts:48` (current union)
- **Webhook predicate site:** `apps/web-platform/app/api/webhooks/stripe/route.ts:437`
- **Today section render:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx:591-606`
- **Today banner precedent:** `apps/web-platform/components/dashboard/today-banner.tsx`
- **Wireframes:** `knowledge-base/product/design/scope-grants/pr-g-cohort-onboarding.pen` + 6 PNG screenshots
- **Brand guide:** `knowledge-base/marketing/brand-guide.md`
- **TC version bump policy:** `knowledge-base/legal/tc-version-bump-policy.md`
- **Issue:** [#3947](https://github.com/jikig-ai/soleur/issues/3947)
- **Draft PR:** [#3984](https://github.com/jikig-ai/soleur/pull/3984)
- **Plan-time learnings:**
  - `knowledge-base/project/learnings/2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`
  - `knowledge-base/project/learnings/2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`
  - `knowledge-base/project/learnings/security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md`
  - `knowledge-base/project/learnings/2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`
  - `knowledge-base/project/learnings/2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`
  - `knowledge-base/project/learnings/2026-03-20-tc-version-enforcement-surface-parity.md`
  - `knowledge-base/project/learnings/2026-05-18-pr-g-brainstorm-vector-expansion-operator-override-and-in-flight-refresh.md`
