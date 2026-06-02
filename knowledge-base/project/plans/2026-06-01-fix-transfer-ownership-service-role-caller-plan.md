---
title: "fix: transfer_workspace_ownership broken under service-role (auth.uid() NULL)"
date: 2026-06-01
type: fix
issue: 4765
branch: feat-one-shot-transfer-ownership-service-role
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: planned
---

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Risks & Mitigations (precedent-diff gate + types resolution), Acceptance Criteria (AC10), Sharp Edges.

### Key Improvements
1. **Precedent-Diff Gate (Phase 4.4):** added a side-by-side grant/caller-resolution matrix proving 092 adopts the 091 (`rename_organization`) + 085 (`accept_workspace_invitation`) canonical shape verbatim, with the single intentional divergence (GRANT `authenticated`→`service_role`) being the security fix itself.
2. **Multi-clause predicate reading:** restated all three operands of the owner-gate (`workspace_id`, `user_id` via COALESCE, `role='owner'` + `FOR UPDATE`) to confirm the COALESCE change touches only the caller-id input source.
3. **`tsc` risk RESOLVED:** verified `createServiceClient()` is untyped (no `<Database>` generic) — adding `p_caller_user_id` to the `.rpc` payload cannot regress `tsc`. AC10/Sharp-Edge downgraded from open risk to trivial guard.

