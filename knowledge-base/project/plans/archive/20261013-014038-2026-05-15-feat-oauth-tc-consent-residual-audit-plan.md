---
title: "OAuth T&C Consent — Residual Audit Bundle (Plan)"
date: 2026-05-15
status: draft
type: feature
classification: brand-survival
issue: 3205
pr: 3853
branch: feat-oauth-tc-consent-3205
worktree: .worktrees/feat-oauth-tc-consent-3205/
spec: knowledge-base/project/specs/feat-oauth-tc-consent-3205/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-15-oauth-tc-consent-residual-audit-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
detail_level: a-lot
plan_review_applied:
  - dhh-rails-reviewer
  - kieran-rails-reviewer
  - code-simplicity-reviewer
---

# Plan: OAuth T&C Consent — Residual Audit Bundle

> **Plan-review revision (2026-05-15):** DHH + Kieran + code-simplicity reviewers converged on cuts and Kieran flagged 3 P0s. All applied below. Notable: SHA pipeline collapsed to a hand-edited literal + one CI check; idempotency moved to the RPC via `UNIQUE(user_id, version)` + `ON CONFLICT DO NOTHING`; WS mid-session message-type list corrected to inbound-only types; AC9 reworded (mocked tests cannot prove atomicity); pg_cron retention sweep deferred (0 beta users, 7-year window).

## Overview

The brainstorm (2026-05-15) established that issue #3205's original premise — "no server-side T&C consent enforcement on OAuth callback" — is **stale on `main`**. Server-side enforcement shipped 2026-03-20 via PR #898 → PR #927 → migrations 005-008. A triad audit (CLO + CPO + CTO + repo-research) of the shipped implementation surfaced six residual gaps (R1–R6) bundled into PR #3853.

This plan implements the bundle and reconciles three spec claims that plan-time verification refuted against current `main`. The biggest delta vs. the spec: codebase precedent (migration 043 `tenant_deploy_audit`) requires GDPR cascade primitives the spec did not name — Article 17 anonymise RPC and a WORM trigger. (The Art. 5(1)(e) retention sweep is deferred per simplicity reviewer; column stays for forward-compat.)

**Brand-survival framing carried forward from brainstorm/spec:** threshold `single-user incident`; vectors are (a) destroyed prior-version consent evidence (GDPR Art. 7(1) demonstrability), (b) middleware fail-open during DB incident, (c) stale-consent agent stream after `TC_VERSION` bump.

## Research Reconciliation — Spec vs. Codebase

