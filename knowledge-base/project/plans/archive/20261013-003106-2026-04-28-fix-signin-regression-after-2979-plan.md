---
date: 2026-04-28
type: bug-fix
classification: user-impact-critical
issue: 2979 (closed) — follow-up regression
related_pr: 2975 (merged 2026-04-28T09:00:08Z)
branch: feat-one-shot-signin-regression-2979
worktree: .worktrees/feat-one-shot-signin-regression-2979
requires_cpo_signoff: true
---

# Fix: Sign-in fails after #2979 / PR #2975 — `Sign-in failed. If you have an existing account, try signing in with email instead.`

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** Hypotheses (H1, H3), Phase 3 (error classifier), Phase 4 (Sentry mirroring), Phase 5 (cache-busting), Risks (R2)
**Research sources used:** installed `@supabase/auth-js@2.49.0` source + `error-codes.d.ts`, installed `@supabase/ssr@0.6.0` `createBrowserClient.js`, `@sentry/nextjs@10.46.0`, `apps/web-platform/server/observability.ts`, `apps/web-platform/public/sw.js`, `apps/web-platform/app/sw-register.tsx`, `.github/workflows/reusable-release.yml`

### Key Improvements

1. **Discriminate on `error.code` (typed enum), not `error.message` (drift-prone string).** `@supabase/auth-js@2.49.0` exposes `bad_code_verifier`, `flow_state_not_found`, `flow_state_expired`, `bad_oauth_state`, `bad_oauth_callback` as typed `ErrorCode` enum values on `AuthApiError.code`. The substring-match approach in current `route.ts:70-72` and the regex approach in plan Phase 3.1 are both fragile against Supabase localizing or rewording messages. The deepened plan switches to a `Set<ErrorCode>` membership check.
2. **Service-worker cache-busting via `CACHE_NAME` bump, not unregister.** `apps/web-platform/public/sw.js` already implements an activate-handler that deletes any cache whose name doesn't match the active `CACHE_NAME` constant. Bumping `soleur-app-shell-v1` → `soleur-app-shell-v2` purges the stale `_next/static/**` cache for every active client without unregistering the SW (preserves push notifications). This makes Plan Risk R2 a non-issue.
3. **`reportSilentFallback` is server-only — client components use `Sentry.captureException` directly.** The plan's Phase 4.1 must distinguish: `app/(auth)/callback/route.ts` (server) uses `reportSilentFallback`; `components/auth/oauth-buttons.tsx` and `app/(auth)/login/page.tsx` (client `"use client"`) use `Sentry.captureException` from `@sentry/nextjs` with the same tag vocabulary (`feature: "auth"`, `op: "signInWithOAuth" | "signInWithOtp" | "verifyOtp"`).
4. **`build-args` extension is mechanical** — the existing `reusable-release.yml` block already passes 6 `NEXT_PUBLIC_*` values; adding `NEXT_PUBLIC_AUTH_PROVIDERS` is a 1-line append matching the established pattern. No new infrastructure.

### New Considerations Discovered

- **The bug class is "stale SW cache + project-rotation"**, not just "stale browser HTTP cache". The SW intercepts `/_next/static/**` cache-first — even a hard reload (Cmd-Shift-R) does NOT purge the SW cache; only an activate-time cleanup or explicit unregister does. This dramatically widens the cohort of broken users (anyone who ever loaded the bad bundle stays broken until SW activates a new version).
- **Cookie-based session storage:** `@supabase/ssr@0.6.0`'s `createBrowserClient` defaults `flowType: "pkce"` and stores the code-verifier in cookies (NOT localStorage). The cookie is keyed by `storageKey` (defaults to `sb-<projectRef>-auth-token`). When the project ref changes (new bundle points at `api.soleur.ai` resolving to ref `ifsccnjhymdmidffkzhl`, old bundle pointed at `test.supabase.co` resolving to a different ref), the cookie names DIFFER. The new bundle's `exchangeCodeForSession` looks up cookie `sb-ifsccnjhymdmidffkzhl-auth-token-code-verifier`, which doesn't exist if the OLD bundle wrote `sb-test-auth-token-code-verifier`. This is the precise mechanism behind H1.
- **`bad_code_verifier` is the official error code** from `@supabase/auth-js` for the verifier-mismatch case. Not the variants enumerated in plan Phase 2.1's regex (`code verifier`, `Code verifier missing`, `PKCE verifier mismatch`, etc.) — those are `error.message` strings that vary by Supabase version. The single source of truth is `error.code === "bad_code_verifier"`.
- **`AuthError.status` and `.code` are both potentially `undefined`** per the type definition (`code?: string`). Network-layer failures pre-response have neither. The classifier must handle `undefined` cleanly without throwing.

## Overview

After PR #2975 ("guardrails against placeholder NEXT_PUBLIC_SUPABASE_URL leaking into prod build") merged at `2026-04-28T09:00:08Z` and the operator rotated `gh secret NEXT_PUBLIC_SUPABASE_URL` at `12:19:05Z` (followed by a successful `Web Platform Release` at `12:19:21Z`), users land on `/sign-in` (which middleware-redirects to `/login?error=auth_failed`) and see the error message:

> Sign-in failed. If you have an existing account, try signing in with email instead.

This message is keyed off `CALLBACK_ERRORS["auth_failed"]` in `apps/web-platform/lib/auth/error-messages.ts` and only fires when the OAuth callback (`apps/web-platform/app/(auth)/callback/route.ts`) redirects to `/login?error=auth_failed`. The email-OTP flow uses `mapSupabaseError(error.message)` instead and would surface a different string — so **the regression is in the OAuth (social) path, not in email-OTP**.

The bundle itself is now correct: `curl https://app.soleur.ai/_next/static/chunks/app/(auth)/login/page-483855928ad7c36b.js | grep -oE 'https?://[a-z0-9.-]*supabase\.co|https?://api\.soleur\.ai'` returns only `https://api.soleur.ai`. The Supabase backend at `api.soleur.ai` (CNAME → `ifsccnjhymdmidffkzhl.supabase.co`) responds healthy; `/auth/v1/authorize?provider=google&redirect_to=…` returns a 302 to `accounts.google.com` with the correct `redirect_uri=https://api.soleur.ai/auth/v1/callback`. Doppler `prd.NEXT_PUBLIC_SUPABASE_URL` and `prd.NEXT_PUBLIC_SUPABASE_ANON_KEY` are aligned (anon-key JWT `ref` claim matches CNAME target).