### New Considerations Discovered
- 075 currently grants the RPC to `authenticated` (NOT service_role as the issue body's "stay" wording implied) — the grant must be **flipped**, not merely kept. Captured in the Research Reconciliation table as an explicit correction.
- The verified caller id is already plumbed end-to-end (route → args.callerUserId → wrapper); the only missing link is the one `.rpc` payload key.

### Halt Gates (deepen-plan)
- Phase 4.6 User-Brand Impact: PASS (threshold `single-user incident`, concrete artifacts/vectors).
- Phase 4.7 Observability: PASS (5 fields present, non-placeholder, no SSH in discoverability_test).
- Phase 4.8 PAT-shaped variable: PASS (no matches).

# 🐛 fix: `transfer_workspace_ownership` broken under service-role (`auth.uid()` NULL)

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec directory exists for this branch (one-shot → plan path skipped brainstorm).

Closes #4765.

## Overview

`transfer_workspace_ownership` (migration `075_transfer_workspace_ownership.sql`) gates the caller on a bare `auth.uid()`:

```sql
-- 075_transfer_workspace_ownership.sql:36-46
DECLARE
  v_caller_user_id uuid := auth.uid();
  ...
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;
```

Its **sole caller** invokes the RPC via the service-role client, under which `auth.uid()` returns `NULL`:

```ts
// server/workspace-membership.ts:366-371
const service = createServiceClient();          // SUPABASE_SERVICE_ROLE_KEY, persistSession:false
const { data, error } = await service.rpc("transfer_workspace_ownership", {
  p_workspace_id: args.workspaceId,
  p_new_owner_user_id: args.newOwnerUserId,
  p_attestation_text: args.attestationText,     // ← p_caller_user_id NOT forwarded
});
```

**Confirmed mechanism (verified by code-read, not yet reproduced live):** every call to the transfer-ownership flow raises `28000` inside the SECURITY DEFINER body → the wrapper's catch maps the unmatched message to `rpc_failed` → the route returns HTTP 500. The flow is gated behind `isTeamWorkspaceInviteEnabled` (dogfood flag), which is why it has not surfaced in production.

This is the **exact class** of defect fixed for `rename_organization` in PR #4762 (migration `091`) and for `accept_workspace_invitation` (migrations `076`/`085`). The fix is a verbatim application of the established `COALESCE(p_caller_user_id, auth.uid())` + service-role-only-grant precedent.

**The fix is unusually small** because the verified caller id is *already plumbed* to the TS wrapper:

- The route reads `getUser()` and passes `callerUserId: user.id` (`app/api/workspace/transfer-ownership/route.ts:67`).
- `TransferWorkspaceOwnershipArgs.callerUserId` already exists (`server/workspace-membership.ts:341`) and is already consumed by the wrapper for session-abort + socket-close (lines 391, 396, 401, 413).
- The wrapper simply fails to forward it as `p_caller_user_id` to the RPC.

So the change is: (1) a new migration `092` widening the RPC signature + flipping the grant; (2) one added key in the existing `.rpc()` payload; (3) migration-shape test + wrapper test.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| RPC at `075:37,44-46` derives `v_caller := auth.uid()` and `RAISE 28000` on NULL | Confirmed verbatim (`075_transfer_workspace_ownership.sql:36-46`) | Migration 092 changes to `COALESCE(p_caller_user_id, auth.uid())` |
| Wrapper calls via `createServiceClient()` at `:365-370` | Confirmed (`:366-371`); does NOT forward a caller id | Add `p_caller_user_id: args.callerUserId` to the existing payload |
| `createServiceClient()` uses service-role key, `persistSession:false` | Confirmed (`lib/supabase/service.ts:155-161`) — `auth.uid()` is NULL under it | Root cause confirmed |
| Fix should mirror `accept_workspace_invitation` / `rename_organization` | Confirmed: `rename_organization` (091:50-53,60,116-119) is an exact same-file template | Adopt 091's RPC + grant shape verbatim |
| Issue assumes grant should "stay/become service_role-only" | **CORRECTION:** 075 currently grants the RPC to `authenticated` (`075:…GRANT EXECUTE … TO authenticated`), NOT service_role. The grant must be **flipped** to service_role-only, not merely "kept". | Migration 092 `REVOKE … FROM authenticated; GRANT … TO service_role` — see Security below |
| `callerUserId` must be added to the wrapper args | **Already present** (`TransferWorkspaceOwnershipArgs.callerUserId`, `:341`) and already plumbed by the route (`:67`) | No interface/route change needed — wrapper only |

## User-Brand Impact

**If this lands broken, the user experiences:** the "Transfer ownership" action in Team settings returns HTTP 500 with `rpc_failed` — a dogfood owner cannot hand off a workspace at all (current state on `main`), OR (if the grant is mis-flipped) any authenticated org member can forge `p_caller_user_id` and steal ownership of a workspace they do not own.

**If this leaks, the user's workflow/data is exposed via:** a forgeable `p_caller_user_id` reachable from PostgREST by `authenticated` would let any logged-in user POST a crafted RPC call with `p_caller_user_id = <victim owner uuid>`, transferring a victim's workspace ownership to themselves — full tenant takeover. This is the identical P1 privilege-escalation class fixed in #4762; the override param is **only** safe behind a service_role-only grant.

- **Brand-survival threshold:** single-user incident

**Rolling-deploy window (fails closed, no escalation):** the migrate job applies on merge before/with the app cutover. During the transient skew window, both directions fail closed to the *existing* HTTP 500 — (a) schema-applied/old-app: old 3-arg call resolves to the new 4-arg form with `p_caller_user_id` defaulted NULL → `COALESCE(NULL, auth.uid())` NULL under service-role → 28000 → 500 (identical to the pre-fix state); (b) new-app/schema-not-applied: 4-arg call against the not-yet-created form → PGRST202 → 500. No data loss and no `authenticated`-reachable forgeable overload exists at any instant because the DROP (of the 3-arg) and the service_role-only GRANT (of the 4-arg) land atomically in one migration. The flow is dogfood-gated (`isTeamWorkspaceInviteEnabled`) and was 100% broken before this PR, so the window regresses nothing.

> `requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work` begins. CPO has not been separately invoked (no Task tool in this environment); confirm CPO review or invoke at /work Phase 0. `user-impact-reviewer` will be invoked at review-time (handled by review/SKILL.md conditional-agent block).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — RPC signature widened.** Migration 092 declares `transfer_workspace_ownership(p_workspace_id uuid, p_new_owner_user_id uuid, p_attestation_text text, p_caller_user_id uuid DEFAULT NULL)`. Verified by migration-shape test regex (`/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.transfer_workspace_ownership\(\s*p_workspace_id\s+uuid\s*,\s*p_new_owner_user_id\s+uuid\s*,\s*p_attestation_text\s+text\s*,\s*p_caller_user_id\s+uuid\s+DEFAULT\s+NULL\s*\)/i`).
- [ ] **AC2 — caller resolved via COALESCE.** The RPC body declares `v_caller_user_id uuid := COALESCE(p_caller_user_id, auth.uid())`. Verified by test regex `/COALESCE\(\s*p_caller_user_id\s*,\s*auth\.uid\(\)\s*\)/i` against the function body extracted between `$$ … $$;`.
- [ ] **AC3 — grant flipped to service_role-only.** Migration 092 emits `REVOKE ALL ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid) FROM PUBLIC, anon, authenticated;` AND `GRANT EXECUTE ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid) TO service_role;` AND does **not** emit any `GRANT … TO authenticated` for the new 4-arg signature. Verified by three test assertions (REVOKE present, GRANT-to-service_role present, GRANT-to-authenticated absent for the 4-arg form).
- [ ] **AC4 — old 3-arg signature dropped.** Migration 092 emits `DROP FUNCTION IF EXISTS public.transfer_workspace_ownership(uuid, uuid, text);` (the old `authenticated`-granted overload) so no orphaned 3-arg, `authenticated`-reachable function remains. Verified by test regex.
- [ ] **AC5 — SECURITY DEFINER hygiene preserved.** The recreated function retains `LANGUAGE plpgsql`, `SECURITY DEFINER`, and `SET search_path = public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`). Verified by test.
- [ ] **AC6 — body invariants preserved.** The migration-shape test asserts every behavioral arm from 075 survives unchanged in 092: owner-gate `42501`, self-transfer `22023`, target-not-member `P0001`, target-already-owner `22023`, attestation `>= 16` chars, actor-GUC `set_config('workspace_audit.actor_user_id', …)`, promote-before-demote ordering, `organizations.owner_user_id` dual-write, `workspace_member_removals` revocation row, and the demoted-owner `user_session_state` clear. (Copy the 075 body verbatim; change only the DECLARE line + signature + grant.)
- [ ] **AC7 — wrapper forwards caller id.** `server/workspace-membership.ts` `transferWorkspaceOwnership` adds `p_caller_user_id: args.callerUserId` to the existing `.rpc("transfer_workspace_ownership", { … })` payload. Verified by a unit test that mocks `createServiceClient().rpc` and asserts the call args include `p_caller_user_id` equal to the supplied `callerUserId`.
- [ ] **AC8 — down migration.** `092_*.down.sql` exists, `DROP FUNCTION IF EXISTS public.transfer_workspace_ownership(uuid, uuid, text, uuid);` and recreates the 075 3-arg form (signature, body, `GRANT … TO authenticated`) for reversibility symmetry. Data is NOT reverted (transfers that occurred remain) — documented in the down-file header comment, matching 091's down convention.
- [ ] **AC9 — full vitest suite green.** `./node_modules/.bin/vitest run` (from `apps/web-platform/`) passes, including the new migration-shape test under `test/supabase-migrations/` and the wrapper test under `test/server/`. (Runner is vitest per `package.json:15` + `bunfig.toml [test] pathIgnorePatterns=["**"]` blocks bun discovery.)
- [ ] **AC10 — `tsc --noEmit` clean.** No type regression from the wrapper change. Confirmed at deepen-plan: `createServiceClient()` is untyped (no `<Database>` generic), so the `.rpc` payload is structurally typed — expected to pass trivially. (Guard retained.)

