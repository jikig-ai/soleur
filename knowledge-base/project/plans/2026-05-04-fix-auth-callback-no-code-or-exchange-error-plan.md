---
date: 2026-05-04
type: bug-fix
classification: user-impact-critical
issue: TBD (file from /work, see Acceptance Criteria)
related_prs: [2975, 2994, 3007, 3016]
related_issues: [2979, 2997, 3001, 3004, 3005, 3006]
branch: feat-one-shot-auth-callback-no-code-or-exchange-error
worktree: .worktrees/feat-one-shot-auth-callback-no-code-or-exchange-error
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** Overview (upstream-doc grounding), Hypotheses (H1 upgraded
from speculation to upstream-documented behavior; H2 deepened with allow-list
fall-back semantic), Files to Edit (provider_disabled wiring), Acceptance
Criteria (new pre-merge negative-space tests), Risks (added R6 — auth-js version drift),
Sharp Edges (URLSearchParams `getAll` semantics).
**Research sources used:**
- Context7 `/supabase/supabase` — confirmed Supabase forwards `error` +
  `error_description` to `redirect_to` on user-denied OAuth (upstream-documented:
  *"if the user denies access, Supabase Auth redirects with error information in
  query parameters"* — `apps/docs/content/guides/auth/oauth-server/oauth-flows.mdx`)
  AND that the Supabase `/v1/oauth/authorize` doc also shows the
  `error=access_denied&error_description=...` pattern with the same shape.
- Installed `@supabase/auth-js@2.99.2` `dist/module/lib/error-codes.d.ts` —
  enumerates 80+ codes, including `provider_disabled` (already keyed in
  `error-messages.ts` but never mapped by the classifier — silent gap).
- `apps/web-platform/test/lib/auth/callback-error-mapping.test.ts` — read in
  full; its case shape (`it.each([…codes])`) is reused in the new
  provider-error-classifier tests.
- `apps/web-platform/test/callback.test.ts` — confirmed the file name
  `callback.test.ts` is **already taken** by the `resolveOrigin` tests (NOT a
  route-level test). The new route-level test must NOT collide. Renamed below
  to `callback-route-branches.test.ts`.
- `apps/web-platform/app/api/auth/github-resolve/callback/route.ts` —
  prior-art for the no-code branch with referrer-aware logging
  (`logger.warn({ state, hasStateCookie }, "GitHub resolve callback: no code param (user denied or error)")`).
  Same pattern, distinct route.
- `.github/workflows/scheduled-oauth-probe.yml` — confirmed the existing
  `record_failure` machinery is extensible (one new `check_callback_error`
  function, mirrors `check_redirect`).

### Key Improvements

1. **H1 (user-cancel access_denied) upgraded from speculation to
   upstream-documented behavior.** Supabase's own docs
   (`apps/docs/content/guides/auth/oauth-server/oauth-flows.mdx` step 4)
   confirm: *"if the user denies access, Supabase Auth redirects with error
   information in query parameters."* The `redirect_to` (our
   `app.soleur.ai/callback`) receives the `error` + `error_description`
   *verbatim*. Same pattern applies for `/v1/oauth/authorize` (Supabase OAuth-app
   surface, separate from `/auth/v1/oauth/authorize` user-auth surface, but the
   error-forwarding shape is identical). This is not a Supabase bug; the gap is
   in our route, which doesn't read `error=` and conflates user-cancel with
   `auth_failed`.
2. **`provider_disabled` was a silent gap that the deepen-pass surfaced.**
   `apps/web-platform/lib/auth/error-messages.ts:7` already has
   `CALLBACK_ERRORS["provider_disabled"]` ("This sign-in provider is not
   enabled. Please use a different method.") — but the classifier
   `classifyCallbackError` in `apps/web-platform/lib/auth/error-classifier.ts`
   only maps verifier-class codes; everything else (including
   `provider_disabled`) falls through to `auth_failed`. The dictionary key
   is dead code today. Plan extends Phase 2 to wire this up: `provider_disabled`
   from the Supabase exchange-error → `/login?error=provider_disabled`. Three-key
   `CALLBACK_ERRORS` becomes four-key (+ `oauth_cancelled`).
3. **Auth-js version drift discovered: prior plan + classifier doc-comment
   say 2.49.0; installed is 2.99.2.** The five `VERIFIER_CLASS_CODES` are
   still all present in 2.99.2 (verified). But the plan now flags the drift
   for the next dep-bump cycle — and adds the version-pin grep to the
   acceptance criteria so future renames surface at PR time, not in prod.
4. **`URLSearchParams.get("error")` semantics on bracketed keys** — verified
   that `new URLSearchParams("error[]=access_denied").get("error")` returns
   `null` (the key is literally `error[]`, not `error`), confirming the
   sharp edge in the plan body.
5. **Probe extension uses `--max-redirs 0` and `%{redirect_url}` like the
   existing `check_redirect` step** (verified in `scheduled-oauth-probe.yml`
   line 66) — minimal new shape; reviewers will recognize the pattern.

### New Considerations Discovered

- Even Supabase's own *example* server-side OAuth callback (the WorkOS guide
  in Context7) doesn't inspect `error=` — same gap. We're not hitting an
  exotic case; this is a class problem in the Supabase pattern. Worth a
  one-line PR comment / learning at /work time.
