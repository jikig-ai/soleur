---
date: 2026-05-04
plan: ../../plans/2026-05-04-fix-auth-callback-no-code-or-exchange-error-plan.md
branch: feat-one-shot-auth-callback-no-code-or-exchange-error
issue: TBD (file from /work)
---

# Tasks: Fix auth callback `op: callback_no_code`

Derived from `2026-05-04-fix-auth-callback-no-code-or-exchange-error-plan.md`.

## 1. Setup

1.1. File the GitHub issue for this demo failure with the Sentry/log id
     `34d20156467d46e28d89c7fc821b6d3a` referenced in the body. Label
     `priority/p1-high`, `type/bug`, `domain/engineering`. Milestone:
     current sprint.
1.2. Verify `/work` Phase 0 prerequisites: branch is on remote, worktree
     is current, `bun install` passes, `vitest` runs to completion on a
     dry baseline.

## 2. RED — Failing tests first (TDD gate per `cq-write-failing-tests-before`)

2.1. Create `apps/web-platform/lib/auth/provider-error-classifier.ts`
     skeleton (no implementation — exports the function signature only,
     throws `Error("not implemented")`).
2.2. Create `apps/web-platform/test/lib/auth/provider-error-classifier.test.ts`
     with all seven cases from plan Phase 2:
     - `access_denied` → `"oauth_cancelled"`.
     - `server_error` → `"oauth_failed"`.
     - `temporarily_unavailable` → `"oauth_failed"`.
     - empty searchParams → `null`.
     - only `error_description` (no `error`) → `null`.
     - bracketed key `error[]=access_denied` → `null`.
     - empty-string `error=` → `null`.
2.3. Create `apps/web-platform/test/app/auth/callback-route-branches.test.ts`
     with the five route-level cases from plan Phase 3:
     (a) `?error=access_denied` → `/login?error=oauth_cancelled` + Sentry op `callback_provider_error`.
     (b) bare `/callback` → `/login?error=auth_failed` + Sentry op `callback_no_code`.
     (c) `?code=valid` happy path → `/dashboard` (mocked exchange + onboarded user).
     (d) `?error=server_error` → `/login?error=oauth_failed`.
     (e) malformed `?error[]=access_denied` → bare-`/callback` branch (no provider_error path).
2.4. Extend `apps/web-platform/test/lib/auth/callback-error-mapping.test.ts`
     with the new `provider_disabled` → `"provider_disabled"` case.
2.5. Run `vitest run` — confirm new tests fail (RED).

## 3. GREEN — Minimal implementation

3.1. Implement `classifyProviderError(searchParams)` in
     `apps/web-platform/lib/auth/provider-error-classifier.ts` using a
     `Record<string, "oauth_cancelled" | "oauth_failed">` table.
3.2. Extend `apps/web-platform/lib/auth/error-classifier.ts`:
     - Add `"provider_disabled"` to the union return type and map
       `error.code === "provider_disabled"` → `"provider_disabled"`.
     - Update doc-comment from `(installed v2.49.0)` to
       `(installed v2.99.2)`. Verification command: `grep '"version"'
       apps/web-platform/node_modules/@supabase/auth-js/package.json`.
3.3. Add the keys `oauth_cancelled` and `oauth_failed` to
     `apps/web-platform/lib/auth/error-messages.ts` `CALLBACK_ERRORS`.
     Copy per plan Files to Edit.
3.4. Edit `apps/web-platform/app/(auth)/callback/route.ts`:
     - BEFORE the `if (code) { ... }` block, call
       `classifyProviderError(searchParams)`. If it returns non-null,
       call `reportSilentFallback(null, { feature: "auth", op:
       "callback_provider_error", message: ..., extra: { providerErrorCode,
       url_path: "/callback", referer_host: <host-only slice>,
       searchParamKeys: <sorted keys array> } })` and redirect to
       `${origin}/login?error=${classifierResult}`.
     - In the bottom-of-function fallback (existing
       `op: "callback_no_code"` branch), also extend `extra` to include
       `url_path`, `referer_host`, `searchParamKeys` for symmetry.
3.5. Fold in #3001: in the verifier-class error branch (existing
     `if (error)` block), iterate `request.cookies.getAll()` and clear
     any cookie matching `/^sb-[a-z0-9]{20}-auth-token-code-verifier$/`
     via `response.cookies.set(name, "", { maxAge: 0, path: "/" })`
     before the redirect.
3.6. Run `vitest run` — confirm all tests pass (GREEN).

## 4. Probe extension

4.1. Add fifth probe step to `.github/workflows/scheduled-oauth-probe.yml`:
     `check_callback_error` function that GETs
     `https://app.soleur.ai/callback?error=access_denied` with
     `--max-redirs 0`, asserts HTTP is 302 (or 307) AND
     `redirect_url` contains `/login?error=oauth_cancelled`. Failure
     mode: `callback_error_passthrough`.
4.2. Append `### callback_error_passthrough` section to
     `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md`
     under "Failure modes" with L3-first triage steps.

## 5. Type/build/test gates

5.1. `tsc --noEmit` clean.
5.2. `vitest run` (apps/web-platform) all green.
5.3. `next build` (web-platform-build CI step) passes — confirms route-file
     export discipline per `cq-nextjs-route-files-http-only-exports`.

## 6. Multi-agent review

6.1. Push branch to remote (per `rf-before-spawning-review-agents-push-the`).
6.2. Run `skill: soleur:review` and ensure these agents at minimum:
     `security-sentinel`, `user-impact-reviewer`, `data-integrity-guardian`,
     `test-design-reviewer`, `architecture-strategist`, `code-simplicity-reviewer`,
     `pattern-recognition-specialist`.
6.3. Resolve all P1/P2 inline; file P3 as scope-outs per
     `rf-review-finding-default-fix-inline`.

## 7. Compound + Ship

7.1. `skill: soleur:compound` to capture learnings (esp. the
     "Supabase docs document return-leg error forwarding but example
     code doesn't read it" learning, and the "auth-js doc-comment
     drift" learning).
7.2. `skill: soleur:ship` — confirms preflight Check 6
     (`User-Brand Impact` section present + threshold valid).
7.3. PR body uses `Closes #<issue> #3001` and `Ref #3004 #3005`.

## 8. Post-merge

8.1. `gh workflow run scheduled-oauth-probe.yml` — verify new
     `callback_error_passthrough` step passes.
8.2. Within 7 days: confirm `feature: auth, op: callback_provider_error`
     event lands in Sentry (close-out for #3004 / #3005).
8.3. Operator runs the deferred Supabase Management API
     `uri_allow_list` verification from #2979 (closes residual H2
     hypothesis).
8.4. `gh issue close 3001` once the cookie-sweep code is verified live.
8.5. Update `knowledge-base/project/learnings/` with the deepen-pass
     findings (Supabase example pattern, auth-js drift, Sentry token
     scope gap second-occurrence).