### Post-merge (operator)

- [ ] **AC11 — migration applied.** Migration 092 is applied to the dev and prd Supabase projects via the existing `web-platform-release.yml#migrate` job (path-filtered `on.push` to `main` touching `apps/web-platform/**` runs migrations). No separate operator SSH/CLI step — the merge IS the apply. **Automation:** baked into the release pipeline.
- [ ] **AC12 — live read-only verification (DEV only).** Against the **dev** Supabase project (NOT prd — `hr-dev-prd-distinct-supabase-projects`), confirm the grant matrix via read-only catalog introspection: `SELECT proname, proacl FROM pg_proc WHERE proname='transfer_workspace_ownership'` shows EXECUTE for `service_role` and NOT `authenticated` on the 4-arg overload, and no 3-arg overload remains. Run via `mcp__plugin_supabase_supabase__*` (dev project ref) — read-only, no synthetic rows created.

## Implementation Phases

### Phase 0 — Preconditions (no code)

1. Confirm latest migration number: `ls apps/web-platform/supabase/migrations/ | sort | tail -3` → highest is `091`; new migration is **092**. (Note: 075 has three distinct-suffix files at the same prefix, a historical convention; new work appends at the next sequential integer, so 092 is unambiguous.)
2. Re-read `091_rename_organization_and_default_names.sql:50-119` and `.down.sql` as the verbatim template for signature + COALESCE + grant + down shape.
3. Re-read `075_transfer_workspace_ownership.sql` in full — the entire `transfer_workspace_ownership` body is copied verbatim into 092 with **only** the DECLARE line, the signature, the DROP, and the GRANT changed. Do NOT touch the `update_workspace_member_role` or `anonymise_organization_membership` definitions that also live in 075 (they are not affected and re-emitting them in 092 would be scope creep + a second source of truth).
4. Confirm CPO sign-off (frontmatter `requires_cpo_signoff: true`) — invoke CPO domain leader at /work Phase 0 if not already covered, given single-user-incident threshold.