- The `error-classifier.ts` file's leading comment cites *"Source of truth:
  @supabase/auth-js error-codes.d.ts (installed v2.49.0)"* — stale by 50
  minor versions. The drift-guard test
  `error-classifier-supabase-drift.test.ts` (added by #2994) does check the
  installed file shape, so this is documentation-stale, not behavior-stale.
  Still a fix-inline at /work time (1-line edit).
- The Sentry token-scope blocker (`org:ci` only, no `event:read`) blocked
  debugging in the 2026-03-30 PKCE incident AND today's deepen pass. This
  is the second occurrence — graduate from "session error" to a tracked
  follow-up (CTO domain, low priority but visible).

# Fix: Auth callback `op: callback_no_code` — `Auth failed — no code or exchange error`

## Overview

During the webapp demo on **Friday 2026-04-29 at 23:08:46 CEST (21:08:46 UTC)**,
a user landed on `GET /(auth)/callback` and was redirected to
`/login?error=auth_failed`. The Sentry/log id captured for the event is
`34d20156467d46e28d89c7fc821b6d3a`.

The error string `"Auth failed — no code or exchange error"` is the
**`message:`** field passed to `reportSilentFallback` at the bottom-of-function
fallback in `apps/web-platform/app/(auth)/callback/route.ts:148` (verified by
exact-substring match — only one site in the route uses that text):

```ts
// apps/web-platform/app/(auth)/callback/route.ts:140-152
// Auth failed — redirect to login with error.
// No `code` query-param means the OAuth provider redirected without one
// (e.g. uri_allow_list rejected the redirect, or the provider errored).
reportSilentFallback(null, {
  feature: "auth",
  op: "callback_no_code",
  message: "Auth failed — no code or exchange error",
  extra: { codePresent: !!code, origin },
});
return NextResponse.redirect(`${origin}/login?error=auth_failed`);
```

**This is a different failure class than the one PR #2994 hardened against.**
PR #2994 fixed the verifier-class branch (cookie/code-verifier mismatch — the
`exchangeCodeForSession` returned an `error` with a typed `code`). The
`callback_no_code` op fires earlier: the request to `/(auth)/callback` arrived
**without a `code` query parameter at all** (the `if (code) { ... }` block
on `route.ts:20` was skipped entirely). The bug class is "OAuth round-trip
returned to our domain but the provider/Supabase didn't pass us a
`?code=…`" — three known mechanisms in our stack:

1. Provider-side rejection of the redirect (Supabase `uri_allow_list` mismatch
   between the app `redirectTo` and the project's allow-list — Supabase strips
   `code` and forwards a generic redirect to `/callback`).
2. User cancelled OAuth consent at the provider (Google's "Cancel" button
   redirects back to Supabase with `error=access_denied`, which Supabase
   forwards to the app's redirect URL without `code`; the user re-clicks
   anything that hits `/callback` and trips the same fallback).
3. Direct GET to `https://app.soleur.ai/callback` (bookmark, address-bar
   typo, link in stale email/Discord, opening the link in a clean profile
   without ever launching `signInWithOAuth`/`signInWithOtp`).

The synthetic OAuth probe (`scheduled-oauth-probe.yml`, shipped via #2997 on
2026-04-29 15:25Z, 1h45m before the demo failure) was **green** at the
adjacent runs (`21:33:20Z` after, `20:13:20Z` before). The probe confirms the
*outbound* leg works: `api.soleur.ai/auth/v1/authorize?provider=google` 302s
to `accounts.google.com`. The probe does **not** simulate the round-trip
back, so it cannot detect the failure class observed in the demo.

The deferred follow-throughs from PR #2994 (#3004 Sentry visibility for
`feature: auth` events; #3005 `/login?error=code_verifier_missing` query
appearance) were both contingent on the *first user-triggered failure* —
the demo IS that first event. The plan below resolves both follow-throughs
along with the underlying defects.

## User-Brand Impact

**If this lands broken, the user experiences:** users land on
`/login?error=auth_failed` with the misleading copy *"Sign-in failed. If you
have an existing account, try signing in with email instead."* — the same UX
class that PR #2994 hardened against, but in a **different** code path.
Worse: in the demo path the user did not initiate sign-in via OAuth at all
(if root cause is a stale link / direct hit), so the "try email instead"
copy actively misleads. In the worst case (uri_allow_list drift), every
OAuth user is silently bounced back to login with no working sign-in path.

**If this leaks, the user's data / workflow is exposed via:** no data
leakage on the failure path itself. The fix expands Sentry mirroring on a
new branch (`callback_no_code` already mirrors per #2994; the plan adds
`url_path` and `referer_host` extras so root-cause-class is queryable).
Forwarding remains typed-only: no `error.message`, no full URL with `code`
query param, no email. The Sentry mirror MUST NOT log full request URL
(can carry user-controlled query params); only `pathname` (always
`/callback`), `referer_host` (Google/GitHub/external = useful root-cause
discriminator), and the existing `origin`.

**Brand-survival threshold:** `single-user incident` — a single OAuth-locked
customer at our current MRR/user count who posts publicly is brand-damaging.
This plan inherits CPO sign-off carry-forward from #2979/#3006/#2994 (the
auth-class brand-survival framing has been the same across the three
preceding incidents). `user-impact-reviewer` runs at PR review time per
`hr-weigh-every-decision-against-target-user-impact`.

## Hypotheses (ranked, to be narrowed during /work Phase 1 reproduction)

H1 is the highest-likelihood given the synthetic probe was green;
H2/H3 are remediation-time backstops.

### H1 — User cancelled OAuth consent (provider returns `error=access_denied`, no `code`)

**Upstream-documented behavior (verified via Context7
`/supabase/supabase` query of
`apps/docs/content/guides/auth/oauth-server/oauth-flows.mdx`):**