So the OAuth round-trip from the browser CAN reach Google/GitHub successfully — but **the callback's `exchangeCodeForSession` is failing**, redirecting to `/login?error=auth_failed`. The plan's job is to identify which of the candidate root causes is firing in production, fix it, and ship guardrails so the regression does not silently repeat.

## User-Brand Impact

**If this lands broken, the user experiences:** Every existing OAuth user (Google + GitHub today, Apple/Microsoft if/when enabled) is locked out of `app.soleur.ai`. The error message — *"try signing in with email instead"* — leads users to email-OTP, which routes through the SAME `signInWithOtp` flow on the SAME Supabase project; if the underlying issue is a Supabase project-config drift, email also fails and the user has zero working sign-in path. Even when email works, OAuth users have no way to access account-linked workspaces (provisioned `workspace_path`, `api_keys` rows, repo connections) without contacting support.

**If this leaks, the user's data / workflow is exposed via:** No data leakage path on the failure side. The Sentry mirror added in Phase 4 forwards only typed enum fields (`error.code`, `error.name`, `error.status`, plus `provider` for OAuth) — `error.message` is intentionally NOT forwarded, since Supabase auth-js error messages can embed user-supplied input (the email passed to `signInWithOtp`, the OAuth `code` query-param) and Sentry is a shared-tenant project (cross-tenant operator-side exposure vector). If the fix for the regression is wrong (e.g., regenerating `code_verifier` cookies on a stale OAuth provider config), it could allow account-linking to the wrong identity. This is captured in Risks R3 below.

**Brand-survival threshold:** `single-user incident` — a single OAuth-locked customer who cannot recover via email-OTP and posts publicly is brand-damaging at our current MRR/user count. CPO sign-off required (per `hr-weigh-every-decision-against-target-user-impact`); `user-impact-reviewer` agent runs at PR review time.

## Hypotheses (ranked, to be narrowed during /work Phase 1 reproduction)

H1, H2, H3 are the highest-likelihood; H4 + H5 are remediation-time backstops.

### H1 — Stale client-side bundle / service-worker cache

The bundle filename pre-rotation was `page-1145cd8d8475e73c.js` (cached references with `https://test.supabase.co`); post-rotation it is `page-483855928ad7c36b.js` (correct `https://api.soleur.ai`). However:

- `cache-control: private, no-cache, no-store, max-age=0, must-revalidate` is set on the HTML response, **but the JS chunks themselves use the standard Next.js immutable cache** (`max-age=31536000, immutable`). A user whose browser cached `page-1145cd8d8475e73c.js` from a HEAD-request prefetch on 2026-04-28 morning may still have it.
- `apps/web-platform/public/sw.js` is registered (verified at `apps/web-platform/app/sw-register.tsx:9`) and **caches `_next/static/**` cache-first** (`sw.js` fetch handler line 53-72). The activate handler deletes caches whose name ≠ the current `CACHE_NAME = "soleur-app-shell-v1"`. **A hard reload does NOT purge the SW cache** — only a `CACHE_NAME` bump triggers the activate-handler cleanup, OR an explicit `caches.delete()` / SW unregister.
- **Mechanism (verified against installed `@supabase/ssr@0.6.0` and `@supabase/auth-js@2.49.0`):** `createBrowserClient` defaults to `flowType: "pkce"` (per `node_modules/@supabase/ssr/dist/main/createBrowserClient.js`). PKCE writes the code-verifier to cookies keyed by `storageKey`, default `sb-<projectRef>-auth-token-code-verifier`. The OLD bundle's `signInWithOAuth({ provider: "google", options: { redirectTo: "${origin}/callback" } })` → wrote cookie `sb-test-auth-token-code-verifier` (project ref derived from `https://test.supabase.co`). The browser then follows the OAuth round-trip → returns to `app.soleur.ai/callback?code=…`. The callback route runs SERVER-SIDE under the new bundle (server reads its env vars at runtime, not from the inlined client bundle), so it instantiates a Supabase client against `api.soleur.ai` (ref `ifsccnjhymdmidffkzhl`). `exchangeCodeForSession(code)` looks up cookie `sb-ifsccnjhymdmidffkzhl-auth-token-code-verifier` → not present → **`AuthApiError` with `code === "bad_code_verifier"` and message text that varies by version**.
- The callback's `errorCode = error.message?.includes("code verifier") ? "code_verifier_missing" : "auth_failed"` is a **substring match against the message string**. The robust discriminator is `error.code === "bad_code_verifier"` (typed `ErrorCode` enum exported by `@supabase/auth-js`). The substring miss falls through to `auth_failed` whenever Supabase reformats its message — and **this is the most likely explanation for the user seeing the "Sign-in failed" copy** (the OAuth round-trip succeeds, the callback runs, the verifier lookup fails, the substring matcher misses the new message format, the user lands at `/login?error=auth_failed`).

**Probe:** Open Chrome DevTools → Application → Service Workers, confirm `sw.js` is active. Application → Cache Storage → `soleur-app-shell-v1` will list `_next/static/**` entries. Filter by content of the cached login chunk (`page-*.js`) for `test.supabase.co` vs `api.soleur.ai` to confirm. Network panel: hard-reload → click "Continue with Google" → if the SW serves the old chunk, the redirect URL contains `test.supabase.co`. Use Playwright with `--disable-cache` AND a fresh user-data-dir (so no SW is registered) to confirm fresh-cache flow works.

### H2 — Supabase project `uri_allow_list` missing `https://app.soleur.ai/callback`