### Phase 1 — RED: failing tests first (per `cq-write-failing-tests-before`)

1. Create `test/supabase-migrations/092-transfer-ownership-caller-override.test.ts` modeled on `test/supabase-migrations/091-rename-organization.test.ts` (readFileSync + regex on source SQL; NO live Supabase — vitest mocks cannot catch GRANT mismatches per learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`, so the migration-shape test is the canonical plan-time gate). Assert AC1–AC6 + AC8. Strip line comments (`sql.replace(/--[^\n]*/g, "")`) before executable-code assertions, mirroring 091's test.
2. Add a wrapper test to `test/server/` (new file `transfer-ownership-wrapper.test.ts`, or extend an existing `workspace-membership`-scoped server test if one exists — grep first) that mocks `createServiceClient().rpc` and asserts the payload includes `p_caller_user_id: <callerUserId>` (AC7). Model on `test/server/rename-organization.test.ts`.
3. Run vitest; confirm new tests FAIL (RED) for the right reason (signature/COALESCE/grant/payload not yet present).

### Phase 2 — GREEN: migration + wrapper

1. Write `apps/web-platform/supabase/migrations/092_transfer_ownership_caller_override.sql`:
   - Header comment block (purpose, #4765, mirrors 091/085 service-role precedent, per `cq-pg-security-definer-search-path-pin-pg-temp` note).
   - `DROP FUNCTION IF EXISTS public.transfer_workspace_ownership(uuid, uuid, text);` (the old `authenticated`-granted 3-arg form).
   - `CREATE OR REPLACE FUNCTION public.transfer_workspace_ownership(p_workspace_id uuid, p_new_owner_user_id uuid, p_attestation_text text, p_caller_user_id uuid DEFAULT NULL) …` — body copied verbatim from 075 with `v_caller_user_id uuid := COALESCE(p_caller_user_id, auth.uid());`.
   - `REVOKE ALL ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid) FROM PUBLIC, anon, authenticated;` + `GRANT EXECUTE … TO service_role;` (NO grant to authenticated).
   - `COMMENT ON FUNCTION …` documenting the service-role-only forgeable-override rationale (copy 091's comment shape).
2. Write `apps/web-platform/supabase/migrations/092_transfer_ownership_caller_override.down.sql`: drop the 4-arg form, recreate the 075 3-arg form (signature + body + `GRANT … TO authenticated`), header note that data is not reverted.
3. Edit `server/workspace-membership.ts:367-371`: add `p_caller_user_id: args.callerUserId,` to the `.rpc` payload.
4. Run vitest → GREEN. Run `tsc --noEmit` → clean.

### Phase 3 — Verification

1. Full suite: `./node_modules/.bin/vitest run` from `apps/web-platform/` (AC9).
2. `tsc --noEmit` (AC10).
3. Defer live grant-matrix introspection to AC12 (post-merge, dev project, read-only).

## Files to Edit

- `apps/web-platform/server/workspace-membership.ts` — add one key (`p_caller_user_id: args.callerUserId`) to the `transfer_workspace_ownership` `.rpc` payload at `:367-371`.

## Files to Create

- `apps/web-platform/supabase/migrations/092_transfer_ownership_caller_override.sql`
- `apps/web-platform/supabase/migrations/092_transfer_ownership_caller_override.down.sql`
- `apps/web-platform/test/supabase-migrations/092-transfer-ownership-caller-override.test.ts`
- `apps/web-platform/test/server/transfer-ownership-wrapper.test.ts` (or extend an existing workspace-membership server test — grep `test/server/` for an existing transfer/workspace-membership wrapper suite first)

## Open Code-Review Overlap

None. (Queried `gh issue list --label code-review --state open` against the planned file paths — no open scope-out names `075_transfer_workspace_ownership`, `092_*`, or the `transferWorkspaceOwnership` wrapper. This issue #4765 is itself the deferred-scope-out being drained.)

## Domain Review

**Domains relevant:** Engineering (security), Legal/Compliance, Product.

### Engineering / Security

**Status:** reviewed (inline)
**Assessment:** Forgeable-override + grant flip is the load-bearing security decision. The new `p_caller_user_id` param is forgeable by any caller; it is ONLY safe because the RPC is granted service-role-only and the sole caller (`transferWorkspaceOwnership` via `createServiceClient`) forwards a route-verified `getUser()` id. The migration MUST flip the grant from `authenticated` (075's current state) to service_role-only in the same migration that adds the param — splitting them would leave a window where `authenticated` can reach a forgeable override (the exact #4762 P1). Mirrors mig 091:108-119 verbatim. `security-sentinel` should re-verify the grant matrix at review.

### Legal / Compliance

**Status:** reviewed (inline) — see GDPR / Compliance Gate below.
**Assessment:** The RPC writes a `workspace_member_attestations` row (Art. 5(2) accountability), a `workspace_member_removals` revocation row, and `workspace_member_actions` via the audit trigger (PA-20 actor GUC). The fix preserves all of these unchanged — it only corrects WHO is resolved as the actor (the real caller, formerly NULL → exception). No new processing activity, no new data category, no Article 30 register change. The audit attribution actually IMPROVES (formerly the flow was 100% broken, so no attestation rows were being written at all under service-role).

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no new user-facing surface. The "Transfer ownership" dialog (`transfer-ownership-dialog.test.tsx` exists) already ships; this fix makes the existing button work. No new page, modal, or flow. Mechanical escalation check: no new file matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`.