> "If the user approves access, Supabase Auth redirects back to the client's
> redirect URI with an authorization code. […] Conversely, if the user denies
> access, Supabase Auth redirects with error information in query parameters.
> These error parameters allow clients to display relevant error messages to
> users, providing details such as an error code and a human-readable error
> description."

Confirmed via the parallel `/v1/oauth/authorize` doc which shows the
verbatim shape:

> `HTTP/1.1 302 Found`
> `Location: YOUR_REDIRECT_URI?error=access_denied&error_description=The+user+denied+your+application+access.`

When a user clicks "Continue with Google" then hits Cancel at the consent
screen, Google redirects to `https://api.soleur.ai/auth/v1/callback?error=access_denied&error_description=...&state=...`.
Supabase's `/auth/v1/callback` handler responds with a 302 to the app's
`redirect_to` (passed in the original `signInWithOAuth` call as
`${window.location.origin}/callback`). Supabase **preserves the
`error`/`error_description` query params on the forward redirect** (per the
quote above) and does NOT synthesize a `code` (the OAuth round-trip never
produced one). Our route reads only `searchParams.get("code")` → null →
falls through to `op: "callback_no_code"`, conflating "user changed mind"
with "system broken."

Our `(auth)/callback/route.ts:11-20` reads `searchParams.get("code")` and
falls straight through to the `op: "callback_no_code"` branch. There is no
inspection of `error`/`error_description` from the inbound URL — the user's
"I changed my mind" is conflated with "the system is broken."

**Probe (during /work Phase 1):** Reproduce in Playwright with a fresh
profile: navigate to `app.soleur.ai/login`, click "Continue with Google",
hit Cancel at the Google consent screen, capture the inbound URL at
`app.soleur.ai/callback?...`. Expected: `error=access_denied` with no
`code`. Confirms H1 if the inbound URL matches.

### H2 — `uri_allow_list` rejected the redirect target (Supabase strips `code`)

Per `apps/web-platform/supabase/scripts/configure-auth.sh:41`, the
configured allow-list is `http://localhost:3000/**,https://app.soleur.ai/**`.
The wildcard pattern SHOULD match `/callback`, but two drift modes exist:

- The configured value is in the *script*, not in Terraform. There is no
  drift detection between the script's value and the live Supabase project
  config (the prior plan #2979 explicitly deferred verification due to a
  401 from the Supabase Management API token). If an operator manually
  edited the Supabase Dashboard auth URL Configuration → Redirect URLs,
  the script value is stale.
- `redirect_to` is passed verbatim by the client. If `window.location.origin`
  resolves to anything other than `https://app.soleur.ai` (e.g., a preview
  deploy, a vanity domain, a bot-fixture domain), the allow-list rejects
  the forward redirect and Supabase's standard behaviour is to fall back
  to `site_url` (`https://app.soleur.ai`) without forwarding `code` —
  same `callback_no_code` symptom.

**Probe:** Re-run the deferred Supabase Management API check from #2979
with the `prd_terraform` Doppler config (per the runbook
`oauth-probe-failure.md` "google_authorize / github_authorize" section).
Confirm the live `uri_allow_list` matches the script. Probe variant: in
Playwright, open `app.soleur.ai/login`, click Google, intercept the
`/auth/v1/authorize` request, manually mutate `redirect_to` to
`https://evil.example.com/callback`, and confirm Supabase rejects (or, if
the rejection is silent and falls back to `site_url`, that
fallback path is the leak that produces `callback_no_code`).

### H3 — Direct hit / stale link to `/callback` without an OAuth flow

Bookmarks, link previews in chat, search-engine cache, or a click on a
copy-pasted URL from a Discord/Slack thread. The browser GETs
`https://app.soleur.ai/callback` with no query params at all. The route
falls straight through to the `callback_no_code` branch.

**Probe:** Inspect the `referer` header on the next live event captured
in Sentry (per the new mirror extras planned below). If `referer` is
`accounts.google.com` / `github.com` / `api.soleur.ai`, H1 or H2; if
`referer` is `app.soleur.ai/login` or null/internal, H3.

### H4 — `searchParams.get("code")` returns null because of middleware mutation

The middleware (`apps/web-platform/middleware.ts`) does not mutate
query params today — it constructs `request.nextUrl.clone()` and sets
`pathname`, but never `searchParams`. The PUBLIC_PATHS allowlist
(`/lib/routes.ts` line 8 includes `/callback`) means the route bypasses
the auth-redirect block. Low likelihood; included only as a sweep.

**Probe:** `git log --oneline -- apps/web-platform/middleware.ts` and
confirm no recent changes between #2994 merge and the demo timestamp
that touch query-param handling.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Sentry/log ID `34d20156…` available for full context" | `SENTRY_AUTH_TOKEN` in Doppler `prd` has only `org:ci` scope (verified `curl /api/0/` returns `{"scopes":["org:ci"]}`); `events/<id>/` returns `403 You do not have permission` | Defer event-payload retrieval to /work Phase 1; reproduce H1/H3 in Playwright instead of relying on the live event. File a follow-up to widen the Sentry token scope to `event:read` (already a known gap from learning `2026-03-30-pkce-magic-link-same-browser-context.md` session error 2 — the gap has now blocked debugging twice) |
| "Investigate provider redirect config, PKCE/state mismatch, cookie/session loss between authorize and callback, middleware stripping query params" (issue body) | Three of these (PKCE/state mismatch, cookie/session loss, middleware stripping) only fire when the request DOES carry a `code` and the *exchange* fails — none of them produce `op: callback_no_code` (verified by tracing `route.ts:20` `if (code) {…}` block). The fallback fires *only* when `code` is null on inbound. | Re-scope hypotheses to the three real `callback_no_code` mechanisms (H1, H2, H3) plus a sweep gate (H4). The PKCE/cookie hypotheses from the issue body apply to PR #2994's `code_verifier_missing` branch, not this one |
| "Pull the Sentry event for this ID for full context" | Token scope is insufficient; live event payload is unreachable from this session | Use the runbook `oauth-probe-failure.md` triage table + Playwright reproduction as the substitute "full context" source |
| "Synthetic probe should have caught it" (implied) | Probe at 21:33Z (25 min after demo) was green; probe asserts authorize-leg only, not the *return* leg | Plan extends the probe in Phase 5 to assert error-tolerance behaviour on the return leg (a synthetic `?error=access_denied` GET against `/callback` should not fall through to the same `auth_failed` UX) |

