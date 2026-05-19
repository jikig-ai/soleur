---
date: 2026-05-18
topic: supabase-custom-access-token-hook-discriminator
category: integration-issues
module: lib/supabase/tenant.ts + supabase/migrations/047-050
status: solved
prs: [#3983]
issues: [#3363]
related_learnings:
  - 2026-05-18-vendor-token-mint-content-carrier-patterns.md
  - 2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md
---

# Supabase Custom Access Token Hook — runtime vs dashboard OTP discrimination

## Problem

Issue #3363 swapped HS256 runtime-JWT minting (Node-side `createHmac` with `SUPABASE_JWT_SECRET`) for asymmetric ES256 via Supabase's Custom Access Token Hook. The plan and ADR-033 §0.4 pre-committed the hook gate as:

```sql
IF event->>'authentication_method' <> 'otp' THEN
  RETURN jsonb_build_object('claims', event->'claims');  -- pass-through
END IF;
-- ... runtime mint logic ...
```

The Phase 0.4 probe captured `amr=[{method:"otp"}]` from the runtime `auth.admin.generateLink + verifyOtp` flow and concluded the gate was sufficient. The plan-review panel signed off. Migrations 047/048 applied to dev. Tenant code rewritten. Tests passing. Branch ready to ship.

**Phase-4 `/soleur:review` then surfaced a P1:** Soleur's user-facing dashboard (`components/auth/login-form.tsx:83`, `app/(auth)/signup/page.tsx:74`) uses `supabase.auth.signInWithOtp({email})` + `verifyOtp({token, email, type:"email"})` — structurally identical to the runtime path at the GoTrue server level. The "otp" gate could not discriminate them. Every dashboard OTP login was getting hook-rewritten with `aud='soleur-runtime'` and `exp=600s` (10-min auto-logout). **Single-user-incident threshold violation.**

## Root cause

**Supabase's Custom Access Token Hook event payload contains NO field that distinguishes admin-initiated `generateLink+verifyOtp` from user-initiated `signInWithOtp+verifyOtp`.** Both produce identical claims structure modulo per-call randomness. Empirical probe against dev (full output below):

| Field | Runtime path | Dashboard path |
|---|---|---|
| `aud` | `soleur-runtime`* | `soleur-runtime`* |
| `amr[0].method` | `otp` | `otp` |
| `app_metadata.providers` | `["email"]` | `["email"]` |
| `aal` | `aal1` | `aal1` |
| `role` | `authenticated` | `authenticated` |
| `is_anonymous` | `false` | `false` |
| `exp - iat` | `600`* | `600`* |
| `jti`, `session_id` | per-call random | per-call random |

*both rewritten — the bug.

The Supabase docs ([Custom Access Token Hook spec](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook)) define the event as exactly three fields: `user_id`, `claims`, `authentication_method`. No `flow_id`, no `admin_initiated`, no discriminator. The ADR-033 §0.4 gate decision was sound for projects using **password-based** dashboard auth; it silently breaks for any project that uses OTP-based dashboard auth (which is increasingly common as products drop passwords).

## Solution — marker-table pattern

Introduce a per-user marker table that the Node code UPSERTs immediately before its `generateLink` call. The hook atomically DELETEs the row inside its critical section; only consumption unlocks the mint path. Dashboard logins never UPSERT, so the DELETE finds no row → pass-through.

### Migration 049 — marker table

```sql
CREATE TABLE IF NOT EXISTS public.runtime_mint_intent (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

ALTER TABLE public.runtime_mint_intent ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.runtime_mint_intent FROM PUBLIC, anon, authenticated;
GRANT INSERT ON TABLE public.runtime_mint_intent TO service_role;
GRANT UPDATE (created_at) ON TABLE public.runtime_mint_intent TO service_role;
GRANT SELECT, DELETE ON TABLE public.runtime_mint_intent TO supabase_auth_admin;
```

Three things to note:
- **Column-level UPDATE grant** — `service_role` cannot re-key `user_id`; only `created_at` can refresh under `ON CONFLICT DO UPDATE`.
- **ON DELETE CASCADE** — orphan-prevention + GDPR Art. 17 hygiene.
- **RLS enabled with zero policies** — defense-in-depth deny for anon/authenticated even if a future migration accidentally re-grants.

### Migration 050 — hook with atomic check-and-consume CTE

```sql
WITH consumed AS (
  DELETE FROM public.runtime_mint_intent
  WHERE user_id = v_user_id
    AND created_at > NOW() - INTERVAL '10 seconds'
    AND created_at <= NOW()
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM consumed) INTO v_intent_consumed;

IF v_auth_method <> 'otp' OR NOT v_intent_consumed THEN
  RETURN jsonb_build_object('claims', v_claims);
END IF;
-- ... precheck + jsonb_set logic ...
```

Three things to note:
- **Single-statement atomicity** — `DELETE ... RETURNING` inside a CTE acquires the row lock; two concurrent hook firings for the same `user_id` serialize and exactly one sees a non-empty `consumed`.
- **Bounded TTL + clock-forward guard** — `created_at > NOW() - INTERVAL '10 seconds'` AND `created_at <= NOW()`. The clock-forward bound defends against an accidental future-dated row (no exploit today since only service_role can write, but cheap belt-and-suspenders).
- **Defense-in-depth `'otp'` retention** — even if the marker were ever poisoned, non-OTP paths (password, oauth, refresh-token) stay pass-through.

### tenant.ts — UPSERT before `generateLink`

```ts
const { error: intentError } = await service
  .from("runtime_mint_intent")
  .upsert({ user_id: userId }, { onConflict: "user_id" });
if (intentError) {
  throw new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly");
}

const link = await service.auth.admin.generateLink({ type: "magiclink", email });
// ... verifyOtp on a TRANSIENT createServiceClient() to avoid singleton session-stash ...

const payload = decodeJwtPayloadUnsafe(jwt);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (typeof payload.jti !== "string" || !UUID_RE.test(payload.jti) || typeof payload.exp !== "number") {
  throw new RuntimeAuthError("jwt_mint", "Authentication unavailable; retry shortly");
}
```

UUID-shape jti check is load-bearing: it's the last line of defense if a multi-device race causes the losing device's `verifyOtp` to return a pass-through JWT lacking precheck-issued jti. Without UUID-shape validation, a future Supabase change that adds a non-UUID natural jti claim would silently bypass the `denied_jti` revocation surface.

## Residual race window

~700ms between tenant.ts UPSERT and the hook's DELETE inside verifyOtp. A dashboard verifyOtp firing for the same user_id within that window consumes the intent — that dashboard user receives runtime claims (10-min session). Probability per dashboard login: ~0.02% under steady-state founder load (24 mints/hr × 700ms × ~1 dashboard login/day). Bounded harm, self-recovering via re-login. Accepted per single-user-incident threshold.

Considered alternative: shadow-user (separate `runtime+<uuid>@soleur.local` auth.users row per founder). Race-free by physical separation, but ~500 LOC + backfill migration + tenant-isolation surface updates. Disproportionate for a 0.02% bounded-harm vector at alpha scale. Tracked for V2 if rate of incidents materializes.

## Empirical verification protocol

Both before-fix and after-fix probes ran a synthetic two-path comparison from one process against dev. Re-runnable by future operators:

```js
// Mint via token_hash (admin runtime path):
const { data } = await admin.auth.admin.generateLink({ type: "magiclink", email });
const v = await client.auth.verifyOtp({ token_hash: data.properties.hashed_token, type: "email" });
const runtime = decode(v.data.session.access_token);

// Mint via 6-digit email_otp (user-facing dashboard path):
const { data: d2 } = await admin.auth.admin.generateLink({ type: "magiclink", email });
const v2 = await client.auth.verifyOtp({ token: d2.properties.email_otp, email, type: "email" });
const dashboard = decode(v2.data.session.access_token);
```

`admin.generateLink({type:"magiclink"})` returns BOTH `properties.hashed_token` (long, token_hash path) and `properties.email_otp` (6-digit, dashboard path). One call → two consumption shapes → controlled A/B.

After-fix expected:
- Runtime (UPSERT performed) → `aud=soleur-runtime`, `exp-iat=600`, UUID-shape jti
- Dashboard (no UPSERT) → `aud=authenticated`, `exp-iat=3600`, no jti

## Key insights

1. **Plan-time assumptions about hook event payloads must be empirically probed against the actual flows used in the project.** Soleur's dashboard uses OTP because we deprecated passwords. The plan reviewers assumed dashboard = password (the documented Supabase default in their examples). Don't trust the docs' canonical setup — probe what your product actually does.
2. **Supabase Custom Access Token Hook event payload is intentionally minimal.** Don't expect new discriminator fields. If you need to distinguish admin-initiated from user-initiated, ship a marker table; the hook can't tell from the event alone.
3. **Atomic single-statement check-and-consume** (DELETE...RETURNING in CTE) is the Postgres-idiomatic primitive for race-free marker consumption. Don't try SELECT-then-DELETE — it races.
4. **The "soleur:review" Phase-4 gate caught what plan-review missed.** Plan-review verified the gate logic; security-sentinel verified the gate against ACTUAL caller surfaces. Both are necessary; neither is sufficient alone.
5. **Defensive UUID-shape claim validation** at the consumer boundary catches future provider drift cheaply.

## Session Errors

**Leak-1 — Playwright snapshot file token leak (sbp_6e41…838a).** Vector: `browser_click` on the dashboard's "Generate token" button auto-emitted a snapshot file (`.playwright-mcp/*.yml`) containing the DOM, including the cleartext Mgmt API token in the textbox; I then grep'd the file, surfacing it to the conversation transcript. Recovery: revoked via dashboard (More Options → Delete → Confirm); verified 401 via `gh api`; shredded the snapshot file. **Prevention:** the vendor-token-mint learning already prescribes `browser_evaluate(filename:)` from the FIRST attempt to keep tokens out of the auto-snapshot path. Hook hardening proposal: PreToolUse hook on `mcp__playwright__browser_click` that detects a target containing "token"/"key"/"secret" in its accessibility-name and emits a stderr breadcrumb saying "prefer browser_evaluate(filename:) for credential capture".

**Leak-2 — Doppler CLI stdout echo (`doppler secrets {set,delete}`).** Vector: BOTH `set` and `delete` echo secret material to stdout by default. `set` echoes the just-set value; `delete` renders the post-deletion **surviving-secrets table**, which contains value chunks from OTHER secrets in the same config — the #4029 X_API_SECRET leak vector (PR #3983 post-merge cleanup ran `doppler secrets delete SUPABASE_JWT_SECRET -c prd --yes` and the surviving-secrets table dumped meaningful portions of `X_API_SECRET` into the conversation transcript). Recovery (Leak-2 original): revoked via dashboard; Mgmt API 401 post-revoke confirmed. Recovery (#4029 / 2026-05-18): X_API_SECRET regenerated at the X Developer Portal; Doppler `prd` + GitHub Actions repo secret updated via the `scripts/rotate-x-api-secret-bootstrap.sh` chain. **Correction (2026-05-18):** the previous version of this entry claimed "no `--silent`/`--quiet` flag exists" — that claim was empirically false. Both `set` and `delete` accept the global `--silent` flag (verified locally via `doppler --help` Global Flags: `--silent disable output of info messages`; `doppler secrets set --help` and `doppler secrets delete --help` both surface it). **Prevention:** the canonical pattern is `--silent` (primary, in-CLI, single-purpose) PLUS trailing `>/dev/null 2>&1` (belt-and-suspenders against stderr drift or future CLI behavior change). For `set`, also pass `--no-interactive` (`set` accepts it; `delete` does NOT — `delete` uses `-y/--yes`; this asymmetric flag-set is its own muscle-memory trap). For post-change verification, prefer the Doppler dashboard Audit tab (`dashboard.doppler.com → Audit`) over CLI stdout — the dashboard is the canonical, leak-free read surface. Hook hardening: PreToolUse hook `prod-write-defer-doppler-secrets-stdout` in `.claude/hooks/prod-write-defer-gate.sh` matches BOTH `doppler secrets set` AND `doppler secrets delete` against configs `{prd|prd_terraform|dev|ci}`, deferring the call for explicit operator approval so the operator can add `--silent`/`>/dev/null 2>&1` before proceeding. Widened 2026-05-18 via #4029 from the original `set`-only / `prd[_terraform]`-only shape.

**Migration 048 FK violation.** A DO-block self-test embedded in the migration tried to INSERT a synthesized UUID into `mint_rate_window` to exercise the rate-limit raise; the FK `mint_rate_window.founder_id → auth.users.id` rejected it. Recovery: replaced behavioral self-test with `pg_get_functiondef`-based compile probe checking for `'45001'` in the function body. **Prevention:** migration self-tests must use compile-shape probes (pg_get_functiondef, pg_proc inspection) rather than synthesized-row inserts — FKs make synthesized fixtures fail.

**Supabase REST vs supabase-js shape mismatch.** Operator-facing REST returns `hashed_token` at the response root; the supabase-js client wraps it under `.properties.hashed_token`. Recovery: documented in ADR-033 §0.2; tenant.ts uses the supabase-js path, runbook curl examples use the root path. **Prevention:** when documenting a Supabase admin-API flow that spans both REST (runbook) and supabase-js (tenant code), explicitly note the shape divergence in the ADR.

**CWD drift via `cd /tmp`.** Scratch operations in `/tmp` reset the bash session's working directory to the bare-repo root for subsequent commands; relative paths broke. Recovery: switched to absolute paths. **Prevention:** never `cd` to `/tmp` during a worktree session — write scratch files to absolute paths instead.

**Singleton session-stash bug.** `service.auth.verifyOtp` calls `GoTrueClient._saveSession` which stashes the resulting JWT in the supabase-js client's in-memory auth state, even with `persistSession: false`. Subsequent calls on the same singleton (`getServiceClient()`) used the founder's tenant JWT instead of the service-role key, yielding `42501 permission denied for function is_jti_denied`. Recovery: per-call `createServiceClient()` for the verifyOtp exchange; the singleton stays pristine for RPC traffic. **Prevention:** never call `auth.verifyOtp` on a shared service-role singleton client. Use a transient throw-away client. Already documented in the tenant.ts prose at the verifyOtp call site.

**Vitest mock surface drift.** When tenant.ts gained two new method calls (`service.from("runtime_mint_intent").upsert()` and `createServiceClient().auth.verifyOtp`), the test mocks in `tenant-jwt-asymmetric.test.ts` and `tenant-jwt-refresh.test.ts` returned `undefined` for those properties → `TypeError: Cannot read properties of undefined (reading 'verifyOtp')`. Tests had to be updated in lockstep. **Prevention:** when adding a new client-method call in the SUT, immediately grep `vi.mock("@/lib/supabase/service"` and audit every mock for the new shape. Or: extract a single canonical mock helper (e.g., `test/helpers/supabase-mocks.ts`) so the surface is updated once.

**GoTrue per-IP rate-limit cascade.** Running 15 tenant-isolation suites under `TENANT_INTEGRATION_TEST=1` exhausted Supabase's `RATE_LIMIT_TOKEN_REFRESH = 10/IP/hour`; downstream suites failed wholesale. Recovery: `test/helpers/mint-once.ts` amortizes 1-2 real mints per suite into a shared cache via `_setMintFnForTest`. **Prevention:** any integration suite that exercises the runtime mint path must amortize via the mint-once helper. Add a `RATE_LIMIT_TOKEN_REFRESH` budget note to the tenant-isolation README.

**supabase-service test timeout.** Eager `import "@/server/observability"` (pino + sentry init) added 3s to vitest's `resetModules()` cycle; first test hit the 5000ms vitest default. Recovery: lazy-import inside the `probeHookRegistration` body so the cost is only paid when the probe runs (production NODE_ENV + Mgmt API token present). Latency dropped to 416ms. **Prevention:** any module that imports heavy observability deps should lazy-import them inside the call path that actually needs them, not at module top.

**psql unavailable on host.** No `psql` binary on the dev host; couldn't run migrations against dev via standard shell. Recovery: `npm install --no-save pg` from worktree root + transient Node script using `pg.Client`. **Prevention:** the apply-migrations script (`apps/web-platform/scripts/apply-migrations.mjs`) already uses the `pg` module via the project's transitive deps. Use it instead of ad-hoc psql. If a new helper is needed, write it once into `scripts/`.

**Doppler project misnamed (`-p web-platform` vs `-p soleur`).** The Doppler project is named `soleur` (one project for all services); `web-platform` is a config within it. First two attempts to invoke doppler used `-p web-platform` and got "project not found". **Prevention:** the project name is documented in `apps/web-platform/CLAUDE.md` and `knowledge-base/engineering/ops/runbooks/doppler-*.md`; reference them before invoking doppler in a new shell.

**Accidentally deleted tracked root `package-lock.json`.** `npm install --no-save pg` from the worktree root created `<worktree>/package-lock.json`. Misread it as a stray artifact (the actual stray was at `apps/web-platform/package-lock.json`, which IS in `.gitignore` per Next.js workspace conventions). `rm`'d it → `git status` showed `D package-lock.json` → restored via `git checkout HEAD --`. **Prevention:** before deleting any "stray" file, `git ls-files <path>` to confirm it's not tracked. Don't trust visual recognition of "stray" files in repos with unusual structure (bare-repo + worktree + nested Next.js app).

**migration-rpc-grants.test.ts failure on CREATE OR REPLACE.** The file-parse lint requires REVOKE statements for `PUBLIC + anon + authenticated` to be present in the migration file even for `CREATE OR REPLACE FUNCTION` (where Postgres preserves prior grants). Recovery: added idempotent REVOKE/GRANT to migration 050. **Prevention:** the test docstring already states this; future CREATE OR REPLACE migrations must include REVOKE/GRANT defensively.

**dsar-allowlist-completeness.test.ts failure on new table.** Any new table with FK to `auth.users` (or transitive) must appear in either `DSAR_TABLE_ALLOWLIST` or `DSAR_TABLE_EXCLUSIONS` in `server/dsar-export-allowlist.ts`. Recovery: added `runtime_mint_intent` to exclusions with rationale. **Prevention:** the test message already names the file to edit; treat it as a hard pre-commit gate when adding any user-FK table.

**Phase-4 review escalation (the headline).** A plan-time assumption (`authentication_method='otp'` discriminates runtime from dashboard) survived plan-review + Phase 0.4 empirical validation but turned out to be wrong for Soleur's actual product surface (`signInWithOtp`-based dashboard login). The /soleur:review security-sentinel agent caught it; the empirical re-probe in Phase 4 confirmed; the marker-table pivot resolved it. **Prevention:** see Key Insights #1 + #4 above. Workflow proposal: when an ADR captures a plan-time empirical probe, the review-phase security agent should cross-check the assumption against ACTUAL caller surfaces in the codebase, not just against the probe itself.
