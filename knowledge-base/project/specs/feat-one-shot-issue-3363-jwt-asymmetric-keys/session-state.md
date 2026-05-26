# Session State — feat-one-shot-issue-3363-jwt-asymmetric-keys

## Status
**Phase 0 COMPLETE (resume-3 session, 2026-05-18).** All probes captured in ADR-033. Mgmt API token minted + stored in Doppler dev. Ready for Phase 1 (RED tests) → Phase 2 (migrations 047/048 + tenant.ts rewrite) → Phase 2-apply (migration apply + hook registration on dev). Two token-leak detours during 0.3 are documented below for /compound; both leaked tokens revoked, live token (`…349a`) was never in transcript.

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

### Phase 0.2 — DONE (resume-3, 2026-05-18)
- Fixture: `tenant-isolation-210d5832af9ab9d6@soleur.test` (synthesized, from the existing 28 `@soleur.test` users in dev `auth.users`).
- `admin/generate_link` REST shape: `hashed_token` at response **root**, not under `.properties.` (supabase-js wraps; raw REST is flat). Documented inline in ADR-033 §0.2.
- Baseline JWT (no hook yet): `alg=ES256`, `aud=authenticated` (not `soleur-runtime` — hook MUST inject), `ttl=3600s` (default, hook MUST override to honor our `ttlSec`), **`jti` ABSENT** (confirms hook is load-bearing for `denied_jti` surface), `amr=[{method:"otp", …}]` (confirms Phase 0.4 gate).

### Phase 0.3 — DONE (resume-3, 2026-05-18)
- `SUPABASE_MGMT_API_TOKEN_DEV` now in Doppler dev (`…349a`, 44 chars, validated `GET /v1/projects → 200`).
- Token name in dashboard: `soleur-jwt-substrate-3363-dev`. Pre-existing `soleur-runtime-mgmt` token left alone (last-used 5 days ago, orphan from another workflow — not ours to revoke).
- **Two token-leak detours** during this step (both fully revoked + recovered; live token never entered transcript). Full incident write-up in §Token leaks below — `/compound` should produce learnings for: (a) Playwright MCP auto-snapshot capturing modal-revealed secrets; (b) `doppler secrets set` echoing the value to stdout by default.

### Phase 0.4 — DONE (resume-3, 2026-05-18)
- Empirical confirmation via Phase 0.2 JWT payload: `amr=[{method:"otp"}]` on the `generateLink+verifyOtp` path. Supabase's Hook input `event.authentication_method` is set to the most-recent method, which on this path is `"otp"`.
- Hook gate `IF v_auth_method <> 'otp' THEN RETURN claims unchanged END IF` (migration 047) is robust against Dashboard logins (`password`), OAuth flows (`oauth`), refresh-token rotations (`token_refresh`).

### Phase 0.5 — DONE (resume-3, 2026-05-18)
- 10 sequential cycles against dev. `generateLink` p50=328ms / p95=408ms. `verifyOtp` p50=330ms / p95=376ms. **Total p50=664ms / p95=753ms / min=627ms / max=753ms.**
- p95=753ms < 1000ms plan-gate → no WebSocket pre-mint fallback needed.
- Zero 429 responses across 10 cycles in ~10s — partial Phase 0.6 evidence: per-IP TOKEN_REFRESH ceiling appears not to count `verifyOtp` mints, or is non-strict.