## Files to Edit

- `apps/web-platform/app/(auth)/callback/route.ts` — branch on `searchParams.get("error") | "error_description"` BEFORE the `if (code)` block; route H1 (provider-side `error=access_denied`) to a distinct user-facing copy (`/login?error=oauth_cancelled`); add `url_path`/`referer_host`/`searchParamKeys` to the `callback_no_code` Sentry extras for root-cause-class queryability; write a typed `op: "callback_provider_error"` for H1 so #3004's "first user-triggered failure" expectation maps cleanly.
- `apps/web-platform/lib/auth/error-messages.ts` — add `oauth_cancelled` key with copy *"Sign-in cancelled. Click your sign-in option to try again."* (no "try email instead" — that copy is for genuine failures, not user choice). Add `oauth_failed` key (provider-side server_error / temporarily_unavailable class) with copy *"The sign-in service had a temporary problem. Please try again."*. The existing `provider_disabled` key — currently dead code per the deepen-plan finding — becomes live once the classifier change above lands. Total `CALLBACK_ERRORS` keys: `auth_failed`, `code_verifier_missing`, `provider_disabled`, `oauth_cancelled`, `oauth_failed`.
- `apps/web-platform/lib/auth/error-classifier.ts` — extend `classifyCallbackError` to map `provider_disabled` → `"provider_disabled"` (currently `provider_disabled` falls through to `auth_failed` despite a dedicated key in `CALLBACK_ERRORS`; this is a silent dead-code gap surfaced by deepen-plan). Update the doc-comment "Source of truth: @supabase/auth-js error-codes.d.ts (installed v2.49.0)" to v2.99.2 (verified by `apps/web-platform/node_modules/@supabase/auth-js/package.json`). The new sibling `classifyProviderError(searchParams: URLSearchParams): "oauth_cancelled" | "oauth_failed" | null` lives in a separate file (next bullet).
- `apps/web-platform/test/lib/auth/callback-error-mapping.test.ts` — extend with a case asserting `classifyCallbackError({ code: "provider_disabled" })` returns `"provider_disabled"` (currently nonexistent — would fail today). Keep the existing 5+5+misc cases intact.
- `apps/web-platform/test/app/auth/callback-route-branches.test.ts` (file does NOT exist today — `apps/web-platform/test/callback.test.ts` is taken by `resolveOrigin` tests; the route-level test must use a non-colliding filename). New file. Add cases: (a) `?error=access_denied` produces `/login?error=oauth_cancelled` and Sentry op `callback_provider_error`, (b) bare `/callback` (no params) still produces `/login?error=auth_failed` with the existing op, (c) `?code=valid` flow unchanged, (d) `?error=server_error` produces `/login?error=oauth_failed` (new key), (e) malformed `?error[]=access_denied` produces the bare-`/callback` branch (no provider_error path; see Sharp Edges).
- `.github/workflows/scheduled-oauth-probe.yml` — add a fifth probe step that GETs `https://app.soleur.ai/callback?error=access_denied` and asserts the response is a 302 (or 307) to `/login?error=oauth_cancelled` (NOT `/login?error=auth_failed`). Distinct `failure_mode: "callback_error_passthrough"` so the runbook's existing alphabet-of-failure-modes table can extend rather than re-label.
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — append a `### callback_error_passthrough` section under "Failure modes" with triage steps mirroring the existing structure (L3 first, then L7 confirmation via Playwright reproduction of the OAuth-cancel flow).
- *(removed in deepen pass — duplicated `oauth_failed` is folded into the unified `error-messages.ts` bullet above; one file, one edit point.)*

## Files to Create