## GDPR / Compliance Gate

[skill-enforced: gdpr-gate at plan Phase 2.7]

Touches a `.sql` migration + an auth-adjacent owner-gate → regulated-data surface trigger fires. Advisory-only assessment: the fix does not add a processing activity, special-category (Art. 9) data, or a new lawful-basis question — it corrects the actor-resolution on an existing owner-gated RPC whose audit/attestation/revocation writes are unchanged. No Article 30 register entry needed (no new PA). No `compliance/critical` finding. At single-user-incident threshold, `user-impact-reviewer` runs at review-time per review/SKILL.md. **Disclaimer:** advisory only; not legal advice.

## Infrastructure (IaC)

No new infrastructure. Pure schema + application-code change against the already-provisioned Supabase projects; migration applies via the existing `web-platform-release.yml#migrate` pipeline on merge. Phase 2.8 trigger set not matched (no server, systemd unit, cron, vendor account, DNS, cert, secret, or firewall rule introduced). Skipped.

## Observability

```yaml
liveness_signal:
  what: HTTP 200 from POST /api/workspace/transfer-ownership on a real owner transfer (formerly 500)
  cadence: on-demand (dogfood, behind isTeamWorkspaceInviteEnabled)
  alert_target: none (dogfood surface; manual dev verification)
  configured_in: app/api/workspace/transfer-ownership/route.ts
error_reporting:
  destination: Sentry via reportSilentFallback (session-abort + socket-close arms already wrapped at workspace-membership.ts:393,410); RPC errors surface as the route's 500 JSON body (reason rpc_failed + detail)
  fail_loud: yes (route returns non-2xx with reason + detail; rpc_failed detail carries the SQLSTATE message)
failure_modes:
  - mode: caller id not forwarded (regression of this fix)
    detection: route returns 500 reason=rpc_failed detail contains "auth.uid() is NULL"
    alert_route: Sentry (unexpected rpc_failed) + 500 response
  - mode: grant left/reverted to authenticated (privilege-escalation regression)
    detection: migration-shape test AC3 fails in CI; pg_proc.proacl introspection (AC12) shows authenticated EXECUTE
    alert_route: CI red (pre-merge); AC12 read-only catalog probe (post-merge dev)
  - mode: caller_not_owner forged (mitigated by service-role-only grant)
    detection: RPC raises 42501; route returns 403 reason=caller_not_owner
    alert_route: 403 response (expected, caller-correctable — not Sentry-mirrored)
logs:
  where: Sentry (silent-fallback arms) + Next.js route response bodies
  retention: Sentry default project retention
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 -X POST https://app.soleur.ai/api/workspace/transfer-ownership
  expected_output: "307"
  # Cookieless POST → 307 redirect to /login proves the transfer-ownership
  # surface is reachable and auth-gated (not 404/500) without SSH or creds.
  # The functional fix (caller resolved, grant service_role-only) is covered
  # locally by the migration-shape + wrapper vitest suites and post-merge by
  # the verify/092 sentinel in the verify-migrations CI job.
```