PR #2975 closing notes (and `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`) explicitly defer this verification: *"a SUPABASE_ACCESS_TOKEN from Doppler prd returned 401 against GET /v1/projects/<ref>/config/auth during plan execution — confirm the allowlist via the Supabase Dashboard."* The deferred operator step in #2979 was: *"Verify Supabase project uri_allow_list includes https://app.soleur.ai/callback."* If this step was skipped after merge, OAuth providers redirect to `https://api.soleur.ai/auth/v1/callback`, Supabase exchanges the code with the provider, then attempts to redirect to `https://app.soleur.ai/callback?code=…` — and **rejects the redirect** because `app.soleur.ai/callback` isn't in `uri_allow_list`. Symptoms: callback URL gets a generic error param or no `code` at all → callback route's "no code or exchange error" branch logs `Auth failed — no code or exchange error` and redirects to `/login?error=auth_failed`.

**Probe:** Re-run the Supabase Management API call with a `prd_terraform` (vs `prd`) token; if still 401, fetch via Supabase Dashboard → Authentication → URL Configuration → Redirect URLs. Compare against `[https://app.soleur.ai/callback, https://app.soleur.ai/**]`.

### H3 — `code_verifier_missing` masquerading as `auth_failed` (substring drift)

`apps/web-platform/app/(auth)/callback/route.ts:70-72`:

```ts
const errorCode = error.message?.includes("code verifier")
  ? "code_verifier_missing"
  : "auth_failed";
```

This case-sensitive substring match is fragile. Supabase JS error message strings change between releases. **The robust fix discriminates on `error.code` (typed enum), not `error.message` (drift-prone text).** `@supabase/auth-js@2.49.0` `lib/errors.js` `AuthError` constructor takes `(message, status, code)` and exposes `error.code: string | undefined`. The full `ErrorCode` enum is published in `@supabase/auth-js/dist/module/lib/error-codes.d.ts`. Verifier-class codes:

- `bad_code_verifier` — verifier cookie missing or doesn't match the OAuth state. Fires for stale-bundle code-verifier-mismatch (H1) and for cookies cleared mid-flow.
- `flow_state_not_found` — server-side flow_state row was never created or already consumed.
- `flow_state_expired` — server-side flow_state row TTL elapsed (default 10min).
- `bad_oauth_state` — `state` parameter from provider doesn't match issued state.
- `bad_oauth_callback` — provider returned a callback URL we didn't issue.

All five MUST map to `code_verifier_missing` in the existing `CALLBACK_ERRORS` dictionary (so the user sees "Session expired. Please try signing in again."). The substring approach catches at most the first two and only when the message contains the literal `"code verifier"` substring.

**Probe:** Add Sentry breadcrumb in callback route logging `error.code`, `error.name`, `error.status`, and `error.message` BEFORE the classifier. After deploy, the next failed callback surfaces the actual `error.code` value in Sentry → confirms the discriminator is firing on the typed code, not falling through to message-substring fallback.

### H4 — Silent fallback: client-side `console.error` not mirrored to Sentry