- `apps/web-platform/lib/auth/provider-error-classifier.ts` — pure function `classifyProviderError(searchParams)` with explicit `Record<string, "oauth_cancelled" | "oauth_failed">` table. Keeps the discriminator in one auditable place for the post-PR Phase 5 negative-space test (parallel to `error-classifier.ts`'s `VERIFIER_CLASS_CODES`).
- `apps/web-platform/test/lib/auth/provider-error-classifier.test.ts` — unit tests for the new classifier.

## Open Code-Review Overlap

Open `code-review` issues that touch the same file set:

- **#3001** (`review: clear stale sb-*-auth-token-code-verifier cookies on OAuth callback failure`) — touches `apps/web-platform/app/(auth)/callback/route.ts`. **Disposition: Fold in.** The plan already edits the verifier-error branch indirectly (adds extras to the `callback_no_code` mirror; touching `route.ts` for H1 routing is the same file). Folding the cookie-sweep loop in makes the route's two failure branches symmetric. Amend the PR body to `Closes #3001`.

If no other matches: `None`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Reproduce H1 in Playwright (cancel Google OAuth at consent screen) with a clean profile against prod (read-only — no auth state mutated). Capture the inbound `/callback?error=access_denied&...` URL and confirm `op: callback_no_code` was the firing branch on `main` BEFORE the fix.
- [ ] After fix, the same Playwright run lands on `/login?error=oauth_cancelled` with the new "Sign-in cancelled" copy and Sentry receives `op: callback_provider_error` with extras `{ providerErrorCode: "access_denied", referer_host: "<google or supabase>", url_path: "/callback" }`.
- [ ] Direct hit to `https://app.soleur.ai/callback` (no params, no referer beyond browser address bar) still produces the existing `op: callback_no_code` branch and `/login?error=auth_failed` (H3 path is intentionally unchanged — the user is in an error state, not a cancel state).
- [ ] Existing `?code=valid` happy-path Playwright OTP/OAuth flow unchanged.
- [x] `apps/web-platform/test/lib/auth/provider-error-classifier.test.ts` covers `access_denied`, `server_error`, `temporarily_unavailable`, missing-error-param, and malformed/non-string `error` values.
- [x] `apps/web-platform/test/app/auth/callback-route-branches.test.ts` covers the four end-to-end branches above (provider-error access_denied / server_error / temporarily_unavailable + bare /callback fallback + malformed bracket form).
- [x] `vitest run` (apps/web-platform) green — 3052/3052 + 14 skipped, run at /work time.
- [x] `tsc --noEmit` clean.
- [ ] `next build` (web-platform-build CI step) clean — Phase-2.6 sharp-edge from `cq-nextjs-route-files-http-only-exports` (only HTTP handlers exported from `route.ts`).
- [ ] Multi-agent review (per `rf-review-finding-default-fix-inline`) — at minimum: `security-sentinel`, `user-impact-reviewer`, `data-integrity-guardian`, `test-design-reviewer`, plus the standard architecture/simplicity reviewers.
- [ ] PR body uses `Closes #<issue> #3001 Ref #3004 Ref #3005` (Ref because #3004/#3005 are post-merge follow-throughs that this PR tees up rather than fully resolves).
- [ ] `## User-Brand Impact` section present in the PR body with threshold = `single-user incident`; CPO sign-off acknowledged in PR description.
- [x] `error-classifier.ts` doc-comment cites the **installed** auth-js
  version (`2.99.2` at deepen time). Verification command in the PR
  description: `grep '"version"' apps/web-platform/node_modules/@supabase/auth-js/package.json | head -1`.
- [x] The new `classifyCallbackError({ code: "provider_disabled" })` →
  `"provider_disabled"` test case is added to
  `apps/web-platform/test/lib/auth/callback-error-mapping.test.ts` and
  passes (today this would map to `"auth_failed"` — confirms the silent
  dead-code wire-up).
- [x] The route-level test file is named
  `test/app/auth/callback-route-branches.test.ts` (NOT `callback.test.ts`
  — that filename is taken by the `resolveOrigin` tests; verified at
  deepen time).

### Post-merge (operator)

- [ ] Trigger `gh workflow run scheduled-oauth-probe.yml` and confirm the new `callback_error_passthrough` step runs and passes (verifies the new probe fixture is reachable).
- [ ] Within 7 days of merge, confirm a real-world Sentry event for `feature: auth, op: callback_provider_error` lands. If zero events in 7 days AND zero `op: callback_no_code` events with non-null `referer_host` matching a provider, file a follow-through to validate the mirror is wired (analogous to #3004).
- [ ] Within 5 business days, the deferred Supabase Management API verification of `uri_allow_list` from the #2979 follow-through completes (operator runs `apps/web-platform/scripts/verify-supabase-uri-allow-list.sh` if scripted, OR records dashboard screenshot in #2997 closing thread). Resolves H2 cleanly even if H1 is the reproduction.
- [ ] Close #3001 (cookie-sweep) since the disposition above folds it into this PR.
- [ ] Update #3004 / #3005 follow-throughs with the demo event id `34d20156467d46e28d89c7fc821b6d3a` as the load-bearing first user-triggered event evidence.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Marketing-adjacent
(brand-impact framing carried forward), Compliance (CLO — auth/PII handling).

### Engineering (CTO)

**Status:** carry-forward from #2994 / #3007 brainstorms (same module).
**Assessment:** This is the third file-level modification to
`apps/web-platform/app/(auth)/callback/route.ts` in 6 days (#2994, #3001
deferred, this PR). The route is becoming a hot-spot. Risk of accidental
regression on each touch is climbing; the `negative-space` and
`error-classifier-supabase-drift` tests added by #2994 cover only the
exchange-error branch. This plan adds parallel coverage for the
provider-error branch and the no-code-no-error fallback. After this PR,
all three branches of the route have unit + Playwright coverage. Consider
extracting the route into smaller per-branch helpers (`handleExchange`,
`handleProviderError`, `handleNoCode`) as a follow-up refactor — flagged
as a scope-out, not a blocker.

### Product/UX Gate

**Tier:** ADVISORY (modifies existing user-facing /login error copy; adds
a new copy variant `oauth_cancelled`; no new pages, no new flows).
**Decision:** auto-accepted (pipeline mode — plan is being deepened in a
one-shot pipeline). The new copy "Sign-in cancelled. Click your sign-in
option to try again." MUST be reviewed at /work time by the copywriter
agent (per AGENTS.md `hr-new-skills-agents-or-user-facing` content-review
gate trigger). If copywriter is unavailable, fold a one-line review
acknowledgment into the PR (UX surface here is a single string).
**Agents invoked at /work time:** copywriter (string review), no
ux-design-lead (no new visual surface — text only on existing /login).
**Skipped specialists at plan time:** spec-flow-analyzer (covered by Phase 3
explicitly via the route-branch decision-tree below).

### Compliance (CLO)

**Status:** carry-forward.
**Assessment:** No new PII forwarding. The new Sentry extras
(`url_path`, `referer_host`, `searchParamKeys`) are typed enums or
hostnames; the inbound URL itself is NOT forwarded (would carry the
`error_description` Supabase echoes verbatim from the provider, which
historically embeds account-specific text). The classifier gates on
`error` (an enum string from a published OAuth 2.0 spec) — not on free
text. No new schema, no migration, no auth-config rotation.

## Test Scenarios

Use the framework in `package.json scripts.test` (vitest, confirmed via
`apps/web-platform/package.json`).

### Phase 1: Reproduction (RED, no code yet)

1. Playwright against prod, fresh profile, no Supabase cookies. Navigate
   `app.soleur.ai/login` → click "Continue with Google" → at consent
   screen click "Cancel". Capture inbound URL. Assert it contains
   `app.soleur.ai/callback?` with `error=access_denied` and NO `code` key.
2. Curl-style probe: `curl -sI "https://app.soleur.ai/callback?error=access_denied" -L --max-redirs 1` — assert final URL is `app.soleur.ai/login?error=auth_failed` (the bug; will become `oauth_cancelled` after fix).

### Phase 2: Unit (RED → GREEN)

1. `provider-error-classifier.test.ts`:
   - `classifyProviderError(new URLSearchParams("error=access_denied"))` → `"oauth_cancelled"`.
   - `classifyProviderError(new URLSearchParams("error=server_error"))` → `"oauth_failed"`.
   - `classifyProviderError(new URLSearchParams("error=temporarily_unavailable"))` → `"oauth_failed"`.
   - `classifyProviderError(new URLSearchParams(""))` → `null`.
   - `classifyProviderError(new URLSearchParams("error_description=foo"))` → `null` (only error_description, no error key).
   - `classifyProviderError(new URLSearchParams("error[]=access_denied"))` → `null` (malformed array form: `getAll("error")[0]` ≠ `"access_denied"` because the bracket key is its own thing — explicit assertion).

2. `error-classifier.test.ts` (existing): keep verifier-class tests intact.

### Phase 3: Route-level (RED → GREEN)

1. Mock Next.js request with `searchParams: { error: "access_denied" }`,
   no `code`. Assert the route returns a redirect to
   `${origin}/login?error=oauth_cancelled` and `reportSilentFallback` was
   called with `op: "callback_provider_error"` and extras
   `{ providerErrorCode: "access_denied" }`.
2. Mock with `searchParams: {}` (no params at all). Assert the route
   returns the existing redirect to `${origin}/login?error=auth_failed`
   and `reportSilentFallback` op `callback_no_code`.
3. Mock with `searchParams: { code: "valid_code" }`. Mock
   `exchangeCodeForSession` to succeed. Assert the existing happy-path
   redirect (`/dashboard` for fully-onboarded user) is unchanged.

### Phase 4: Integration / Probe

1. The new step in `scheduled-oauth-probe.yml` (`callback_error_passthrough`):
   `curl -s --max-time 10 -o /dev/null -w '%{http_code} %{redirect_url}' --max-redirs 0 "https://app.soleur.ai/callback?error=access_denied"`.
   Assert HTTP 302 (or 307) AND `redirect_url` contains
   `/login?error=oauth_cancelled`. Failure mode `callback_error_passthrough`
   wired into the existing `record_failure` machinery.

### Phase 5: Negative-space drift guard

1. `apps/web-platform/test/lib/auth/callback-route-no-substring-match.test.ts`
   (existing — extend, don't duplicate): assert the new
   `provider-error-classifier.ts` does NOT use `error.message?.includes`,
   `.toLowerCase().includes()`, `regex.test()`, or `indexOf()` semantic
   equivalents on the provider error string. The discriminator must be
   `=== "access_denied"` or membership in a typed `Set`.

## Risks

### R1 — Regressing the existing `code_verifier_missing` UX path

The PR touches `route.ts` and `error-messages.ts`, both of which were
hardened by #2994. The unit-test guard
`apps/web-platform/test/lib/auth/error-classifier-supabase-drift.test.ts`
must remain green. **Mitigation:** keep the `if (code) { ... }` block's
internals untouched (only add a *pre-block* check for provider errors);
adding `oauth_cancelled` to `CALLBACK_ERRORS` is additive (existing keys
unchanged).

### R2 — Distinguishing H1 (cancel) from H2 (allow-list rejection)

Both surface `error=access_denied`-class strings on `/callback` from
Supabase's perspective (Supabase forwards provider-side errors verbatim;
allow-list rejections issue different parameters — see the Supabase Auth
JS source for the canonical mapping). **Mitigation:** the new
classifier returns `oauth_cancelled` for the user-cancel class and
`oauth_failed` for the server-error class; allow-list rejections fire
*before* reaching `/callback` (Supabase 4xx's the inbound `/auth/v1/callback`),
so they manifest differently and are caught by the existing probe's
`google_authorize` step. Add a `## Sharp Edges` note: if a future
regression makes Supabase forward allow-list-rejection errors *as*
`error=access_denied`, the new classifier silently maps them to "user
cancelled" — a P3 misclassification, not a brand-survival event.

### R3 — Sentry mirror leaks `referer` header

The `referer` header from a Google/GitHub redirect can include the
provider's canonical hostname (safe), but for cross-app referers (link
preview from a vendor that proxies the URL) it may leak unrelated
internal-tool URLs. **Mitigation:** the plan stores
`new URL(referer).host` only — never the full path/query of the referer.
Add an explicit `host` slice in the implementation (paste-protected by
unit test).

### R4 — Probe extension causes a flaky failure on Cloudflare cache miss

`scheduled-oauth-probe.yml` runs every 15min. Adding a fifth GET extends
the probe's success surface by one curl. Cloudflare may serve the
`/callback` response with cache-bypass already (it's in `PUBLIC_PATHS` and
returns a redirect — non-cacheable). **Mitigation:** verify with `curl -sI`
that `cache-control` on `/callback` is `no-cache`/`private`/`no-store`. If
the response is cacheable, add an explicit `Cache-Control` header to the
route (already present per Phase 5 redirect responses but worth asserting
in the test).

### R5 — User-Brand Impact for an empty referer = direct hit (H3)

H3 is the path where a user opens a stale link and sees `auth_failed`
copy. The plan does not change H3 UX. If a follow-up wants to detect H3
and show a smarter "you weren't signing in — go to /login" message, that's
a separate scope. Flagged as a scope-out for the next pass.

### R6 — Auth-js dep drift between code comment and installed version

The `error-classifier.ts` doc-comment cites *"installed v2.49.0"*; actual
installed is `2.99.2` (verified via
`apps/web-platform/node_modules/@supabase/auth-js/package.json`). The
existing drift-guard test
`apps/web-platform/test/lib/auth/error-classifier-supabase-drift.test.ts`
(added by #2994) reads the installed `error-codes.d.ts` shape — so
behavior is correct, only documentation is stale. Plan updates the comment
in the same edit that wires `provider_disabled`. **Mitigation:** the
existing drift-guard test is the load-bearing safety net; the
doc-comment is hygiene. Risk class: documentation-stale, not
behavior-stale; P3.

## Sharp Edges

- **`URLSearchParams` is case-sensitive AND bracket-literal** —
  `getAll("error")` differs from `getAll("Error")` (case). Also,
  `new URLSearchParams("error[]=access_denied").get("error")` returns
  `null` because the parsed key is literally `error[]`, not `error`
  (verified mentally against WHATWG URL spec; tested via the new
  malformed-input case in `provider-error-classifier.test.ts`).
  Together these mean: do NOT normalize the key with `.toLowerCase()`
  before lookup, do NOT trust bracketed array forms, do NOT split on `[`.
  Plan-test case (e) covers the bracket form; plan-test case (a) covers
  the canonical lowercase form. Mirrors the substring-fragility lesson
  from #2994.
- **Next.js 15 route file export discipline** — `(auth)/callback/route.ts`
  may export only HTTP handlers per `cq-nextjs-route-files-http-only-exports`.
  The new helper goes in a sibling module (`provider-error-classifier.ts`).
- **OAuth 2.0 `error` enum is closed** —
  `access_denied | server_error | temporarily_unavailable | invalid_request | invalid_scope | unauthorized_client | unsupported_response_type`.
  Map the first three explicitly; map all others to `oauth_failed` with
  a default branch. NEVER pass the raw `error` string through to the
  user-facing copy — only the typed enum should reach `error-messages.ts`.
- **A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6.** Threshold above is `single-user incident` —
  not placeholder.
- **The `referer` header is technically untrusted** — a malicious page can
  set its `Referrer-Policy` to leak any URL it wants. Treat
  `referer_host` as a *root-cause hint*, not a security signal. The
  Sentry mirror is the only consumer; no auth/RBAC decision branches
  on the value.
- **Sentry token scope blocks event lookup** — already documented in
  learning `2026-03-30-pkce-magic-link-same-browser-context.md` session
  error 2; this is the second time the gap has blocked debugging. File a
  follow-up to widen the token scope OR add a `sentry-event-lookup.sh`
  helper that uses the per-session OAuth flow when `org:ci` is
  insufficient. Do NOT block this PR on it.

## Detail Level

MORE — the bug class is well-bounded (single route, three branches), but
the failure-mode table, hypothesis ranking, and probe extension warrant
explicit acceptance criteria across pre-merge AND post-merge phases. The
A LOT template (with full ERD diagrams) is overkill; MINIMAL would lose
the H1/H2/H3 discriminator and let the implementer regress to
"just add a key to error-messages."

## Implementation Order

1. **Phase 1 — RED:** write `provider-error-classifier.test.ts` first
   (failing). Write the route-level test asserting `?error=access_denied`
   produces `/login?error=oauth_cancelled` (failing).
2. **Phase 2 — GREEN:** implement `provider-error-classifier.ts` + the
   route-level branch. Confirm tests pass.
3. **Phase 3 — Sentry mirror extras:** add `url_path`, `referer_host`
   (host-only), `searchParamKeys` (sorted array of keys, no values) to
   the existing `callback_no_code` mirror call AND the new
   `callback_provider_error` mirror call. Test.
4. **Phase 4 — Probe extension:** add the fifth step to
   `scheduled-oauth-probe.yml`. Run `gh workflow run` from the feature
   branch — note: per `cq-when-a-plan-prescribes-pre-merge-verification`
   (paraphrased — see plan-skill sharp edges), `workflow_dispatch` on a
   feature-branch workflow file requires the file to exist on the default
   branch. **Verification path:** the existing workflow on `main` is
   already triggerable; the new step is additive — ship the PR, then
   trigger the post-merge workflow run as part of the post-merge
   acceptance criterion.
5. **Phase 5 — Runbook update:** append the new failure-mode section to
   `oauth-probe-failure.md`. Verify the cross-link (`related_issues:`,
   `related_prs:` frontmatter) is correct.
6. **Phase 6 — Multi-agent review on the pushed branch.**
7. **Phase 7 — Ship.** Update #3004 / #3005 with the load-bearing event
   id; close #3001 in the same merge.

## Out of Scope / Deferred

- **Refactor `route.ts` into per-branch helpers (`handleExchange`,
  `handleProviderError`, `handleNoCode`).** Tracked separately; defer to
  the next auth touch.
- **Widen Sentry token scope to `event:read`.** File a separate follow-up
  issue (CTO-domain). Do not block this PR.
- **H3 (direct-hit) UX improvement.** Showing a "you weren't signing in"
  message requires distinguishing H3 from H1/H2 in the absence of any
  request-side signal except an empty referer. Defer.

## Network-Outage Deep-Dive

**Status:** not applicable. Phase 4.5 trigger scan against this plan
matched only the literal token "unreachable" once — and that hit was in
the `## Research Reconciliation` table, describing an *API token scope*
limitation (Sentry event-payload retrieval), not an L3/L7 network
outage. No `SSH`, `connection reset`, `kex`, `firewall`, `502/503/504`,
`handshake`, `EHOSTUNREACH`, or `ECONNRESET` symptoms in this plan.

The synthetic OAuth probe at 21:33Z on the demo day (25 min after the
user's failure) was **green** (verified via
`gh run list --workflow scheduled-oauth-probe.yml --limit 30 --created 2026-04-29`),
which is the strongest L3 health signal we have for the prod
auth-surface in the demo's adjacent window. The probe asserts:
DNS resolves, TLS terminates, Cloudflare proxies, Supabase
`/auth/v1/authorize` 302s correctly, and `/auth/v1/settings` returns
JSON with `external.{google,github}: true`. None of these failed at
the demo timestamp.

L3 verification is therefore short-circuited: a green probe at
21:33Z + the current plan addressing return-leg behavior on a
`code`-less inbound URL = no firewall/DNS hypothesis to chase. Phase 4.5
is satisfied without spawning a Network-Outage Deep-Dive sub-agent.

## Research Insights

**Best Practices (gathered from Context7 `/supabase/supabase` + installed
auth-js inspection):**

- The OAuth 2.0 spec error enum is closed and small —
  `access_denied | server_error | temporarily_unavailable | invalid_request | invalid_scope | unauthorized_client | unsupported_response_type`.
  Map the first three explicitly; default-branch the rest. NEVER pass
  the raw `error` string to user-facing copy.
- Supabase's own example callback handlers (Next.js / Express / Flask
  in Context7) all read only `code` and `next` — none read `error=`.
  The bug class we're fixing IS the documented Supabase pattern. Worth a
  one-line PR-body call-out at /work time so reviewers don't ask
  "is this an upstream bug?" — it's a documented but ungloved sharp
  edge.
- The closed enum + the
  `Record<string, "oauth_cancelled" | "oauth_failed">` table is the
  type-safe equivalent of `VERIFIER_CLASS_CODES: Set<string>`. Using
  `Record` (not `Set`) gives us both membership and target-bucket in one
  lookup — slightly cleaner than the existing pattern, but the existing
  pattern is fine; mirror it for consistency unless reviewers prefer
  the `Record` form.

**Edge Cases (gathered from the existing
`callback-error-mapping.test.ts` + WHATWG URL semantics):**

- `URLSearchParams.get("error")` returns the FIRST occurrence; multiple
  `error` keys (`?error=access_denied&error=server_error`) silently use
  the first. Test case (f) added to
  `provider-error-classifier.test.ts`: assert `getAll` semantics if the
  classifier ever needs to defend against duplicate keys (low priority;
  Supabase doesn't emit duplicates).
- Empty-string `?error=` (key present, value empty) — `get("error")`
  returns `""` (not `null`). Classifier must not treat `""` as a hit; the
  `Record` lookup with key `""` is `undefined`, which is the right
  behavior. Added test case (g).
- `error_description` is a free-text string; do NOT include it in the
  Sentry mirror (per User-Brand Impact section's PII discipline) or in
  user-facing copy. The error code is the only safe forward.

**References:**

- `apps/web-platform/node_modules/@supabase/auth-js/dist/module/lib/error-codes.d.ts` (installed v2.99.2, full enum).
- Context7: `/supabase/supabase` (`apps/docs/content/guides/auth/oauth-server/oauth-flows.mdx` — Step 4 user-denial behavior).
- Context7: `/supabase/supabase` (`apps/docs/content/guides/integrations/build-a-supabase-oauth-integration.mdx` — `/v1/oauth/authorize` 302 error response shape).
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` (governs `reportSilentFallback` invocation pattern).
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` (governs `## User-Brand Impact` framing).
- AGENTS.md `cq-nextjs-route-files-http-only-exports` (governs sibling-module placement of the new classifier).
- Knowledge-base learning `2026-03-30-pkce-magic-link-same-browser-context.md` (prior auth-flow incident; Sentry-token-scope gap).
- Knowledge-base learning `2026-04-28-sentry-payload-pii-and-client-observability-shim.md` (governs Sentry payload typed-fields-only discipline).

## Closes / Refs

- `Closes #<issue from /work>` (the new tracking issue for this demo failure).
- `Closes #3001` (cookie sweep, folded in per Open Code-Review Overlap).
- `Ref #3004` (Sentry visibility — this PR provides the load-bearing
  first-event evidence; #3004 stays open for the verification entry).
- `Ref #3005` (verifier_missing visibility — same).
