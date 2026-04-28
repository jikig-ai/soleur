---
date: 2026-04-28
tags: [supabase, auth, ci, secrets, build-time-inlining, dual-source-of-truth, jwt, recurrence]
status: applied
issue: 3006
pr: 3007
predecessor: 2975
---

# Sign-in fully broken in prod — test-fixture anon-key JWT leaked into the production JS bundle via `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY`

## What happened

Every sign-in attempt on `https://app.soleur.ai/login` redirected to `/login?error=auth_failed` ("Sign-in failed. If you have an existing account, try signing in with email instead."). All four OAuth providers (Google, Apple, GitHub, Microsoft), email-OTP, and email/password were affected.

Sentry events (mirrored to Sentry by PR #2994 hours earlier) showed:

```
op: exchangeCodeForSession
message: "Invalid API key AuthApiError"
errorCode: <empty>  errorName: <empty>  errorStatus: <empty>
```

Forensics:

- The deployed JS bundle had `NEXT_PUBLIC_SUPABASE_ANON_KEY` baked in with `ref=test` (test fixture JWT) instead of the canonical prd anon key with `ref=ifsccnjhymdmidffkzhl`.
- Supabase's auth API rejected every request as "Invalid API key" because the JWT issuer ref didn't match the routed project.
- Hot-fix at 2026-04-28T16:56:28Z: rotated the GitHub repo secret `NEXT_PUBLIC_SUPABASE_ANON_KEY` to the canonical Doppler value and triggered a fresh release.

This is the **second incident in the same class within 24 hours** — predecessor (PR #2975) shipped guardrails for `NEXT_PUBLIC_SUPABASE_URL` after the same operator-paste-during-rotation surface broke OAuth on 2026-04-27. The fix was URL-only; the symmetric anon-key surface was left undefended.

## Why it happened

`apps/web-platform`'s production image is built by `.github/workflows/reusable-release.yml`. The build step consumes `${{ secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY }}` via Docker `build-args`. Next.js inlines `process.env.NEXT_PUBLIC_*` references into client chunks at build time via Webpack `DefinePlugin`. Once a chunk is built, the value is **immutable**; runtime env changes do not flow through.

`apps/web-platform/test/*` uses placeholder-shaped JWTs in 4 files (`byok.integration.test.ts`, `agent-env.test.ts`, `fixtures/qa-auth.ts`, `server/health-supabase.test.ts`). The most plausible operational origin is operator copy-paste during the same credentials-rotation window that produced the URL incident — pasting a test-fixture JWT into the GitHub repo secret slot.

PR #2975's URL gates did NOT cover the anon-key surface because:

- `reusable-release.yml`'s Validate step only checked `NEXT_PUBLIC_SUPABASE_URL`.
- `verify-required-secrets.sh`'s `SUPABASE_URL_RE` was URL-only.
- `validate-url.ts` is hostname-regex-shaped — fundamentally different shape contract from a JWT (regex vs. base64url claims). Extending it would have been wrong.
- Preflight Check 5 only grepped for Supabase hostnames, not for inlined JWTs.

Each `NEXT_PUBLIC_*` build-arg is its own structural surface. The URL fix was correct for URLs but structurally insufficient as a class fix.

## Fix

PR #3007 ships the symmetric guardrail set, mirroring PR #2975's four-layer defense for the anon-key surface:

1. **Pre-build CI assertion** (`.github/workflows/reusable-release.yml`): a step `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` runs after the URL Validate step and before `docker/build-push-action`. It decodes the JWT payload (base64url middle segment), parses claims via `jq`, and asserts:
   - `iss === "supabase"` (catches cross-vendor JWT paste — Auth0, Clerk, Stripe)
   - `role === "anon"` (load-bearing for security: rejects service-role-key paste, which would grant admin RLS bypass to every browser visitor)
   - `ref` matches `^[a-z0-9]{20}$` (canonical project-ref shape)
   - `ref` not in placeholder set (`test*`, `placeholder*`, `example*`, `service*`, `local*`, `dev*`, `stub*`)
   - `ref` matches the canonical first label of `secrets.NEXT_PUBLIC_SUPABASE_URL` (resolved via `dig +short CNAME` for `api.soleur.ai`)
2. **Runtime JWT-claims guard** (`apps/web-platform/lib/supabase/validate-anon-key.ts`): a sibling to `validate-url.ts` that exports `assertProdSupabaseAnonKey(rawKey, rawUrl)`. Same claims assertions as the CI step. **Gated on `process.env.NODE_ENV === "production"`** so the 4 anon-key-fixture test files are unaffected. `client.ts` calls it at module load alongside `assertProdSupabaseUrl`.
3. **Doppler-side shape check** (`apps/web-platform/scripts/verify-required-secrets.sh`): a new JWT-claims block after the URL shape check, asserting the same four claims so a placeholder-shaped value entered into Doppler `prd` also fails the secret-verification job.
4. **Preflight Check 5 Step 5.4** (`plugins/soleur/skills/preflight/SKILL.md`): extends the existing chunk-fetch (no new HTTP request) to grep the inlined `eyJ…` JWT in the deployed login chunk, decode the payload, and assert the same claims.

## Lesson

**The recurrence pattern matters.** When a class of incident produces a fix scoped to one variable in the class, the remaining variables must be tracked and prioritized — not deferred indefinitely. Issue #2980 (generalize to all 5 `NEXT_PUBLIC_*` build-args) was open at the time of the URL fix; the anon-key portion of #2980 should have been folded into PR #2975. Two separate brand-survival incidents in 24 hours instead of one.

**`role` claim distinction is load-bearing for security, not just correctness.** A Supabase service-role JWT is structurally identical to an anon JWT (same algorithm, same claim set, same length envelope). The only distinguishing field is `"role": "service_role"` vs `"role": "anon"`. If an operator pastes the **service-role key** into the `_ANON_KEY` slot, every browser session loads a JWT that bypasses Row-Level Security — silent data exfiltration class. The auth-break failure mode (test fixture) is self-evident and pages immediately; the role-confusion failure mode is silent and pages only when an attacker notices. The `role == "anon"` assertion in all four gates is the load-bearing defense for the worse failure mode.

**JWT shape gates ≠ JWT signature verification.** The validators do NOT verify the JWT signature. Anon keys are public; the signature check would require either embedding the project's signing secret (impossible) or a network call (defeats fail-fast at build time). Runtime auth is Supabase's responsibility; the gates are shape gates.

**Templatize, don't generalize.** Each `NEXT_PUBLIC_*` build-arg has a different shape contract (URL = hostname regex; anon key = JWT claims; Sentry DSN = URL with embedded project key; VAPID public key = base64url 65-byte EC point; GitHub App slug = lowercase-alpha string). A "generic NEXT_PUBLIC validator" is the wrong abstraction. The pattern this PR establishes — sibling validator module + CI step + verify-script block + preflight step + learning file — should be replicated per build-arg in #2980.

## Recurrence prevention

- **#2980** (generalize to remaining 4 `NEXT_PUBLIC_*` build-args) — re-prioritize. The pattern is now templated; folding in `SENTRY_DSN`, `VAPID_PUBLIC_KEY`, `GITHUB_APP_SLUG`, and `AGENT_COUNT` is mechanical work.
- **#2981** (Doppler-only build-args migration, Option B) — would eliminate the dual-source-of-truth class entirely (the underlying root cause of both #2979 and #3006). Defense-in-depth is a complement, not a substitute, for structural simplification.
- **PR #2994** (typed Sentry mirror for OAuth errors) — already landed. Reduced diagnosis time from "hours" to "minutes" by surfacing the exact Sentry breadcrumbs.

## Operator runbook (post-incident)

If the inlined anon-key JWT regresses to a placeholder/test-fixture value:

1. Decode the Doppler `prd` value to confirm the canonical key is still present:
   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
     | cut -d. -f2 | { read p; pad=$(( (4 - ${#p} % 4) % 4 )); \
       printf '%s' "$p$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '"iss=\(.iss) role=\(.role) ref=\(.ref)"'; }
   # Expected: iss=supabase role=anon ref=ifsccnjhymdmidffkzhl
   ```
2. If Doppler is correct, rotate the GitHub repo secret from Doppler:
   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
     | tr -d '\r\n' \
     | gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY --body -
   ```
3. Trigger a fresh release workflow run. The new CI Validate step now runs before any Docker work — confirm it passes.
4. Re-probe the deployed bundle:
   ```bash
   curl -fsSL https://app.soleur.ai/login \
     | grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' | head -1 \
     | xargs -I{} curl -fsSL "https://app.soleur.ai{}" \
     | grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1 \
     | cut -d. -f2 \
     | { read p; pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '"iss=\(.iss) role=\(.role) ref=\(.ref)"'; }
   # Expected: iss=supabase role=anon ref=ifsccnjhymdmidffkzhl
   ```
5. Browser smoke test: navigate to `https://app.soleur.ai/login`, click "Sign in with Google", verify the Supabase auth screen loads (no `Invalid API key` error). Repeat for "Sign in with email", verify the OTP code form accepts a code.

## Audit trail

- Diagnosis Sentry event id: `c5affdf737e34110be747ce3a6463407` (timestamp `2026-04-28T16:53:25Z`)
- Hot-fix secret rotation: `2026-04-28T16:56:28Z`
- PR #3007 (this PR): four-layer guardrail set landed.