| # | Spec claim | Reality on `main` | Plan response |
|---|---|---|---|
| RC1 | "Replace literal `4004` in `ws-handler.ts:322` with `WS_CLOSE_CODES.TC_NOT_ACCEPTED`" (spec G5, TR4). | The constant is **already imported and used** at `apps/web-platform/server/ws-handler.ts:1851`: `ws.close(WS_CLOSE_CODES.TC_NOT_ACCEPTED, "T&C not accepted")`. `WS_CLOSE_CODES.TC_NOT_ACCEPTED = 4004` is defined at `apps/web-platform/lib/types.ts:138`, imported by both server and client (`lib/ws-client.ts:154`). | **DROP G5/TR4.** No code change. |
| RC2 | "FR7: Verify `/accept-terms` and `/signup` checkbox copy names BOTH Terms & Conditions AND Privacy Policy with separate linked anchors". | Both pages **already meet the GDPR Art. 7(2) "distinguishable" bar**. `accept-terms/page.tsx:54-73` and `signup/page.tsx:189-208` each render `I agree to the <a>Terms & Conditions</a> and <a>Privacy Policy</a>` with `target="_blank"`, `rel="noopener noreferrer"`, distinct URLs. | **DOWNGRADE FR7 to a regression-prevention vitest assertion only.** |
| RC3 | "New table `public.tc_acceptances` with INSERT-only via service-role; SELECT self-only RLS; UPDATE/DELETE revoked" (spec FR1). | Codebase precedent `apps/web-platform/supabase/migrations/043_tenant_deploy_audit.sql` ships **WORM trigger + Art. 17 anonymise RPC + retention_until column**. | **EXTEND FR1.** New schema mirrors 043: WORM trigger + `anonymise_tc_acceptances(p_user_id)` RPC + `retention_until` column. **Defer `pg_cron` retention sweep** (simplicity-reviewer): 0 beta users, 7-year horizon means the cron runs against 0 rows for years. Column stays; sweep ships in a follow-on issue. |
| RC4 | "REVOKE/GRANT shape — service-role only" (spec FR1). | Per learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`, Supabase auto-grants EXECUTE to `anon`+`authenticated`+`service_role`. `REVOKE FROM PUBLIC` alone leaves them intact. | **TIGHTEN.** `REVOKE ALL ... FROM PUBLIC, anon, authenticated` for caller-facing RPCs; `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` for the trigger function (no direct caller). |
| RC5 | "OQ1: RPC vs. multi-statement route handler" (spec OQ1). | Migration 043 uses `SECURITY DEFINER` RPC with `SET search_path = public, pg_temp`. | **RESOLVE → RPC.** `accept_terms(p_version, p_doc_sha)` RPC; idempotency via `UNIQUE(user_id, version)` + `INSERT ... ON CONFLICT DO NOTHING` inside the RPC (Kieran P0-3). |
| RC6 | "OQ3: E2E stack" (spec OQ3). | No Playwright in `apps/web-platform/`. | **RESOLVE → vitest + mocked Supabase + mocked OAuth provider.** |
| RC7 | "`TC_EXEMPT_PATHS` has 2 entries" (spec FR4 implied scope). | Actual list in `lib/routes.ts:18-22` has **3 entries**: `/accept-terms`, `/api/accept-terms`, `/api/auth/github-resolve/callback`. | **CLARIFY FR4.** Fail-closed test covers all 3 via `test.each(...)`. |
| RC8 | Spec FR5 message-type list includes `tool_use`. | `tool_use` is server→client only — `ws-handler.ts:1690-1715` rejects it on inbound with `"server-to-client only"`. Real inbound message types (Kieran P0-1): `start_session` (1004), `resume_session` (1247), `close_conversation` (1308), `chat` (1352), `interactive_prompt_response` (1586), `abort_turn` (1608), `review_gate_response` (1620). | **CORRECT FR5.** Gate `start_session`, `resume_session`, `chat`, `interactive_prompt_response`, `review_gate_response`. **Exempt** `abort_turn` + `close_conversation` (a user must always be able to stop a stream / close a conversation even with stale consent — refusing those would worsen UX without changing GDPR demonstrability). |

## User-Brand Impact

(Carried forward from brainstorm Phase 0.1 — operator selected "all of them" for the worst-outcome framing.)

**If this lands broken, the user experiences:** a destroyed or fabricated consent record when their lawyer or counsel asks Soleur to demonstrate consent for a prior `TC_VERSION`, OR an OAuth-signup user reaching `/dashboard` during a Supabase DB incident without server-side consent verification, OR a long-running agent stream that continues against stale consent after a `TC_VERSION` bump.

**If this leaks, the user's data is exposed via:** the `users.tc_accepted_at` / `users.tc_accepted_version` overwrite on re-acceptance destroys prior-version evidence; the middleware fail-open at `middleware.ts:133-138` admits non-accepted users on DB error; the WS handshake-only check at `ws-handler.ts:1830-1853` does not re-validate during a live session.

**Brand-survival threshold:** `single-user incident` — a single missing or fabricated consent record is a GDPR Art. 7(1) breach. CPO sign-off captured in brainstorm carry-forward; CLO sign-off required at PR review on (a) FR1 schema, (b) Phase 9.2 bump-policy rubric content, (c) the 7-year retention default. `user-impact-reviewer` runs at PR review per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** Migration `044_add_tc_acceptances_ledger.sql` applied cleanly to dev Supabase (`bdgbnzmprmqsibpvtbmd`) and prd Supabase (`zzfprwuaccgpdttogdoa`) per `hr-dev-prd-distinct-supabase-projects`. Migration checklist artifact at `knowledge-base/project/specs/feat-oauth-tc-consent-3205/migration-checklist.md` records SHA + timestamp per project.
- **AC2.** Grep `REVOKE ALL ON FUNCTION public\.\w+\(.*\) FROM PUBLIC, anon, authenticated` against the new migration returns ≥1 match for EVERY caller-facing `CREATE OR REPLACE FUNCTION public.*` line. Trigger function additionally REVOKEs from `service_role`. Service-role-callable RPCs additionally have `GRANT EXECUTE ... TO service_role`.
- **AC3.** `apps/web-platform/lib/legal/tc-version.ts` exports `TC_DOCUMENT_SHA` as a hand-edited string literal; the value matches the SHA-256 of `docs/legal/terms-and-conditions.md` at HEAD. The CI guardrail (AC7) is the source of truth; the route handler imports the literal directly.
- **AC4.** `POST /api/accept-terms` calls the new `public.accept_terms(p_version, p_doc_sha)` RPC; the RPC owns idempotency via `UNIQUE(user_id, version)` + `INSERT ... ON CONFLICT DO NOTHING`. The route handler does NOT early-return on already-current version; it always calls the RPC, which is a no-op for re-acceptance of the same version (Kieran P0-3).
- **AC5.** `middleware.ts:133-138` no longer fails open. On `tcError` non-null, the handler redirects to `/accept-terms` with `?error=db_unavailable` UNLESS the path is in `TC_EXEMPT_PATHS`. The error is mirrored to Sentry via `reportSilentFallback`.
- **AC6.** `ws-handler.ts` carries a new `tcVersionAtHandshake` field on each `ClientSession`; on inbound message types `start_session`, `resume_session`, `chat`, `interactive_prompt_response`, `review_gate_response`, the handler re-queries `users.tc_accepted_version` (with a 30-second in-process cache keyed on `userId`) and closes the socket with `WS_CLOSE_CODES.TC_NOT_ACCEPTED` if it does not equal `TC_VERSION`. `abort_turn` and `close_conversation` are EXEMPT from re-check (per RC8 reasoning). The cache window means up to 30 s of stale-consent traffic per session may pass between bump and enforcement; this is the explicit trade-off.
- **AC7.** CI workflow job in `.github/workflows/ci.yml` named `tc-document-sha-guard`: runs on every PR; computes SHA-256 of `docs/legal/terms-and-conditions.md` AND `plugins/soleur/docs/pages/legal/terms-and-conditions.md`; grep-extracts `TC_DOCUMENT_SHA` literal from `apps/web-platform/lib/legal/tc-version.ts`; fails the job if (a) the two doc copies are not byte-identical, OR (b) canonical SHA ≠ literal AND the same PR did NOT bump `TC_VERSION`.
- **AC8.** Vitest assertion `apps/web-platform/test/accept-terms-copy-regression.test.tsx` reads `app/(auth)/accept-terms/page.tsx` and `app/(auth)/signup/page.tsx` as strings; asserts each contains the literal `Terms &amp; Conditions`, the literal `Privacy Policy`, the literal `terms-and-conditions.html`, AND the literal `privacy-policy.html`.
- **AC9.** E2E vitest `apps/web-platform/test/e2e-oauth-tc-consent.test.ts`: mocks Supabase auth `exchangeCodeForSession` + `getUser` + service-client; drives a GET on the callback route with NULL `tc_accepted_version`; asserts redirect to `/accept-terms`; POSTs to `/api/accept-terms`; asserts (a) `users.tc_accepted_version` mutated to `TC_VERSION`, (b) row inserted into `tc_acceptances` with `version`+`document_sha`+`accepted_at`, (c) **the route handler called `accept_terms` RPC exactly once with `(TC_VERSION, TC_DOCUMENT_SHA)` — not a separate `.update("users")` + `.insert("tc_acceptances")`** (per Kieran P0-2: this test demonstrates the route delegates to one RPC; it cannot prove server-side atomicity, which is a Postgres transaction guarantee enforced by `SECURITY DEFINER` SQL).
- **AC10.** Vitest `apps/web-platform/test/middleware.fail-closed.test.ts` asserts that on `tcError != null`:
  - For each path in `TC_EXEMPT_PATHS` (3 entries), middleware continues with `NextResponse.next()` (no redirect).
  - For a representative non-exempt path (`/dashboard`), middleware redirects to `/accept-terms?error=db_unavailable`.
  - Uses `test.each(TC_EXEMPT_PATHS)(...)` so adding a 4th exempt path automatically gets coverage.
- **AC11.** Vitest `apps/web-platform/test/ws-handler.tc-mid-session.test.ts` asserts:
  - For each gated message type (`start_session`, `resume_session`, `chat`, `interactive_prompt_response`, `review_gate_response`), after `TC_VERSION` is bumped mid-session, `ws.close(WS_CLOSE_CODES.TC_NOT_ACCEPTED, ...)` is invoked.
  - For each exempt message type (`abort_turn`, `close_conversation`), after `TC_VERSION` is bumped mid-session, `ws.close` is NOT invoked.
  - 30-second cache: re-sending a gated message within 30 s does NOT re-query DB (mock `.select` call count is 1, not 2).
- **AC12.** Migration includes WORM trigger `tc_acceptances_no_mutate`: rejects all UPDATE attempts unconditionally; rejects DELETE except via `anonymise_tc_acceptances` GUC + `service_role` bypass. (No retention-sweep bypass in v1 since `pg_cron` is deferred.)
- **AC13.** Migration includes `public.anonymise_tc_acceptances(p_user_id uuid) RETURNS int` — `SECURITY DEFINER`, `SET search_path = public, pg_temp`, sets `user_id = NULL` for the given user's rows (preserves audit trail), single GUC SET-site for `app.tc_acceptances_anonymise_in_progress`. Per `cq-pg-security-definer-search-path-pin-pg-temp`. Idempotent.
- **AC14.** Migration includes `public.accept_terms(p_version text, p_doc_sha text) RETURNS void` — `SECURITY DEFINER`, `SET search_path = public, pg_temp`. Body: (1) `UPDATE public.users SET tc_accepted_at = now(), tc_accepted_version = p_version WHERE id = auth.uid();` (2) `INSERT INTO public.tc_acceptances (user_id, version, document_sha, accepted_at) VALUES (auth.uid(), p_version, p_doc_sha, now()) ON CONFLICT (user_id, version) DO NOTHING;` Both statements use server-side `now()` — RPC does NOT accept a client-supplied timestamp (Kieran P2-3). Migration creates `UNIQUE(user_id, version)` constraint or partial unique index on `tc_acceptances`. REVOKE from `PUBLIC, anon, authenticated`; GRANT EXECUTE to `service_role`. (Note: `auth.uid()` requires session context; service-role calls supply `user_id` via SET_CONFIG or take `p_user_id` parameter — verify the Supabase pattern in 043 at /work-time; 043's writer accepts `p_founder_id`, suggesting the parameter pattern is canonical.)
- **AC15.** `knowledge-base/legal/article-30-register.md` includes a new "Processing Activity — Consent Records" entry (number assigned at /work time based on current entry count). Legal basis: Art. 6(1)(b) + Art. 7. Retention: 7 years from acceptance (column default; sweep mechanism deferred to follow-on issue).
- **AC16.** `knowledge-base/legal/tc-version-bump-policy.md` exists with the 3-tier rubric (material / clarifying / cosmetic). CLO sign-off captured on PR review.
- **AC17.** `/soleur:gdpr-gate` invoked at /work Phase 2 exit; report committed at `knowledge-base/legal/gdpr-gate-report-2026-05-15-feat-oauth-tc-consent-3205.md`.
- **AC18.** PR body declares `Closes #3205` and includes a comment summary linking shipped surfaces (PR #898, PR #927, migrations 005-008) + the bundled R1-R6 + Art. 17 work.
- **AC19.** All existing tests pass.
- **AC20.** `user-impact-reviewer` agent runs at PR review with no must-close findings.
- **AC21.** Tracking issue filed for the deferred `pg_cron` retention sweep, label `deferred-scope-out` + `domain/legal`, milestone `Post-MVP / Later`, re-evaluation criteria: "first row reaches 6.5-year age OR CLO requests retention enforcement, whichever first."