## Test Scenarios

1. **Migration shape (092-…test.ts):** signature is 4-arg with `p_caller_user_id uuid DEFAULT NULL`; body uses `COALESCE(p_caller_user_id, auth.uid())`; REVOKE-from-authenticated + GRANT-to-service_role present; NO GRANT-to-authenticated for 4-arg; old 3-arg DROPped; SECURITY DEFINER + search_path pin retained; all 075 behavioral arms preserved.
2. **Down migration shape:** drops 4-arg, recreates 075 3-arg form with `GRANT … TO authenticated`.
3. **Wrapper unit (transfer-ownership-wrapper.test.ts):** mocked `.rpc` receives `p_caller_user_id` equal to `args.callerUserId`; existing self-transfer short-circuit (`:362`) and error-reason mapping unchanged.
4. **Full suite + tsc:** green.
5. **Post-merge dev introspection (AC12):** `pg_proc.proacl` shows service_role-only EXECUTE; no 3-arg overload remains.

## Risks & Mitigations

- **Risk: grant flip omitted or split into a later migration** → privilege escalation window. **Mitigation:** AC3 + AC4 enforce REVOKE-authenticated + GRANT-service_role-only + DROP-3-arg in the SAME migration; CI fails if absent. See Precedent-Diff Gate below (identical to 091/085 grant matrix).
- **Risk: Supabase generated types narrow `.rpc` args** so the 4th param fails `tsc`. **RESOLVED at deepen-plan:** `createServiceClient()` calls `createClient(...)` with NO `<Database>` generic (`lib/supabase/service.ts:155-166`) — the client is untyped, so `.rpc("transfer_workspace_ownership", { … })` accepts an arbitrary payload. Adding `p_caller_user_id` causes NO `tsc` regression. No generated `database.types.ts` for app RPCs exists in the repo (only third-party `node_modules` `.types.ts` files). AC10 remains as a guard but is expected to pass trivially.

### Precedent-Diff Gate (deepen-plan Phase 4.4)

Pattern-bound behaviors in this plan: (d) RPC permissioning + SQL `SECURITY DEFINER`. Established canonical form exists — verified against two sibling migrations.

**Caller-resolution + grant matrix (the load-bearing pattern):**

| Aspect | `transfer_workspace_ownership` 075 (current, BROKEN) | 092 (this plan) | Precedent `rename_organization` 091:50-119 | Precedent `accept_workspace_invitation` 085:269-270 |
| --- | --- | --- | --- | --- |
| Caller derivation | `v_caller := auth.uid()` (NULL under service-role) | `v_caller := COALESCE(p_caller_user_id, auth.uid())` | `COALESCE(p_caller_user_id, auth.uid())` (091:60) | `COALESCE(p_caller_user_id, auth.uid())` |
| Override param | none | `p_caller_user_id uuid DEFAULT NULL` (4th) | `p_caller_user_id uuid DEFAULT NULL` (091:53) | `p_caller_user_id uuid DEFAULT NULL` |
| REVOKE | `FROM PUBLIC, anon, authenticated` (075:156) | `FROM PUBLIC, anon, authenticated` | `FROM PUBLIC, anon, authenticated` (091:116) | `FROM PUBLIC, anon, authenticated` (085:269) |
| GRANT | **`TO authenticated`** (075:158 — the bug surface) | **`TO service_role`** (flip) | `TO service_role` (091:118-119) | `TO service_role` (085:270) |
| search_path pin | `public, pg_temp` | `public, pg_temp` (unchanged) | `public, pg_temp` | `public, pg_temp` |