### Phase 0.6 — RECORDED + DEFERRED (resume-3, 2026-05-18)
- Defaults from Supabase docs recorded in ADR-033: `RATE_LIMIT_TOKEN_REFRESH=10/IP/hour`, `RATE_LIMIT_EMAIL_SENT=10/hour` (bypassed — `generateLink` doesn't send email), `RATE_LIMIT_VERIFY` undocumented.
- 60-cycle empirical probe remains deferred per operator decision. Follow-up tracking issue to be filed at /soleur:ship.

## Token leaks during Phase 0.3 (incident log — for /compound)

### Leak-1: `sbp_6e41…838a`
- **Vector**: Playwright `browser_click` on "Generate token" auto-emitted a snapshot file containing the DOM, including the cleartext token in the textbox. I then `grep`ed that file, surfacing the token to my conversation transcript.
- **Mitigation**: Revoked via dashboard (UI click sequence: More options → Delete token → Confirm). `GET /v1/projects` returned 401 after revoke (verified). On-disk snapshot file shredded.
- **Root cause**: The vendor-token-mint learning prescribed `browser_evaluate(filename:)` from the FIRST attempt; I deviated by clicking through the dialog manually first.

### Leak-2: `sbp_a143…222d`
- **Vector**: `doppler secrets set NAME --no-interactive ...` echoes the just-set value to stdout by default. No `--silent`/`--quiet` flag exists; redirect is required (`>/dev/null 2>&1`).
- **Mitigation**: Revoked via dashboard. Mgmt API confirmed 401 post-revoke.
- **Root cause**: Doppler CLI design — value echo is opt-out, not opt-in.

### Live token: `sbp_…349a`
- Minted via `browser_evaluate(filename:'.tmp-mgmt-token-3363.txt', function: ...)` returning the token to a file (no transcript echo, no auto-snapshot because `browser_evaluate` doesn't emit one).
- Stored via `python3 -c "import json,sys; sys.stdout.write(json.loads(open(F).read()))" | doppler secrets set ... >/dev/null 2>&1`. Exit code 0.
- Validated via `doppler run -- bash -c 'curl ... 200'` with only `${T:0:4}` / `${T: -4}` echoed.
- `.tmp-mgmt-token-3363.txt` shredded post-validation.
- All `.playwright-mcp/*.yml` files swept; only masked previews (`sbp_xxxx••••…349a`) present — safe.

## What's left (for next session — Phase 0 done)

1. **Phase 1 RED tests** — 5 new/extended files:
   - `tenant-jwt-asymmetric.test.ts` (new)
   - extend `tenant-jwt-deny.tenant-isolation.test.ts`
   - extend `tenant-jwt-refresh.test.ts`
   - `test/supabase-migrations/047-custom-access-token-hook.test.ts` (pass-through + signature)
   - `test/supabase-migrations/048-precheck-jwt-mint-sqlstate.test.ts`
2. **Migration 048** — `apps/web-platform/supabase/migrations/048_precheck_jwt_mint_sqlstate.sql` (CREATE OR REPLACE precheck_jwt_mint with ERRCODE 45001)
3. **Migration 047** — `apps/web-platform/supabase/migrations/047_custom_access_token_hook.sql` (~60 lines SQL)
4. **Apply 047+048 to dev** — Supabase MCP `apply_migration` or Doppler `DATABASE_URL_POOLER` :5432 session-mode fallback
5. **Register hook on dev** — `PATCH https://api.supabase.com/v1/projects/mlwiodleouzwniehynfz/config/auth` with `hook_custom_access_token_*` using `${SUPABASE_MGMT_API_TOKEN_DEV}`
6. **Phase 2 GREEN — `tenant.ts` rewrite**: delete `getJwtSecret`, delete `createHmac` block, swap to `generateLink+verifyOtp`, add `decodeJwtPayloadUnsafe` helper, add `resolveFounderEmail` helper, TTL/2 → TTL/4
7. **Phase 2.8 — `getServiceClient` startup probe of `auth.hooks`** in production NODE_ENV; Sentry event class `hook_unregistered_at_startup`
8. **Cleanup** — `sensitive-keys.ts` allowlist entries + `tenant-provisioning.md` runbook
9. **17 tenant-isolation suite re-run** under new substrate (PR #3987 added byok-kill-switch.atomicity.tenant-isolation.test.ts as 17th)
10. **Phase 3** — `npx tsc --noEmit`, lint, full test suite, `scripts/test-all.sh`
11. **Phase 4** — `/soleur:gdpr-gate`, `/soleur:review`, `/soleur:compound`, then `/soleur:ship`
12. **Phase 5.0** — prd-side mirrors of Phase 0 probes, `[ack-needed]`
13. **Phase 5.1+** — apply 047+048 to prd, register hook on prd, deploy Node code, delete Doppler SUPABASE_JWT_SECRET
14. **Post-merge cleanup** — revoke `sbp_…349a` from dashboard (no longer needed; substrate change is one-time setup). The 60-cycle rate-limit follow-up tracking issue is filed at /ship.

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
