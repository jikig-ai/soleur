# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-signin-regression-2979/knowledge-base/project/plans/2026-04-28-fix-signin-regression-after-2979-plan.md
- Status: complete

### Errors
- Initial `gh pr view 2979` failed (issue, not PR) — recovered by querying `gh issue view 2979`. Confirmed the actual fix shipped as PR #2975 (`552bd2c5`).
- Supabase Management API (`/v1/projects/<ref>/config/auth`) returned 401 with `prd.SUPABASE_ACCESS_TOKEN`. Hypothesis H2 verification deferred to Phase 1.3 (operator probe).
- Sentry has zero auth events in 24h — confirmed there is no error signal because client-side `console.error` is not mirrored to Sentry (this gap IS H4 and is part of the fix).

### Decisions
- **Root-cause hypothesis H1 is most likely:** stale browser bundle (cached `_next/static` chunk OR service-worker cache) writes `code_verifier` cookie keyed against old project ref; new bundle's callback exchanges against new project ref → cookie name mismatch → `bad_code_verifier`; substring matcher misses → user lands at `/login?error=auth_failed` with the wrong copy.
- **Discriminate on typed `error.code` enum, not `error.message` substring.** Extract `lib/auth/error-classifier.ts` with a `Set<ErrorCode>` membership check.
- **Bump SW `CACHE_NAME` `v1` → `v2`, do NOT unregister SW.** Surgical 1-line fix preserves push-notification subscriptions.
- **Mirror to Sentry:** server-side via `reportSilentFallback`, client-side via `Sentry.captureException`.
- **`User-Brand Impact` threshold = `single-user incident`** → CPO sign-off + `user-impact-reviewer` at PR review.

### Components Invoked
- soleur:plan, soleur:deepen-plan
- gh CLI, doppler CLI, curl + dig
- Source-of-truth reads of `@supabase/auth-js@2.49.0`, `@supabase/ssr@0.6.0`, `@sentry/nextjs@10.46.0`, `public/sw.js`, `app/sw-register.tsx`, `server/observability.ts`, `reusable-release.yml`
- Phase 4.6 User-Brand Impact halt gate: PASSED
- Phase 4.5 network-outage trigger: NOT MATCHED