092 adopts the 091/085 shape **verbatim**. The single divergence from 075 that is NOT a verbatim copy is the GRANT target flip (`authenticated` → `service_role`) — and that flip is the security fix, not a regression: it is required precisely because the new param is forgeable (see User-Brand Impact + Engineering/Security domain review).

**Multi-clause predicate reading (the owner-gate, per deepen-plan SQL-predicate check):** the gate at 075:48-58 (preserved in 092) is `v_is_owner := EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id = p_workspace_id AND user_id = v_caller_user_id AND role = 'owner' FOR UPDATE); IF NOT v_is_owner THEN RAISE 42501`. All three operands restated: (a) `workspace_id = p_workspace_id` scopes to the target workspace; (b) `user_id = v_caller_user_id` — now resolved via COALESCE, so it is the route-verified caller (not NULL); (c) `role = 'owner'` — gate passes iff the caller currently holds owner. The `FOR UPDATE` row-lock prevents two concurrent transfers from both reading themselves as owner under READ COMMITTED. The COALESCE change alters ONLY operand (b)'s input source (param-override preferred over the always-NULL `auth.uid()`); the gate's three-clause conjunction is otherwise identical to 075.

**Scheduled-work check:** N/A — this plan introduces no cron/recurring job (Inngest cron functions exist in the repo but none is added here).
- **Risk: copying the 075 body introduces a transcription drift** in one of the behavioral arms. **Mitigation:** AC6 pins every arm via regex; copy verbatim, change only the DECLARE/signature/grant/DROP lines.
- **Risk: re-emitting `update_workspace_member_role` / `anonymise_organization_membership`** (also defined in 075) creates a second source of truth. **Mitigation:** 092 touches ONLY `transfer_workspace_ownership` (Phase 0 step 3).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with concrete artifacts/vectors + `single-user incident` threshold.)
- **Supabase generated types (RESOLVED):** `createServiceClient()` uses an untyped `createClient(...)` (no `<Database>` generic, `lib/supabase/service.ts:155-166`), so the `.rpc` payload is not schema-narrowed and adding `p_caller_user_id` does not break `tsc`. No app-RPC `database.types.ts` exists in the repo. No types update needed — mirrors the `rename_organization` precedent (PR #4762), which also added a `p_caller_user_id` key to an untyped service-client `.rpc` call without a types change.
- **Migration numbering:** 075 has three distinct files at the same prefix (`075_conversation_visibility`, `075_transfer_workspace_ownership`, `075_workspace_invitations`) — a historical batch convention, not a collision to replicate. New work appends at the next sequential integer (092).
- **vitest cannot catch GRANT mismatches** (mocks resolve `.rpc` to `vi.fn()` without a real DB) — per learning `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md`. The migration-shape regex test (AC1–AC6) is the canonical plan-time gate; AC12 read-only introspection is the post-merge confirmation. Do NOT rely on an integration test against a live DB to catch the grant, and do NOT run synthetic-user integration suites against prd (`hr-dev-prd-distinct-supabase-projects`).
- The route ALREADY passes `callerUserId` and the args interface ALREADY has it — resist the temptation to "add" plumbing that exists. The wrapper is the only TS edit.

## Alternative Approaches Considered

| Approach | Why rejected |
| --- | --- |
| Keep `auth.uid()`-only gate; switch the wrapper to a per-tenant JWT client instead of service-role | The wrapper deliberately uses service-role for the session-abort + socket-close side effects and matches the sibling membership RPCs' invocation mode. Switching the client is a larger blast radius and diverges from the 091/085 precedent. Rejected. |
| Add `p_caller_user_id` but leave grant at `authenticated` | Privilege escalation: any authenticated user could forge the override via PostgREST and steal ownership. The #4762 P1 class. Rejected — grant MUST flip to service_role-only. |
| `CREATE OR REPLACE` in place without DROPping the 3-arg overload | Postgres treats the 4-arg form as a distinct overload; the old 3-arg `authenticated`-granted function would remain reachable. Must DROP the 3-arg form. |

## Deferral Tracking

No deferrals. The entire fix lands in one PR. (This plan itself drains deferred-scope-out #4765.)
