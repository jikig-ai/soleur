# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-auth-callback-no-code-or-exchange-error/knowledge-base/project/plans/2026-05-04-fix-auth-callback-no-code-or-exchange-error-plan.md
- Status: complete

### Errors
- Sentry event-payload retrieval blocked: Doppler `SENTRY_AUTH_TOKEN` (prd) has only `org:ci` scope; live event `34d20156467d46e28d89c7fc821b6d3a` returned `403`. Second occurrence (first noted in learning `2026-03-30-pkce-magic-link-same-browser-context.md`). Recorded as Sharp Edge with follow-up; non-blocking. Plan substitutes runbook + Playwright reproduction for full event context.
- `org:ci`-scope blocker captured in Research Reconciliation table so the implementer doesn't waste time retrying the API.

### Decisions
- Symptom string `"Auth failed — no code or exchange error"` matches `route.ts:148` `op: "callback_no_code"` — bottom-of-function fallback, NOT the verifier-class branch. Scope: no-`code`-param class, not exchange-error class. Different failure class than #2994 hardened.
- H1 (user cancelled OAuth at consent screen → Supabase forwards `error=access_denied&error_description=…` to `/callback`) is highest-likelihood root cause. Verified via Context7 `/supabase/supabase` as upstream-documented behavior. Synthetic OAuth probe was green at 21:33Z (25 min after demo failure 21:08Z), eliminating L3/network-outage hypotheses.
- Fix: add `classifyProviderError(searchParams)` (sibling to `classifyCallbackError`); branch BEFORE `if (code)` to route `?error=access_denied` → `/login?error=oauth_cancelled` (new copy: "Sign-in cancelled. Click your sign-in option to try again."), `?error=server_error` → `/login?error=oauth_failed`. New Sentry op: `callback_provider_error`.
- Deepen surfaced silent dead code: `apps/web-platform/lib/auth/error-messages.ts` has `provider_disabled` key, but `error-classifier.ts` never maps `error.code === "provider_disabled"` to it. Plan wires this up in same PR (1-line fix + 1 test case).
- Auth-js drift: doc-comment says `(installed v2.49.0)`; actual installed is `2.99.2`. Plan updates the comment in same edit.
- Folded in #3001 (clear stale `sb-*-auth-token-code-verifier` cookies on verifier-class failure) per Open Code-Review Overlap fold-in disposition. `Closes #3001`.
- Probe extension: `scheduled-oauth-probe.yml` gets a fifth step (`callback_error_passthrough`) to assert `?error=access_denied` lands on `/login?error=oauth_cancelled`. Runbook `oauth-probe-failure.md` extended with new failure-mode triage section.
- `## User-Brand Impact` present with threshold = `single-user incident`; CPO sign-off carry-forward from #2979/#3006/#2994 documented.

### Components Invoked
- soleur:plan (pipeline phase 1)
- soleur:deepen-plan (pipeline phase 2)
- mcp__plugin_soleur_context7__query-docs (`/supabase/supabase` x2)
- Read against installed `@supabase/auth-js@2.99.2` source + existing test files
- gh CLI (issue list/view, pr view, run list/view --log) for #3001/#3004/#3005/#2997/#3007/#2994/#3006/#2979
- Doppler CLI for SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT
- curl against sentry.io API for token-scope verification