Two sites: `apps/web-platform/components/auth/oauth-buttons.tsx:80` (`console.error("[auth] Supabase OAuth error:", error.message)`) and `apps/web-platform/app/(auth)/login/page.tsx:52,75` (`console.error("[auth] Supabase error:", error.message)`). These are pure stdout logs — invisible in Sentry per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`. The reason this regression has zero Sentry signal in 24h despite the user-visible breakage IS this gap. Sentry sweep on `auth_failed`, `Auth failed`, `exchangeCodeForSession`, `OAuth`, `callback` against `org=jikigai` for the past 7 days returned zero events; only an `info`-level "Server startup v0.57.8" at `2026-04-28T12:26:10` post-deploy. Without Sentry signal we are debugging blind. Fix: route through `reportSilentFallback(err, { feature: "auth", op: "signInWithOAuth"|"signInWithOtp"|"verifyOtp"|"exchangeCodeForSession" })`.

### H5 — Stale OAuth provider Console redirect-URI config

For each enabled provider (Google + GitHub today; Apple + Microsoft are configured in `oauth-buttons.tsx` PROVIDERS but `external_apple` and `external_azure` are FALSE in the live `/auth/v1/settings` response), the OAuth Console must allow `https://api.soleur.ai/auth/v1/callback` in its "Authorized redirect URIs". Empirically, the Google probe in plan-execution returned a valid 302 with the correct redirect URI — so Google's config is OK. GitHub was not directly probed (would require the auth-page round-trip end-to-end). Apple/Microsoft's UI buttons exist but the providers are disabled at Supabase level — clicking them returns `provider_disabled` (mapped via `CALLBACK_ERRORS`), NOT the regression's `auth_failed`. So H5 is low-likelihood for the user's specific report but should be confirmed for GitHub, and **the four UI buttons should be reduced to two** until the disabled providers are enabled.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| Issue #2979 said "All four configured OAuth providers (Google, Apple, GitHub, Microsoft) are affected" | `/auth/v1/settings` response (live, 2026-04-28T13:24Z): `apple: false, azure: false, github: true, google: true`. Only 2 providers actually enabled at Supabase. | UI exposes 4 buttons; clicking Apple or Microsoft returns `provider_disabled`. Plan AC adds a `provider_enabled` filter on the rendered button list (Phase 4 task), reducing the discoverable surface to enabled providers only. |
| User report "/sign-in page" | `/sign-in` does not exist as a route; middleware fall-through redirects to `/login` (307 with query string preserved). | Plan does not modify the redirect; user-reported `/sign-in` is in fact `/login?error=auth_failed`. |
| `apps/web-platform/lib/supabase/allowed-hosts.ts` (referenced in #2979 learning file line 40) | The merged file lives at `apps/web-platform/lib/supabase/validate-url.ts` (renamed during PR #2975 review per architecture finding "rename to match SRP"). | Phase 5 retro-edits the learning file in place to point at the merged path. |
| `signInWithOAuth` "reuses the same base URL for every provider" (issue body) | True. Confirmed by reading `lib/supabase/client.ts` and `components/auth/oauth-buttons.tsx`. The placeholder leak from #2975 affected all providers; the regression's failure mode (post-fix) is per-callback, not per-base-URL. | No change needed; just confirms the new failure class is downstream of the bundle URL. |

## Implementation Phases

### Phase 1 — Reproduce + Sentry-instrument (RED)

Goal: see the live error message, decide between H1/H2/H3 with evidence rather than guessing.

**1.1 Add Sentry mirroring to all four client-side auth `console.error` sites + the callback's `logger.error`:**

- `apps/web-platform/components/auth/oauth-buttons.tsx:80` — wrap `console.error` with `Sentry.captureException(error, { tags: { feature: "auth", op: "signInWithOAuth", provider: provider.id } })`.
- `apps/web-platform/app/(auth)/login/page.tsx:52,75` — same pattern, `op: "signInWithOtp"|"verifyOtp"`.
- `apps/web-platform/app/(auth)/callback/route.ts:64-67` — already calls `logger.error`; add `reportSilentFallback(error, { feature: "auth", op: "exchangeCodeForSession", extra: { errorMessage: error.message, errorName: error.name, errorStatus: error.status } })`. Per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`, the existing pino log is invisible in Sentry.
- `apps/web-platform/app/(auth)/callback/route.ts:120` — same pattern for the `Auth failed — no code or exchange error` branch.

**1.2 Reproduce in fresh Playwright session against prod:**

```bash
PLAYWRIGHT_BASE_URL=https://app.soleur.ai bun playwright test e2e/oauth-signin.e2e.ts \
  --browser chromium --headed --grep "Google OAuth flow" \
  --project soleur/web-platform
```

Capture: (a) the URL of every redirect in the chain, (b) cookies set on `app.soleur.ai` and `api.soleur.ai`, (c) the final query-string the user lands on at `/login`, (d) the Supabase JS console error message verbatim. Save as a regression artifact to `knowledge-base/project/specs/feat-one-shot-signin-regression-2979/repro-2026-04-28.md` (path is enumerated, not a glob; per `hr-when-a-plan-specifies-relative-paths-e-g`).

**1.3 Verify Supabase `uri_allow_list` includes `https://app.soleur.ai/callback`:**

- Try Doppler `prd_terraform.SUPABASE_ACCESS_TOKEN` first (separate token from the 401-returning `prd` one).
- If still 401, attempt MCP supabase tools (`mcp__plugin_supabase_supabase__authenticate`, then `query-auth-config` if available — `ToolSearch` to discover).
- If both fail, document fallback to Supabase Dashboard with screenshot in `repro-2026-04-28.md`.

**Acceptance for Phase 1:**

- [ ] Sentry produces ≥1 event for the next failed OAuth attempt against prod (with `feature:auth, op:exchangeCodeForSession` tag) within 5 minutes of the deploy.
- [ ] `repro-2026-04-28.md` contains the verbatim Supabase error message string AND the `uri_allow_list` contents.

### Phase 2 — Tests (TDD, RED before GREEN per `cq-write-failing-tests-before`)

**2.1 New test file** `apps/web-platform/test/lib/auth/callback-error-mapping.test.ts`:

- Cases (`it.each` parameterization):
  - `"code verifier missing"` → `errorCode === "code_verifier_missing"` (current behavior baseline).
  - `"Code verifier missing"` (capitalized) → must map to `code_verifier_missing` after the fix.
  - `"PKCE verifier mismatch"` → must map to `code_verifier_missing` after the fix.
  - `"code_verifier missing"` (underscore) → must map to `code_verifier_missing` after the fix.
  - `"invalid grant"` (token already-used) → must map to `code_verifier_missing` after the fix (UX is identical: "Session expired").
  - `"network error"` → falls through to `auth_failed` (correct).
  - `"flow_state_not_found"` → must map to `code_verifier_missing` after the fix (this IS the actual Supabase error string for stale-bundle code-verifier mismatches; confirm via Phase 1.2 repro).

**2.2 New test file** `apps/web-platform/test/components/oauth-buttons-disabled-providers.test.tsx`:

- Cases:
  - When `enabledProviders=["google", "github"]` is passed to `<OAuthButtons />`, only 2 buttons render.
  - When `enabledProviders` is empty, the component renders the email-only fallback message.

**2.3 New test file** `apps/web-platform/test/components/oauth-buttons-sentry.test.tsx`:

- Mock `@sentry/nextjs.captureException`. Trigger `signInWithOAuth` rejection. Assert `captureException` called with `{ tags: { feature: "auth", op: "signInWithOAuth", provider: "google" } }`.

**2.4 Targeted vitest run** (per `cq-in-worktrees-run-vitest-via-node-node`):

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-signin-regression-2979/apps/web-platform && \
  ./node_modules/.bin/vitest run test/lib/auth/callback-error-mapping.test.ts \
                                test/components/oauth-buttons-disabled-providers.test.tsx \
                                test/components/oauth-buttons-sentry.test.tsx
```

Expected: ALL FAIL (RED). Commit as `test: add RED tests for callback error mapping + Sentry mirroring + provider-enabled filter` with `LEFTHOOK=0` if lefthook hangs (per `cq-when-lefthook-hangs-in-a-worktree-60s`).

### Phase 3 — Fix the callback error mapper (GREEN for callback-error-mapping)

**3.1 Discriminate on typed `error.code` (Supabase `ErrorCode` enum), not `error.message`.**

The robust fix imports `AuthError` from `@supabase/auth-js` (re-exported by `@supabase/supabase-js`) and matches on the typed `code` field. Replace lines 64-73 of `apps/web-platform/app/(auth)/callback/route.ts` with a call to the extracted classifier from 3.2:

```ts
import { classifyCallbackError } from "@/lib/auth/error-classifier";
// ...
if (error) {
  // Mirror to Sentry first so the raw error.code surfaces even if the
  // classifier drifts. Per AGENTS.md cq-silent-fallback-must-mirror-to-sentry.
  reportSilentFallback(error, {
    feature: "auth",
    op: "exchangeCodeForSession",
    extra: {
      errorCode: error.code,
      errorName: error.name,
      errorStatus: error.status,
      // truncate message in case it embeds the OAuth `code` query-param
      errorMessage: error.message?.slice(0, 200),
    },
  });
  const errorCode = classifyCallbackError(error);
  return NextResponse.redirect(`${origin}/login?error=${errorCode}`);
}
```

**3.2 Extract `apps/web-platform/lib/auth/error-classifier.ts`** (separate module — route files cannot export non-HTTP symbols per `cq-nextjs-route-files-http-only-exports`):

```ts
import type { AuthError } from "@supabase/supabase-js";

// Source of truth: @supabase/auth-js/dist/module/lib/error-codes.d.ts
// (installed version 2.49.0 at 2026-04-28). When the dependency bumps,
// re-grep error-codes.d.ts for *_verifier, *_state, bad_oauth_*.
const VERIFIER_CLASS_CODES = new Set<string>([
  "bad_code_verifier",
  "flow_state_not_found",
  "flow_state_expired",
  "bad_oauth_state",
  "bad_oauth_callback",
]);

export type CallbackErrorCode = "code_verifier_missing" | "auth_failed";

/**
 * Maps a Supabase AuthError (or any error-shaped object) to a coarse code the
 * login page renders. The discriminator is the typed `error.code` field, not
 * the drift-prone `error.message` string. Inputs that aren't `AuthError` (raw
 * Errors, network failures, undefined) fall through to "auth_failed".
 *
 * See knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-callback-error-classifier-and-sentry-mirroring.md
 */
export function classifyCallbackError(
  err: Pick<AuthError, "code"> | { code?: string } | unknown,
): CallbackErrorCode {
  const code =
    typeof err === "object" && err !== null && "code" in err
      ? (err as { code?: unknown }).code
      : undefined;
  if (typeof code === "string" && VERIFIER_CLASS_CODES.has(code)) {
    return "code_verifier_missing";
  }
  return "auth_failed";
}
```

**Why a `Set` not a regex:** the typed enum is the source of truth. A regex over message text is what we're replacing — adding a new regex is the same anti-pattern at one level higher. The `Set` is grep-stable (per `cq-code-comments-symbol-anchors-not-line-numbers`), trivially extended on the next Supabase release, and the test file `callback-error-mapping.test.ts` parameterizes across the membership.

**3.3 Update Phase 2.1 test cases to discriminate on `code`, not `message`:**

The previously-prescribed message-substring cases (`"code verifier missing"`, `"PKCE verifier mismatch"`, etc.) become **legacy/regression cases** that must STILL map correctly via `error.code === "bad_code_verifier"`. The new test matrix uses error objects with explicit `.code` values:

| Input `error.code` | Expected `classifyCallbackError(...)` |
| --- | --- |
| `"bad_code_verifier"` | `"code_verifier_missing"` |
| `"flow_state_not_found"` | `"code_verifier_missing"` |
| `"flow_state_expired"` | `"code_verifier_missing"` |
| `"bad_oauth_state"` | `"code_verifier_missing"` |
| `"bad_oauth_callback"` | `"code_verifier_missing"` |
| `"invalid_credentials"` | `"auth_failed"` |
| `"unexpected_failure"` | `"auth_failed"` |
| `undefined` (network error) | `"auth_failed"` |
| `null` (missing object) | `"auth_failed"` |
| Plain `Error` (no `.code`) | `"auth_failed"` |

Per `cq-mutation-assertions-pin-exact-post-state`, each assertion uses `.toBe(expected)`, never `.toContain([...])`.

**3.4 Run targeted tests — expect GREEN:**

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-signin-regression-2979/apps/web-platform && \
  ./node_modules/.bin/vitest run test/lib/auth/callback-error-mapping.test.ts
```

### Phase 4 — Fix Sentry mirroring + provider-enabled filter (GREEN for the rest)

**4.1 Mirror `console.error` to Sentry** in three files (per AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`).

**Critical:** `reportSilentFallback` lives in `apps/web-platform/server/observability.ts` and **imports server-only modules** (pino logger). It is server-side only. Client components (`"use client"` files) MUST use `@sentry/nextjs`'s `captureException` directly. The vocabulary stays consistent (`feature: "auth"`, `op: ...`).

Server (route handler):

```ts
// app/(auth)/callback/route.ts — server module
import { reportSilentFallback } from "@/server/observability";
reportSilentFallback(error, {
  feature: "auth",
  op: "exchangeCodeForSession",
  extra: { errorCode: error.code, errorName: error.name, errorStatus: error.status },
});
```

Client (oauth-buttons + login page):

```ts
// components/auth/oauth-buttons.tsx — "use client"
import * as Sentry from "@sentry/nextjs";
// ...
if (error) {
  console.error("[auth] Supabase OAuth error:", error.message);
  Sentry.captureException(error, {
    tags: { feature: "auth", op: "signInWithOAuth", provider: provider.id },
    extra: { errorCode: (error as { code?: string }).code, errorMessage: error.message?.slice(0, 200) },
  });
  setError(mapSupabaseError(error.message));
  setLoading(null);
}
```

Same pattern in `app/(auth)/login/page.tsx` for both `handleSendOtp` (`op: "signInWithOtp"`) and `handleVerifyOtp` (`op: "verifyOtp"`).

**Sentry SDK confirmed:** `@sentry/nextjs@10.46.0` installed; client config in `sentry.client.config.ts` initializes `dsn: process.env.NEXT_PUBLIC_SENTRY_DSN` with `tracesSampleRate: 0` (error-only — matches our use case). The server-side `beforeSend` hook in `sentry.server.config.ts` strips `cookie` and `x-nonce` headers — our `errorMessage` slice provides additional defense against echoing OAuth-code query-params into the event.

**4.2 Filter rendered OAuth buttons by enabled-providers list:**

- Add a server-side fetch in `app/(auth)/login/page.tsx` (or a new `lib/auth/enabled-providers.ts` module) that hits `/auth/v1/settings` server-side at request time (cached via `revalidate: 300` to avoid per-render fetches) and filters the PROVIDERS array.
- Alternative (simpler, recommended): expose the enabled set via `NEXT_PUBLIC_AUTH_PROVIDERS=google,github` build-arg, sourced from Doppler. This avoids a runtime fetch but requires re-deploy when toggling. **Choose this approach** because OAuth provider configuration changes are a Terraform / Supabase-Dashboard-mediated event already, and the deploy step for the build-arg is a marginal addition.

**4.3 Run all targeted tests — expect GREEN:**

```bash
./node_modules/.bin/vitest run test/lib/auth/ test/components/oauth-buttons*
```

**4.4 Full app vitest sweep:**

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run
```

Pre-existing flakes (per the #2979 learning's session-errors entry: `chat-page.test.tsx > does NOT send msg when sessionConfirmed is false`) are tolerated only after rerunning the failure in isolation and confirming green; any new failure introduced by this PR is a hard fail.

### Phase 5 — Backstop: client-side cache-busting for stale bundles (H1 mitigation)

**5.1 Bump `CACHE_NAME` in `apps/web-platform/public/sw.js`** (replaces previous "unregister SW" approach).

Verified: `apps/web-platform/public/sw.js` line 1 declares `const CACHE_NAME = "soleur-app-shell-v1";`. The activate handler (lines 24-32) deletes any cache whose name doesn't equal the active `CACHE_NAME`. **Bumping the constant from `v1` to `v2` purges the stale `_next/static/**` cache for every active client without unregistering the SW.** Push notifications survive (the SW registration itself is unchanged); only the cached static assets get evicted.

```diff
- const CACHE_NAME = "soleur-app-shell-v1";
+ const CACHE_NAME = "soleur-app-shell-v2";
```

This is the surgical fix for H1. It has zero blast radius on push notifications (R2 in plan), zero risk to in-flight session cookies (R1), and reaches every active client when the SW activates the new version. Browser SW lifecycle: existing tabs use the old SW until they close; new navigations install v2 immediately. Worst case the user has to reload twice (one to install v2, one to fetch fresh chunks via v2's cleanup). Same outcome as 5.2's `Clear-Site-Data` for the cache class but more targeted and reversible.

**Rejected alternative — `serviceWorker.getRegistrations().forEach(r => r.unregister())`** on `/login` mount: would break push notifications for already-authenticated users who reload `/login` (e.g., bookmark navigation), since SW unregistration purges the push-subscription. The SW is a singleton across the origin and is registered for the whole app via `apps/web-platform/app/sw-register.tsx:9`; unregistering it from `/login` is a global operation.

**5.2 Add `Clear-Site-Data` header on `/login` response when `?error=` is present:**

```ts
// In middleware or a route-level header
if (pathname === "/login" && searchParams.has("error")) {
  response.headers.set("Clear-Site-Data", '"cache", "storage"');
}
```

This is the nuclear option for H1 — when the user lands at `/login?error=…`, the browser purges its HTTP cache and storage for `app.soleur.ai`. Subsequent reloads pull fresh chunks. Validate that this doesn't clear in-flight session cookies (it can — `Clear-Site-Data: "cookies"` clears cookies, but `"cache", "storage"` does not).

**5.3 Audit OAuth Console redirect-URI lists (H5 backstop):**

For Google (already verified via `/auth/v1/authorize` 302 probe) and GitHub (NOT directly verified), confirm `https://api.soleur.ai/auth/v1/callback` is in the Authorized redirect URIs. If we hold credentials, automate via the GitHub OAuth Apps API or the Google Cloud Console API. If not, use Playwright MCP to navigate to the consoles and inspect (per AGENTS.md `hr-when-playwright-mcp-hits-an-auth-wall` — keep the tab open at the auth page if creds are needed).

### Phase 6 — Verify in prod (post-deploy)

**6.1 Replay the Phase 1.2 Playwright probe against prod after merge + deploy.** Expect: full OAuth round-trip → `/dashboard` (or `/connect-repo` / `/setup-key` per `callback/route.ts:84-110` chain). No error param at `/login`.

**6.2 Sentry search:** `feature:auth op:exchangeCodeForSession` for the post-deploy 30-minute window MUST be empty.

**6.3 Bundle probe (preflight Check 5):** confirm the new login chunk still resolves only to canonical Supabase host.

## Files to Create

- `apps/web-platform/lib/auth/error-classifier.ts` — extracted callback error mapper (Phase 3.2).
- `apps/web-platform/test/lib/auth/callback-error-mapping.test.ts` — RED-then-GREEN tests for the classifier (Phase 2.1).
- `apps/web-platform/test/components/oauth-buttons-disabled-providers.test.tsx` — RED tests for provider filter (Phase 2.2).
- `apps/web-platform/test/components/oauth-buttons-sentry.test.tsx` — RED tests for Sentry mirroring (Phase 2.3).
- `knowledge-base/project/specs/feat-one-shot-signin-regression-2979/repro-2026-04-28.md` — Phase 1 repro artifact.
- `knowledge-base/project/specs/feat-one-shot-signin-regression-2979/spec.md` — feature spec (per AGENTS.md feat-branch convention, written by `/work` Phase 0).
- `knowledge-base/project/specs/feat-one-shot-signin-regression-2979/tasks.md` — derived from this plan, written by Save Tasks step below.
- `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-callback-error-classifier-and-sentry-mirroring.md` — learning file (Phase 7 / compound).

## Files to Edit

Verified each path exists via `Read` during plan execution:

- `apps/web-platform/app/(auth)/callback/route.ts` — Phase 3.1 (call `classifyCallbackError` from new module), Phase 4.1 (`reportSilentFallback` on both error branches).
- `apps/web-platform/components/auth/oauth-buttons.tsx` — Phase 4.1 (client-side `Sentry.captureException`), Phase 4.2 (filter providers by `NEXT_PUBLIC_AUTH_PROVIDERS`).
- `apps/web-platform/app/(auth)/login/page.tsx` — Phase 4.1 (client-side `Sentry.captureException` in `handleSendOtp` + `handleVerifyOtp` catch sites).
- `apps/web-platform/middleware.ts` — Phase 5.2 (`Clear-Site-Data: "cache", "storage"` header on `/login?error=…`).
- `apps/web-platform/public/sw.js` — Phase 5.1 (bump `CACHE_NAME` constant `v1` → `v2`).
- `apps/web-platform/scripts/verify-required-secrets.sh` — Phase 4.2 (add `NEXT_PUBLIC_AUTH_PROVIDERS` to required-secrets check).
- `.github/workflows/reusable-release.yml` — Phase 4.2 (append `NEXT_PUBLIC_AUTH_PROVIDERS=${{ secrets.NEXT_PUBLIC_AUTH_PROVIDERS }}` to the existing `build-args` block, alongside the 6 existing `NEXT_PUBLIC_*` values).
- `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md` — retro-edit Phase 5 (path-rename allowed-hosts.ts → validate-url.ts) per `wg-when-fixing-a-workflow-gates-detection`.

## Open Code-Review Overlap

Ran:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
```

For each path in `## Files to Edit`, `jq -r --arg path "<path>" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'`:

- `apps/web-platform/app/(auth)/callback/route.ts` — None.
- `apps/web-platform/components/auth/oauth-buttons.tsx` — None.
- `apps/web-platform/app/(auth)/login/page.tsx` — None.
- `apps/web-platform/middleware.ts` — None.
- `apps/web-platform/scripts/verify-required-secrets.sh` — None.
- `.github/workflows/reusable-release.yml` — None.

`## Open Code-Review Overlap: None.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 1 Sentry breadcrumb deployed; live failed OAuth attempt produces a Sentry event with `feature:auth, op:exchangeCodeForSession` tag and the verbatim error message.
- [ ] Phase 2 RED tests fail before Phase 3/4 fixes; pass after.
- [ ] `classifyCallbackError` covers the 7 enumerated cases in 2.1.
- [ ] All 3 `console.error` auth sites mirror to Sentry via `Sentry.captureException` or `reportSilentFallback` (per `cq-silent-fallback-must-mirror-to-sentry`).
- [ ] OAuth button list filters by `NEXT_PUBLIC_AUTH_PROVIDERS` (or runtime fetch) — clicking Apple/Microsoft when disabled is impossible (button absent), not error-mapped.
- [ ] `Clear-Site-Data` header on `/login?error=…` verified via `curl -I` against the deployed app.
- [ ] No new vitest failures in `apps/web-platform`; pre-existing `chat-page.test.tsx > does NOT send msg…` flake re-runs green in isolation.
- [ ] PR body uses `Closes #2979` (issue is currently `state: CLOSED`, but the regression is the same user-visible symptom — re-link via PR body so the issue surfaces in the PR's ref graph for future audits). If `Closes` would inappropriately re-close an already-closed issue, switch to `Ref #2979`.
- [ ] CPO sign-off recorded (per `hr-weigh-every-decision-against-target-user-impact` threshold = `single-user incident`).
- [ ] `user-impact-reviewer` agent runs at review time (auto-triggered by `requires_cpo_signoff: true` in frontmatter — see `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

### Post-merge (operator)

- [ ] `Web Platform Release` workflow run after merge succeeds (Validate step + deploy). Polled per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.
- [ ] Phase 6.1 Playwright probe in prod: full OAuth round-trip lands at `/dashboard` for an established user.
- [ ] Phase 6.2 Sentry search empty for the 30-minute post-deploy window.
- [ ] Phase 6.3 bundle probe: login chunk has only `https://api.soleur.ai`.
- [ ] If H2 is the live cause: Supabase Dashboard (or `prd_terraform.SUPABASE_ACCESS_TOKEN` if it has scope) confirms `uri_allow_list` contains `https://app.soleur.ai/callback`. If missing, add it.

## Test Strategy

- **Unit:** Vitest in `apps/web-platform/test/lib/auth/` and `apps/web-platform/test/components/`. Run via `./node_modules/.bin/vitest run` per `cq-in-worktrees-run-vitest-via-node-node`.
- **Integration:** Existing `apps/web-platform/e2e/otp-login.e2e.ts` continues to pass; add new `apps/web-platform/e2e/oauth-callback-regression.e2e.ts` that exercises the OAuth→callback round-trip against a Playwright-mocked Supabase backend (do NOT hit live Supabase from CI per `cq-destructive-prod-tests-allowlist`).
- **Manual prod verification:** Phase 1.2 + Phase 6.1 Playwright probes against `https://app.soleur.ai`.

## Risks

- **R1 — `Clear-Site-Data` clobbers in-flight session cookies.** Mitigation: scope to `"cache", "storage"` only; explicitly NOT `"cookies"`. Validate via curl + browser test that the user's session cookie persists across the `Clear-Site-Data` response.
- **R2 — Service-worker unregister breaks push notifications / offline.** RESOLVED via deepen-plan: replaced 5.1's "unregister SW" approach with a `CACHE_NAME` bump. The SW registration is preserved (push notifications keep working), only the cached static assets are evicted via the existing activate-handler cleanup logic. Verified by reading `public/sw.js:1` and `app/sw-register.tsx:9`.
- **R3 — Wrong fix for `code_verifier_missing` could allow account-linking to wrong identity.** Specifically: if we silently retry `signInWithOAuth` after a verifier error, the new flow's `state` parameter must be regenerated (Supabase JS does this automatically) — we must NOT pass through any user-controlled state. Mitigation: do not auto-retry; the `code_verifier_missing` UX is "Session expired. Please try signing in again." which forces the user back to the consent screen. Verified in `error-messages.ts:6` — copy is correct.
- **R4 — Filtering OAuth buttons via `NEXT_PUBLIC_AUTH_PROVIDERS` build-arg means toggling a provider requires re-deploy.** Acceptable trade-off: provider toggles are rare (Terraform/Supabase-Dashboard-mediated already). Alternative documented in 4.2.
- **R5 — Supabase JS error-message strings will drift again.** Mitigation: the new `classifyCallbackError` matches a broad regex; the test suite enumerates 7 cases. Add a new case + harden the regex on the next drift event. The Sentry breadcrumb (1.1) gives us the raw message string for fast iteration.

## Sharp Edges

- **Plan globs are file-list-enumerated, not glob-pattern.** Per `hr-when-a-plan-specifies-relative-paths-e-g`. No glob is prescribed; each path in `## Files to Edit` and `## Files to Create` was Read or `ls`-confirmed during plan execution.
- **Substring → regex widening.** Per `cq-union-widening-grep-three-patterns` consumer-pattern grep: the `errorCode` string is consumed in `app/(auth)/login/page.tsx:33` via `CALLBACK_ERRORS[callbackError]`. Extending the discriminator to map MORE inputs to `code_verifier_missing` (vs. introducing a new code) avoids needing to add a new key to `CALLBACK_ERRORS` and re-update all consumers.
- **Sentry mirroring on the callback's `error.message` should not echo the FULL message verbatim if it contains the OAuth `code` query-param.** Per the existing `previewValue` pattern in `lib/supabase/validate-url.ts:25-31`, truncate before sending. Apply the same truncation here.
- **Per `cq-mutation-assertions-pin-exact-post-state`,** the test `verifies error.message → errorCode === "code_verifier_missing"` must use `.toBe("code_verifier_missing")`, not `.toContain([...])`.
- **Per `cq-docs-cli-verification`,** any CLI invocation in this plan that lands in a `.md` doc must be verified. Bash invocations in this plan are: `gh pr view`, `gh issue view`, `gh run list`, `curl`, `dig`, `doppler secrets get`, `bun playwright test`, `./node_modules/.bin/vitest run`. All standard tools, all locally verified before plan write.
- **Per `cq-prose-issue-ref-line-start`,** no line in this plan starts with `#NNNN`. Verified via grep `^#[0-9]` — only `## Heading` matches, no issue refs at line start.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with concrete artifacts and threshold = `single-user incident`.

## Domain Review

**Domains relevant:** Product, Engineering (CTO).

### Product (CPO)

**Status:** sign-off required pre-`/work` per `requires_cpo_signoff: true` frontmatter. CPO must verify: (a) the regression's user impact framing in `## User-Brand Impact` matches their assessment, (b) the trade-off in 4.2 (filter via build-arg vs. runtime fetch) is acceptable, (c) the `Clear-Site-Data` mitigation in 5.2 does not break in-progress checkout/onboarding sessions for users mid-flow.

### Engineering (CTO)

**Status:** assessment carry-forward — none recorded; this plan's CTO concerns are: (a) regex-vs-substring discriminator drift class (mitigated by test enumeration + Sentry breadcrumb), (b) service-worker unregister blast radius (R2), (c) `Clear-Site-Data` cookie-scope correctness (R1).

### Product/UX Gate

**Tier:** none.

This plan does not create new user-facing pages or flows. It hardens an existing flow's error path. No wireframes needed; copy in `error-messages.ts` is unchanged. UX Gate skipped.

**Brainstorm-recommended specialists:** none (this plan was triggered by a bug report, not a brainstorm).

## Non-Goals

- **NG1: Not migrating `reusable-release.yml` build-args from GitHub-secrets to Doppler-only.** Tracked in #2981. The placeholder-leak class is now defended by 4 layers; the dual-source-of-truth issue is a separate ergonomics improvement.
- **NG2: Not enabling Apple or Microsoft providers at Supabase.** They're configured in the UI (`oauth-buttons.tsx PROVIDERS`) but disabled at Supabase. Phase 4.2 hides the UI buttons for disabled providers — actually enabling them is a separate plan (provider account setup, OAuth Console redirect-URI registration, Terraform `supabase_auth_provider` resource if available). Filed as #2982 (TBD at /work) for tracking.
- **NG3: Not migrating away from Supabase JS for auth.** The error-message-drift fragility is real; the fix is hardening the matcher, not rewriting auth.
- **NG4: Not rebuilding the SW registration model.** R2 documents the trade-off; if SW is needed later, the unregister in 5.1 can be scoped to a SW name.

## Deferral Tracking

- **#2982 (to be filed at /work Phase 0):** "feat(auth): enable Apple + Microsoft OAuth providers in Supabase + register OAuth Console redirect URIs". Rationale: UI exposes 4 buttons; only 2 work. Re-evaluation: when product needs broader OAuth coverage. Milestone: Post-MVP / Later.

## References

- Issue #2979 (closed): https://github.com/jikig-ai/soleur/issues/2979
- PR #2975 (merged): https://github.com/jikig-ai/soleur/pull/2975
- Learning: `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`
- Source-of-truth `ErrorCode` enum: `apps/web-platform/node_modules/@supabase/auth-js/dist/module/lib/error-codes.d.ts` (installed `@supabase/auth-js@2.49.0` via `@supabase/supabase-js@^2.49.0`)
- `AuthError` class: `apps/web-platform/node_modules/@supabase/auth-js/dist/module/lib/errors.js` (constructor `(message, status, code)`; `isAuthError` / `isAuthApiError` type-guards available)
- `createBrowserClient` PKCE default + cookie-based storage: `apps/web-platform/node_modules/@supabase/ssr/dist/main/createBrowserClient.js` (defaults `flowType: "pkce"`, `storageKey` derived from `cookieOptions.name`)
- Service worker registration site: `apps/web-platform/app/sw-register.tsx:9`; SW source: `apps/web-platform/public/sw.js:1` (`CACHE_NAME` constant); SW activate-handler cache cleanup: `public/sw.js:24-32`
- `reportSilentFallback` server-side helper: `apps/web-platform/server/observability.ts:82` (signature `(err, { feature, op?, extra?, message? })`)
- Sentry SDK: `@sentry/nextjs@10.46.0`; client init: `apps/web-platform/sentry.client.config.ts`; server init: `apps/web-platform/sentry.server.config.ts` (`beforeSend` strips `cookie` and `x-nonce` headers)
- AGENTS.md rules invoked: `hr-weigh-every-decision-against-target-user-impact`, `cq-silent-fallback-must-mirror-to-sentry`, `cq-write-failing-tests-before`, `cq-in-worktrees-run-vitest-via-node-node`, `cq-test-mocked-module-constant-import`, `cq-nextjs-route-files-http-only-exports`, `cq-union-widening-grep-three-patterns`, `cq-mutation-assertions-pin-exact-post-state`, `cq-code-comments-symbol-anchors-not-line-numbers`, `cq-docs-cli-verification`, `cq-prose-issue-ref-line-start`, `hr-when-a-plan-specifies-relative-paths-e-g`, `wg-when-fixing-a-workflow-gates-detection`, `wg-use-closes-n-in-pr-body-not-title-to`.
