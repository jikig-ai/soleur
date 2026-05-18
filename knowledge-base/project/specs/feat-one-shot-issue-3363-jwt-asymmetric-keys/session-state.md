# Session State — feat-one-shot-issue-3363-jwt-asymmetric-keys

## Status
**PAUSED at Phase 0 boundary.** Plan + ADR-033 (Decision: Option C) + Phase 0.1 probe committed and pushed to draft PR #3983. Ready for fresh-session continuation of Phase 0.2 onward.

## Plan Phase — complete
- Plan file: `knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md` (664 lines after cuts)
- ADR-033: `knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md` (Status: Accepted, Decision: Option C)

### Plan-review panel (5 agents) — complete
- DHH: SHIP-WITH-CUTS
- Kieran: ACCEPT-WITH-FIXES
- Code-simplicity: CUT-NEEDED (604 → 340 estimated, actual 604 → 664 net because additive runbooks)
- Architecture-strategist: SHIP-WITH-RUNBOOK-ADDED
- Spec-flow-analyzer: SHIP-WITH-FLOW-FIXES

### Cuts applied (consolidated panel findings)
- DELETED `runtime_jwt_hook_audit` table (§2.9) — `auth.audit_log_entries` already exists
- DELETED `EXCEPTION WHEN OTHERS` defensive-pass-through block in migration 047
- SWITCHED `SQLERRM ILIKE '%mint_rate_exceeded%'` → `SQLSTATE '45001'` matching; added migration 048 to update `precheck_jwt_mint` to raise with ERRCODE 45001
- PRE-COMMITTED Phase 0.4 fallback: hook gate is `v_auth_method <> 'otp'` (not `aud=soleur-runtime`)
- DELETED §3.2 Terraform fork, `sb_secret_*` paragraphs, `precheck_jwt_mint` rename mention, `sensitive-keys.ts` retention discussion
- ADDED Rollback Runbook (with HS256-verifier-retention citation gap noted)
- ADDED Deploy-Order Runbook (prd) with `[ack-needed]` gates
- ADDED Phase 5.0 prd-side mirrors of Phase 0.1/0.2/0.4 probes
- ADDED hook pass-through test + hook signature test (`test/supabase-migrations/047-custom-access-token-hook.test.ts`)
- ADDED `getServiceClient` hard-fail at startup in production NODE_ENV (planned, not implemented)

## Phase 0 Probes — partial

### Phase 0.1 — DONE
- Probed: `curl $NEXT_PUBLIC_SUPABASE_URL/auth/v1/.well-known/jwks.json`
- Result: **asymmetric ES256 already enabled on dev**
- kid: `3605e4cb-db60-461d-a122-969e7671f66b`
- Phase 0.1.a (Dashboard "Enable JWT Signing Keys" click on dev) **NOT needed**

