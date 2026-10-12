# Decision Challenges — feat-one-shot-9994-deleteuser-500s

Decisions surfaced during `soleur:plan` for #9994. Technical rulings were recorded
as `pending - assumed` at plan time (plan subagent had no Agent tool), then ruled
by a batched `soleur:engineering:cto` spawn on 2026-10-12 — all six assumptions
confirmed.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix shape: widen `tearDownTenantUser` sentinel + adopt in 5 defective suites (A) vs per-suite manual FK-reverse teardown (B) | technical | Ruled by CTO agent, 2026-10-12: confirm A - the parity-guarded `tearDownTenantUser` helper already runs the full 22-RPC anonymise sequence in production order and is the canonical path; per-suite manual FK-reverse is the proven drift source (#5582's 8-vs-23 reopening is cited in the helper's own docblock). |
| Fold in `workspace_id` insert repairs (conversations + messages) in cc-dispatcher + conversations-rail — adjacent defect, same red leg, different root cause | technical | Ruled by CTO agent, 2026-10-12: confirm fold in - mig 059 (`ALTER COLUMN workspace_id SET NOT NULL` on both `conversations` and `messages`) means the `supabase-dev` leg cannot go green while neither file supplies `workspace_id`, and neither file mentions the column anywhere. |
| Fold in `dsar-export-cross-tenant` (best-effort swallow → strict helper path) | technical | Ruled by CTO agent, 2026-10-12: confirm fold in - `dsar-export-cross-tenant.integration.test.ts:155-156` wraps raw `deleteUser` in a bare `try { } catch {` that silently leaks synthetic users; identical defect class in the same named verification leg. |
| `brand_survival_threshold: single-user incident` + `requires_cpo_signoff: true` for a test-only diff | technical | Ruled by CTO agent, 2026-10-12: confirm keep - the diff widens a write-boundary sentinel that mirrors the Art-17 erasure cascade in `server/account-delete.ts`, so a malformed widening could mask a real erasure regression; `single-user incident` + CPO sign-off is the correct conservative carry. |
| Sentinel scope: `test/*.integration.test.ts` + `test/helpers/` only, `test/server/**` deferred to #10096 | technical | Ruled by CTO agent, 2026-10-12: confirm scoped - the grep census shows ~16 `test/server/**` carriers of the same call site (silent `.catch(() => {})` variants included), and folding them in now would enshrine a large allowlist that documents the defect rather than barring it; #10096 is the right vehicle. |
| Sentinel allowlist vs migrate the 4 working manual-FK-reverse suites to the helper | technical | Ruled by CTO agent, 2026-10-12: confirm allowlist - all four working suites run documented `anonymise_workspace_members`/`anonymise_workspace_member_actions` + explicit `workspaces`/`organizations` deletes with WORM-trigger comments, a deliberately different cleanup semantic (they remove solo-workspace/org cruft the helper leaves as NULL-owner rows), so migration would be churn without defect reduction. |

## Not Yet Specified candidates

(none — the plan's unknowns are implementation details, not product fog)