### Post-merge (operator)

- **AC22.** Migration applied to prd Supabase post-merge via `/soleur:ship` Phase 5 verification.
- **AC23.** Spot-check on prd via `mcp__plugin_supabase_supabase__execute_sql`: insert one synthetic acceptance via the RPC; SELECT it back; assert WORM by attempting UPDATE (expect SQLSTATE P0001); attempt anonymise RPC; assert `user_id = NULL`.

## Implementation Phases

### Phase 0: Preconditions (one-shot)

- **0.1.** Verify worktree on `feat-oauth-tc-consent-3205` at HEAD `a63aa714` or later.
- **0.2.** `ls apps/web-platform/supabase/migrations/ | sort | tail -n 5` — verify **044** is still available immediately before commit (per R1).
- **0.3.** Verify Supabase project IDs for dev / prd via `doppler secrets get SUPABASE_PROJECT_REF -p soleur -c <env> --plain`.
- **0.4.** `sha256sum docs/legal/terms-and-conditions.md plugins/soleur/docs/pages/legal/terms-and-conditions.md` — record the canonical value to seed `TC_DOCUMENT_SHA`. Assert byte-identical.
- **0.5.** Grep `reportSilentFallback` import in a sibling caller (e.g., `app/api/accept-terms/route.ts:7`) to confirm the canonical import path is `@/server/observability`.
- **0.6.** Read the WS protocol discriminated union in `apps/web-platform/lib/types.ts` (around line 201-230 per Kieran's reference) to confirm the 7 inbound message types named in AC6.

### Phase 1: Migration 044_add_tc_acceptances_ledger.sql (ATDD — RED)

Migration mirrors `043_tenant_deploy_audit.sql` structure. **No `pg_cron` retention sweep in v1** (deferred per RC3); column stays.

- **1.1.** **Write failing migration test** at `apps/web-platform/test/migration-044-tc-acceptances.test.ts` — **minimal, semantic asserts only** (per DHH cut):
  - Grep: EVERY caller-facing `CREATE OR REPLACE FUNCTION public.\w+\(` block (i.e., `accept_terms`, `anonymise_tc_acceptances`) is followed within 10 lines by `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon, authenticated`.
  - Grep: the trigger function `tc_acceptances_no_mutate` REVOKEs from `PUBLIC, anon, authenticated, service_role` (four-role pattern).
  - Grep: `LANGUAGE plpgsql` block for the trigger function does NOT contain `SECURITY DEFINER` (must be INVOKER).
  - No assertions on table-DDL string presence (DHH: parse-test theater). The migration's actual apply-to-dev (1.7) is the structural test.

- **1.2.** **Write migration**. Table schema:
  ```sql
  CREATE TABLE IF NOT EXISTS public.tc_acceptances (
    id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid         REFERENCES public.users(id) ON DELETE RESTRICT,
    version         text         NOT NULL CHECK (length(version) BETWEEN 1 AND 32),
    document_sha    text         NOT NULL CHECK (document_sha ~ '^[0-9a-f]{64}$'),
    accepted_at     timestamptz  NOT NULL DEFAULT now(),
    ip_hash         text         NULL  CHECK (ip_hash IS NULL OR length(ip_hash) BETWEEN 1 AND 128),
    user_agent      text         NULL  CHECK (user_agent IS NULL OR length(user_agent) BETWEEN 1 AND 512),
    retention_until timestamptz  NOT NULL DEFAULT (now() + interval '7 years'),
    created_at      timestamptz  NOT NULL DEFAULT now(),
    UNIQUE (user_id, version)
  );
  ALTER TABLE public.tc_acceptances ENABLE ROW LEVEL SECURITY;
  CREATE INDEX tc_acceptances_user_accepted_idx ON public.tc_acceptances (user_id, accepted_at DESC);
  ```
  Header comment cites: ADR (TBD if separate ADR needed; for v1 plan + spec docs suffice), learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`, Art. 30 RoPA entry (Phase 9.1), `cq-pg-security-definer-search-path-pin-pg-temp`. **Explicit comment block** explaining ON DELETE RESTRICT ordering: `anonymise_tc_acceptances` MUST be called BEFORE `auth.admin.deleteUser` in the offboarding runbook (mirror 043:43-47).

- **1.3.** **WORM trigger** — mirror 043:137-185, simplified (no retention-sweep bypass in v1, only anonymise bypass):
  ```sql
  CREATE OR REPLACE FUNCTION public.tc_acceptances_no_mutate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public, pg_temp
  AS $$
  DECLARE v_flag text;
  BEGIN
    v_flag := current_setting('app.tc_acceptances_anonymise_in_progress', true);
    IF v_flag <> '' AND current_user = 'service_role' THEN
      RETURN COALESCE(NEW, OLD);
    END IF;
    RAISE EXCEPTION 'tc_acceptances is append-only (WORM)' USING ERRCODE = 'P0001';
  END;
  $$;
  REVOKE ALL ON FUNCTION public.tc_acceptances_no_mutate() FROM PUBLIC, anon, authenticated, service_role;
  CREATE TRIGGER tc_acceptances_no_update BEFORE UPDATE ON public.tc_acceptances FOR EACH ROW EXECUTE FUNCTION public.tc_acceptances_no_mutate();
  CREATE TRIGGER tc_acceptances_no_delete BEFORE DELETE ON public.tc_acceptances FOR EACH ROW EXECUTE FUNCTION public.tc_acceptances_no_mutate();
  ```
  Function is `INVOKER` (no `SECURITY DEFINER`) per 043:127-134 reasoning — DEFINER would evaluate `current_user` as the function owner (`postgres`), defeating the role gate.

- **1.4.** **`accept_terms` RPC** — `SECURITY DEFINER`, `SET search_path = public, pg_temp`. Parameters: `p_user_id uuid, p_version text, p_doc_sha text`. Body uses server-side `now()`; client cannot supply a timestamp:
  ```sql
  CREATE OR REPLACE FUNCTION public.accept_terms(p_user_id uuid, p_version text, p_doc_sha text)
    RETURNS void
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = public, pg_temp
  AS $$
    UPDATE public.users SET tc_accepted_at = now(), tc_accepted_version = p_version WHERE id = p_user_id;
    INSERT INTO public.tc_acceptances (user_id, version, document_sha)
      VALUES (p_user_id, p_version, p_doc_sha)
      ON CONFLICT (user_id, version) DO NOTHING;
  $$;
  REVOKE ALL ON FUNCTION public.accept_terms(uuid, text, text) FROM PUBLIC, anon, authenticated;
  GRANT EXECUTE ON FUNCTION public.accept_terms(uuid, text, text) TO service_role;
  ```
  Idempotency is in the RPC (`ON CONFLICT DO NOTHING`). The UPDATE is a no-op if the version was already current; the INSERT is a no-op if `(user_id, version)` is already present. The route handler ALWAYS calls the RPC — no early-return (Kieran P0-3).

- **1.5.** **`anonymise_tc_acceptances` RPC** — same shape as 043's anonymise. Sets `user_id = NULL` on matching rows (preserves audit trail). Single SET-site for the GUC. `SECURITY DEFINER` + `SET search_path`.

- **1.6.** **No `pg_cron` retention sweep in v1.** `retention_until` column stays. Phase 10's `gh issue create` (AC21) files the deferred-tracking issue for the sweep.

- **1.7.** **Apply to dev**: `bash apps/web-platform/scripts/run-migrations.sh --target dev` (verify script flag at /work). Migration test in 1.1 turns GREEN.

- **1.8.** **prd application deferred to post-merge `/soleur:ship`** per `hr-menu-option-ack-not-prod-write-auth`.

### Phase 2: Route handler — `POST /api/accept-terms` calls RPC (ATDD — RED)

- **2.1.** **Write failing test** at `apps/web-platform/test/api-accept-terms-ledger.test.ts`:
  - Mocks service client; expects `.rpc("accept_terms", { p_user_id, p_version, p_doc_sha })` to be called.
  - Asserts NO direct `.update("users")` or `.insert("tc_acceptances")` call on the service client.
  - Asserts the route does NOT short-circuit on already-current version — RPC is always called (RPC handles the no-op).

- **2.2.** **Edit `apps/web-platform/app/api/accept-terms/route.ts`**:
  - Remove the existing idempotency check (lines 40-50 in current main).
  - Always call `.rpc("accept_terms", { p_user_id: user.id, p_version: TC_VERSION, p_doc_sha: TC_DOCUMENT_SHA })`.
  - Preserve CSRF gate (`validateOrigin`/`rejectCsrf` at top of file).
  - On RPC error, surface to Sentry via `reportSilentFallback` and return 500.
  - Import `TC_DOCUMENT_SHA` from `@/lib/legal/tc-version`.

- **2.3.** Test 2.1 → GREEN.

### Phase 3: `TC_DOCUMENT_SHA` literal in `tc-version.ts` (simplest viable shape)

Plan-review-applied: **collapsed** from 6 artifacts to 1 hand-edited literal + 1 CI check (Phase 6). No script, no generated file, no build-time hook, no re-export shim, no runtime test.

- **3.1.** Compute SHA-256 of `docs/legal/terms-and-conditions.md` (and verify byte-identical to `plugins/soleur/docs/pages/legal/terms-and-conditions.md`).
- **3.2.** Edit `apps/web-platform/lib/legal/tc-version.ts` to add:
  ```typescript
  /**
   * SHA-256 of docs/legal/terms-and-conditions.md at the time of the
   * current TC_VERSION. Hand-edited literal. CI guardrail
   * (.github/workflows/ci.yml:tc-document-sha-guard) asserts this
   * matches the file content; mismatch fails the build unless TC_VERSION
   * was bumped in the same PR. Persisted per acceptance in tc_acceptances.
   */
  export const TC_DOCUMENT_SHA = "<64-char-lowercase-hex>";
  ```
- **3.3.** No package.json edits, no .gitignore edits, no new files.

### Phase 4: Middleware fail-closed (ATDD — RED)

- **4.1.** **Write failing test** at `apps/web-platform/test/middleware.fail-closed.test.ts`:
  - For each path in `TC_EXEMPT_PATHS` (use `test.each(TC_EXEMPT_PATHS)`): mocks DB error; asserts middleware continues with `NextResponse.next()` (no redirect).
  - For `/dashboard`: mocks DB error; asserts redirect to `/accept-terms?error=db_unavailable`.

- **4.2.** **Edit `apps/web-platform/middleware.ts` lines 126-142**:
  ```typescript
  if (tcError) {
    reportSilentFallback(tcError, {
      feature: "middleware",
      op: "tc_query_failed",
      message: "users.tc_accepted_version SELECT failed",
      extra: { userId: user.id },
    });
    // Exempt paths must remain reachable during a DB incident so the user
    // can still get to /accept-terms (its own /api endpoint reads no DB
    // state, only writes), and the github-resolve recovery path stays open.
    if (TC_EXEMPT_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"))) {
      return withCspHeaders(response, cspValue);
    }
    const url = request.nextUrl.clone();
    url.pathname = "/accept-terms";
    url.searchParams.set("error", "db_unavailable");
    return withCspHeaders(NextResponse.redirect(url), cspValue);
  }
  ```
  Note: middleware's existing branch order already short-circuits exempt paths above this block (lines 125-126), so the exempt check inside the new branch is belt-and-suspenders; preserve it anyway.

- **4.3.** Test 4.1 → GREEN.

### Phase 5: WebSocket mid-session re-check (ATDD — RED)

- **5.1.** **Write failing test** at `apps/web-platform/test/ws-handler.tc-mid-session.test.ts`:
  - Per AC11: enumerate 5 gated message types + 2 exempt types via `test.each`.
  - For each gated type: simulate session opened at `tc_accepted_version = "1.0.0"`, bump `TC_VERSION` to `"1.0.1"`, send the message, assert `ws.close(WS_CLOSE_CODES.TC_NOT_ACCEPTED, ...)` invoked.
  - For each exempt type: same setup, assert `ws.close` is NOT invoked.
  - Cache test: two gated messages within 30s → mock `.select` count is 1.

- **5.2.** **Edit `apps/web-platform/server/ws-handler.ts`**:
  - Define `const TC_RECHECK_MESSAGE_TYPES = new Set(["start_session", "resume_session", "chat", "interactive_prompt_response", "review_gate_response"]);` near top of file.
  - Add fields to `ClientSession` interface: `tcVersionAtHandshake: string | null`, `tcRecheckCacheUntil: number | null`.
  - At session registration (line ~1875): set `tcVersionAtHandshake: userRowTyped.tc_accepted_version ?? null`, `tcRecheckCacheUntil: null`.
  - At the inbound-message handler (find via `grep -n 'switch (msg.type)' apps/web-platform/server/ws-handler.ts`), insert at the top of the switch (before any case):
    ```typescript
    if (TC_RECHECK_MESSAGE_TYPES.has(msg.type)) {
      if (!session.tcRecheckCacheUntil || Date.now() > session.tcRecheckCacheUntil) {
        const { data: row, error } = await supabase
          .from("users").select("tc_accepted_version").eq("id", session.userId).single();
        if (error || row?.tc_accepted_version !== TC_VERSION) {
          ws.close(WS_CLOSE_CODES.TC_NOT_ACCEPTED, "T&C not accepted (mid-session)");
          return;
        }
        session.tcRecheckCacheUntil = Date.now() + 30_000;
      }
    }
    ```

- **5.3.** Test 5.1 → GREEN.

### Phase 6: CI guardrail for T&C document SHA drift (ATDD — small)

Plan-review-applied: single bash script invoked from CI, no test driver, no generated file dependency.

- **6.1.** **Write `apps/web-platform/scripts/check-tc-document-sha.sh`**:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  CANONICAL_SHA=$(sha256sum docs/legal/terms-and-conditions.md | awk '{print $1}')
  MIRROR_SHA=$(sha256sum plugins/soleur/docs/pages/legal/terms-and-conditions.md | awk '{print $1}')

  if [ "$CANONICAL_SHA" != "$MIRROR_SHA" ]; then
    echo "::error::T&C document mirror drift — docs/legal/ and plugins/soleur/docs/pages/legal/ are not byte-identical." >&2
    exit 1
  fi

  LITERAL_SHA=$(grep -oE 'TC_DOCUMENT_SHA = "[0-9a-f]{64}"' apps/web-platform/lib/legal/tc-version.ts | grep -oE '[0-9a-f]{64}' || true)

  if [ -z "$LITERAL_SHA" ]; then
    echo "::error::TC_DOCUMENT_SHA literal not found in apps/web-platform/lib/legal/tc-version.ts" >&2
    exit 1
  fi

  if [ "$CANONICAL_SHA" = "$LITERAL_SHA" ]; then
    exit 0
  fi

  # SHA mismatch — allow ONLY if this PR bumps TC_VERSION.
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    if git diff --unified=0 "origin/${GITHUB_BASE_REF}...HEAD" -- apps/web-platform/lib/legal/tc-version.ts \
       | grep -qE '^[+-]export const TC_VERSION'; then
      exit 0
    fi
  fi

  echo "::error::TC document content changed but TC_DOCUMENT_SHA literal is stale and TC_VERSION was not bumped. Recompute SHA, update the literal, and bump TC_VERSION in lib/legal/tc-version.ts." >&2
  exit 1
  ```

- **6.2.** **Add CI job to `.github/workflows/ci.yml`** (after the existing `lint-bot-statuses` job pattern at lines ~64-69):
  ```yaml
  tc-document-sha-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<pinned-sha>
        with: { fetch-depth: 0 }
      - name: Verify TC document SHA pinned in tc-version.ts
        env:
          GITHUB_BASE_REF: ${{ github.base_ref }}
        run: bash apps/web-platform/scripts/check-tc-document-sha.sh
  ```

- **6.3.** No test file for the bash script (per DHH cut #2; PR itself is the test surface). Manually verify behavior by (a) committing a doc edit without bumping `TC_VERSION` and confirming CI fails, (b) bumping `TC_VERSION` and the literal and confirming CI passes. Document both verifications in PR description.

### Phase 7: Copy regression test (ATDD — small)

- **7.1.** **Add `apps/web-platform/test/accept-terms-copy-regression.test.tsx`** per AC8. ~30 LOC, two file reads, four `toContain` assertions per file.
- **7.2.** Test → GREEN immediately (current copy passes).

### Phase 8: End-to-end test (ATDD — RED)

- **8.1.** **Add `apps/web-platform/test/e2e-oauth-tc-consent.test.ts`** per AC9. Mock chain: `exchangeCodeForSession` → success; `getUser` → fixture user; service client → `tc_accepted_version: null`. Drive callback route GET; assert redirect to `/accept-terms`. Drive POST `/api/accept-terms`; assert RPC called exactly once with `(p_user_id, TC_VERSION, TC_DOCUMENT_SHA)`. Mock the RPC to return `{ data: null, error: null }`; do NOT claim atomicity (P0-2).

- **8.2.** Test → GREEN.

### Phase 9: Article 30 RoPA + bump-policy doc

- **9.1.** **Edit `knowledge-base/legal/article-30-register.md`**: append "Processing Activity — Consent Records" (number = current entry count + 1, assigned at /work time).
- **9.2.** **Create `knowledge-base/legal/tc-version-bump-policy.md`** with the 3-tier rubric (material / clarifying / cosmetic) per spec FR9 + CLO assessment shape.
- ~~9.3. Learning addendum~~ — **CUT** (plan-review-applied; replaced by PR description summary).

### Phase 10: PR-ready + Closes #3205 + deferred tracking

- **10.1.** Run `/soleur:gdpr-gate` (AC17); commit report to `knowledge-base/legal/`.
- **10.2.** File deferred-tracking issue for `pg_cron` retention sweep (AC21):
  ```bash
  gh issue create \
    --title "feat: tc_acceptances retention sweep (pg_cron deferred from PR #3853)" \
    --label "deferred-scope-out,domain/legal,priority/p3-low" \
    --milestone "Post-MVP / Later" \
    --body "Deferred from #3205 / PR #3853. Column \`retention_until\` exists with 7-year default; \`pg_cron\` DELETE sweep was cut because no row qualifies for deletion before 2033. Re-evaluate when first row reaches 6.5-year age OR CLO requests retention enforcement."
  ```
- **10.3.** `gh pr ready 3853`; PR body declares `Closes #3205`.
- **10.4.** Review pipeline: `user-impact-reviewer` (mandatory per AC20) + `data-integrity-guardian` (recommended).
- **10.5.** CPO/CLO sign-off via PR comments on (a) FR1 schema, (b) Phase 9.2 rubric, (c) 7-year retention default.

## Files to Edit

- `apps/web-platform/app/api/accept-terms/route.ts` — Phase 2; call RPC, drop early-return.
- `apps/web-platform/middleware.ts` — Phase 4; fail-closed branch + Sentry mirror.
- `apps/web-platform/server/ws-handler.ts` — Phase 5; mid-session TC re-check with 30s cache.
- `apps/web-platform/lib/legal/tc-version.ts` — Phase 3; add `TC_DOCUMENT_SHA` literal.
- `.github/workflows/ci.yml` — Phase 6.2; new `tc-document-sha-guard` job.
- `knowledge-base/legal/article-30-register.md` — Phase 9.1; add Consent Records processing activity.

## Files to Create

- `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql` — Phase 1.
- `apps/web-platform/scripts/check-tc-document-sha.sh` — Phase 6.1.
- `apps/web-platform/test/migration-044-tc-acceptances.test.ts` — Phase 1.1.
- `apps/web-platform/test/api-accept-terms-ledger.test.ts` — Phase 2.1.
- `apps/web-platform/test/middleware.fail-closed.test.ts` — Phase 4.1.
- `apps/web-platform/test/ws-handler.tc-mid-session.test.ts` — Phase 5.1.
- `apps/web-platform/test/accept-terms-copy-regression.test.tsx` — Phase 7.1.
- `apps/web-platform/test/e2e-oauth-tc-consent.test.ts` — Phase 8.1.
- `knowledge-base/legal/tc-version-bump-policy.md` — Phase 9.2.
- `knowledge-base/project/specs/feat-oauth-tc-consent-3205/migration-checklist.md` — Phase 1.7-1.8; dev+prd apply log.

**Cuts from previous draft:** `compute-tc-sha.mjs`, `tc-document-sha.generated.ts`, `tc-document-sha.test.ts`, `check-tc-document-sha.test.sh`, package.json `prebuild`/`pretest` edits, `.gitignore` edit, learning-addendum edit.

## Open Code-Review Overlap

Five open `code-review`-labeled issues touch files this plan modifies; none target the same concern. Disposition: **acknowledge** for each. (See previous draft for full enumeration — #2191, #2591, #3184, #3242, #3372, #3374.) No fold-ins.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from brainstorm Phase 0.5).

### Engineering (CTO — carry-forward)

**Status:** reviewed (brainstorm).
**Assessment:** Premise stale. Three single-user-incident-class gaps confirmed. RC5 resolved to RPC; RC8 corrected message-type list at plan time (Kieran P0-1). `TC_VERSION` stays as code constant; `TC_DOCUMENT_SHA` joins as a sibling code constant.

### Legal (CLO — carry-forward)

**Status:** reviewed (brainstorm).
**Assessment:** Append-only ledger is must-close before paid-customer-#1. Git/build SHA fingerprint sufficient. IP/UA capture deferred pending LIA (#3855). Bundled-consent UI defensible (RC2 confirms). Bump-policy rubric must-tighten (Phase 9.2). **PR-review sign-off required on (a) FR1 schema, (b) Phase 9.2 rubric content, (c) 7-year retention default.**

### Product (CPO — carry-forward)

**Status:** reviewed (brainstorm).
**Assessment:** Close #3205 as resolved-on-main; PR #3853 is the new tracking surface. Phase 4.10 (Stripe live) prereq.

### Product/UX Gate

**Tier:** none. No new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files. Existing page edits are read-only (regression-prevention assertion only).

## GDPR / Compliance Gate

Plan touches schemas / migrations / auth flows / API routes (regulated-data surfaces). AC17 invokes `/soleur:gdpr-gate` at /work Phase 2 exit. Phase 9.1 (Article 30 RoPA update) addresses the Art. 30 trigger preemptively.

## Test Scenarios

| # | Scenario | Test file | Type |
|---|---|---|---|
| T1 | Migration REVOKE pattern + INVOKER trigger | `test/migration-044-tc-acceptances.test.ts` | vitest unit (grep) |
| T2 | RPC contract — route handler delegates to `accept_terms` | `test/api-accept-terms-ledger.test.ts` | vitest unit |
| T3 | Middleware fail-closed (all 3 exempt paths + non-exempt) | `test/middleware.fail-closed.test.ts` | vitest unit (`test.each`) |
| T4 | WS mid-session — 5 gated types + 2 exempt + cache | `test/ws-handler.tc-mid-session.test.ts` | vitest unit (`test.each`) |
| T5 | CI guardrail | (no test file; PR-surface verification) | manual via PR |
| T6 | Copy regression | `test/accept-terms-copy-regression.test.tsx` | vitest unit |
| T7 | E2E: OAuth → /accept-terms → RPC called | `test/e2e-oauth-tc-consent.test.ts` | vitest integration |
| T8 (post-merge) | WORM invariant on prd | `mcp__plugin_supabase_supabase__execute_sql` | manual via MCP |

## Risks

- **R1.** Migration 044 conflicts with a parallel-PR migration. Mitigation: re-check before commit; repo tolerates duplicate numbers.
- **R2.** `reportSilentFallback` import path drift in middleware. Mitigation: Phase 0.5 grep.
- **R3.** WS re-check adds DB load. Mitigation: 30s in-process cache. <1 qps additional load worst case.
- **R4.** Operator forgets to bump `TC_DOCUMENT_SHA` after edit. Mitigation: CI guardrail (Phase 6).
- **R5.** WORM trigger blocks legitimate operator UPDATE during incident response. Mitigation: anonymise RPC + (in v1) Supabase admin override with logged justification.
- **R6.** 7-year retention is a guess pending legal review. Mitigation: AC15 RoPA documents; CLO sign-off at PR review can adjust; deferring the cron sweep means the choice has no runtime effect until 2033.
- **R7.** `(user_id, version)` uniqueness rejects re-acceptance of the same version. Acceptable — re-acceptance is meaningless when version did not change; the `users.tc_accepted_at` UPDATE in the RPC is the heartbeat record.
- **R8.** 30s WS cache window means up to 30 s of stale-consent agent traffic after a `TC_VERSION` bump. Documented explicitly in AC6. Acceptable: bumps are operator-initiated and bounded; the window is upper-bounded; the WS close on the next message after the window closes the gap.
- **R9.** Plan-review revision moves idempotency from route handler to RPC. The current route handler's early-return at lines 47-50 is REMOVED. Race fix: concurrent requests from the same user no longer have a window where two `users` UPDATEs run; the RPC's `ON CONFLICT DO NOTHING` is the single source of truth for "same version re-accept = no-op."

## Research Insights

- **Migration precedent:** `043_tenant_deploy_audit.sql` is the gold-standard append-only WORM ledger template.
- **Supabase default privileges trap:** `REVOKE FROM PUBLIC` alone leaves `anon`/`authenticated`/`service_role` grants intact (learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`). AC2 grep enforces the four-role pattern.
- **No new dependencies:** vitest + Supabase mock pattern already in tree.
- **CI workflow shape:** `.github/workflows/ci.yml` already has multiple `lint-*` jobs that match the new `tc-document-sha-guard` shape.
- **`WS_CLOSE_CODES.TC_NOT_ACCEPTED`** already exists at `lib/types.ts:138`, imported at `ws-handler.ts:1851` and `lib/ws-client.ts:154`.
- **`TC_EXEMPT_PATHS` has 3 entries** including `/api/auth/github-resolve/callback`.
- **Both consent pages already name BOTH documents** with distinct anchors.
- **WS inbound message types** (Kieran-verified): `start_session` (1004), `resume_session` (1247), `close_conversation` (1308), `chat` (1352), `interactive_prompt_response` (1586), `abort_turn` (1608), `review_gate_response` (1620). `tool_use` and 18 others are server→client only — rejected on inbound at `ws-handler.ts:1690-1715`.

## Hypotheses

Skipped — no SSH / firewall / network-outage triggers.

## Sharp Edges

- **Migration number 044 is provisional.** Verify next available immediately before commit.
- **`reportSilentFallback` import path** verify at Phase 0.5.
- **WS-handler mid-session check inserts into a hot path.** 30 s cache TTL. Do NOT disable the cache.
- **`TC_DOCUMENT_SHA` is a hand-edited literal**, not a generated artifact. CI is the structural defense. Operator workflow: edit T&C → run `sha256sum docs/legal/terms-and-conditions.md` → update literal in `tc-version.ts` → bump `TC_VERSION` if material/clarifying → commit all in one PR.
- **CONCURRENTLY index forbidden** in Supabase migrations. The migration uses plain `CREATE INDEX`.
- **`/api/auth/github-resolve/callback` is in `TC_EXEMPT_PATHS`** (third entry). AC10's `test.each` covers it automatically.
- **`tc_acceptances.user_id ON DELETE RESTRICT`** — the offboarding runbook MUST call `anonymise_tc_acceptances(p_user_id)` BEFORE `auth.admin.deleteUser`. Migration header comment documents this.
- **`accept_terms` RPC takes `p_user_id` as a parameter**, NOT `auth.uid()` — service-role context. Verify pattern against 043's `write_tenant_deploy_audit` at /work-time.
- **No `pg_cron` retention sweep in v1.** Column exists; sweep deferred to follow-on issue (AC21). Until 2033, no row qualifies for deletion anyway.
- **`UNIQUE(user_id, version)` rejects re-acceptance of the same version** — by design; consent records are content-addressed by `(user_id, version)`. Re-acceptance of same version is a no-op.
- **Per `hr-no-dashboard-eyeball-pull-data-yourself`:** AC23 prd spot-check uses `mcp__plugin_supabase_supabase__execute_sql`.
- **Per `hr-dev-prd-distinct-supabase-projects`:** migration applied to BOTH projects.
- **Per `hr-menu-option-ack-not-prod-write-auth`:** prd apply is post-merge via `/soleur:ship` with explicit ack.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-15-feat-oauth-tc-consent-residual-audit-plan.md. Branch: feat-oauth-tc-consent-3205. Worktree: .worktrees/feat-oauth-tc-consent-3205/. Issue: #3205. PR: #3853. Plan reviewed (DHH + Kieran + simplicity, all changes applied). ATDD implementation next, 10 phases: migration (no cron sweep) → route handler → SHA literal → middleware → WS mid-session → CI guardrail → copy regression → e2e → RoPA+rubric → PR-ready+deferred-tracking.
```