### Phase 0.2 — NOT RUN
Needs: `NEXT_PUBLIC_SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (in Doppler), plus a real fixture email (auth.users row). Consumes 1 GoTrue generate+verify cycle, 1 audit row, 1 auth.sessions row.

### Phase 0.3 — BLOCKED
Needs `SUPABASE_MGMT_API_TOKEN_DEV` (NOT in Doppler dev as of 2026-05-18; re-verified absent on session resume). Mint via Supabase Dashboard → Account → Access Tokens, store via Playwright MCP `browser_evaluate(filename: ...)` pattern (see `2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md`).

**Session-resume Playwright wedge note (2026-05-18, second session):** Playwright MCP showed `✓ Connected` on `claude mcp list` but `/mcp` reload returned `-32000`. Diagnosis: stale `SingletonLock` symlink pointing to dead PID 2556914 in `/home/jean/.cache/playwright-mcp-profile/`. **Cleanup done this session:** killed stale `playwright-mcp` PIDs (2334365, 2334569, 2334570) + removed `SingletonLock`/`SingletonCookie`/`SingletonSocket`. Direct `npx @playwright/mcp@latest --config=.claude/playwright-mcp.config.json` spawn works cleanly (silent wait-for-client). Subsequent `/mcp` reload STILL returned -32000 — suggests Claude Code session-state caches a dead handshake; only a full CLI restart re-handshakes. **Next session should `claude mcp list` first to verify status; if -32000 reappears, exit + relaunch `claude` rather than burn time debugging.**

### Phase 0.4, 0.5 — NOT RUN
- 0.4: Probe `authentication_method='otp'` gate empirically. Needs migration 047 deployed to a test schema (or fork the migration locally).
- 0.5: Latency baseline (10 cycles).

### Phase 0.6 — DEFERRED (decided 2026-05-18, second session)
Operator decision: defer 0.6 (60-cycle empirical rate-limit probe). Reason: wasteful (risks tripping per-IP limits affecting unrelated dev workflows) AND the precheck `60/hour` ceiling is the durable canary regardless. Record TOKEN_REFRESH=10/IP/hour + EMAIL_SENT=10/hour defaults in ADR-033 with Supabase docs citation. File follow-up tracking issue for empirical probe once observability surface exists to consume the data.

## What's left (for next session)

1. **Phase 0.2, 0.4, 0.5 probes** — populate ADR-033 with concrete numbers (latency p50/p95). Phase 0.3 needs Mgmt API token minted first (Playwright MCP path; see Session-resume Playwright wedge note above). Phase 0.6 deferred — record default rate-limit values from Supabase docs and file follow-up issue.
2. **Migration 047** — `apps/web-platform/supabase/migrations/047_custom_access_token_hook.sql` (~60 lines SQL)
3. **Migration 048** — `apps/web-platform/supabase/migrations/048_precheck_jwt_mint_sqlstate.sql` (CREATE OR REPLACE on `precheck_jwt_mint` with ERRCODE 45001)
4. **Apply migrations to dev** — via Supabase MCP or Doppler `DATABASE_URL_POOLER` fallback chain
5. **Register hook via Mgmt API** — needs SUPABASE_MGMT_API_TOKEN in Doppler (mint a fresh one if absent)
6. **Phase 1 RED tests** — 4 new test files:
   - `tenant-jwt-asymmetric.test.ts`
   - extend `tenant-jwt-deny.tenant-isolation.test.ts`
   - extend `tenant-jwt-refresh.test.ts`
   - new `test/supabase-migrations/047-custom-access-token-hook.test.ts` (pass-through + signature)
7. **Phase 2 GREEN — `tenant.ts` rewrite**: delete `getJwtSecret`, delete `createHmac` block, swap to `generateLink+verifyOtp`, add `decodeJwtPayloadUnsafe` helper, add `getServiceClient` startup probe of `auth.hooks`
8. **16 tenant-isolation suite re-run** under the new substrate
9. **Phase 3** — `npx tsc --noEmit`, lint, full test suite
10. **Phase 4** — `/soleur:gdpr-gate`, `/soleur:compound`, then `/soleur:ship`
11. **Phase 5.0** — prd-side mirrors of Phase 0 probes, `[ack-needed]`
12. **Phase 5.1+** — apply 047+048 to prd, register hook on prd, deploy Node code, delete Doppler SUPABASE_JWT_SECRET

## How to re-enter

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-issue-3363-jwt-asymmetric-keys
# /soleur:go would detect the worktree and offer to continue
# Or jump straight into:
/soleur:work knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md
```

The lease has been released so `cleanup-merged` will reap this worktree once PR #3983 merges. To keep the lease active for the next session, re-create on entry:

```bash
SOLEUR_SKILL_NAME=one-shot SOLEUR_EXPECTED_DURATION_MIN=240 \
  bash .claude/hooks/lib/session-state.sh acquire_lease feat-one-shot-issue-3363-jwt-asymmetric-keys
```

## Artifacts in place
- Worktree: `.worktrees/feat-one-shot-issue-3363-jwt-asymmetric-keys/`
- Branch: `feat-one-shot-issue-3363-jwt-asymmetric-keys`
- Draft PR: [#3983](https://github.com/jikigai/soleur/pull/3983)
- Commits on branch: `503be0a8` (init), `af0707a5` (docs: plan + ADR-033), `afb9737c` (handoff snapshot), `<this commit>` (resume-2 deltas)
