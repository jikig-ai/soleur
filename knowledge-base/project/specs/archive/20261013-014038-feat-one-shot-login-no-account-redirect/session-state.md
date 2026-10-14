# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-login-no-account-redirect/knowledge-base/project/plans/2026-05-04-fix-login-no-account-redirect-to-signup-plan.md
- Status: complete

### Errors
None. Two corrections were applied during the deepen pass (status code 422 → 400, banner state simplified) — both caught and fixed in-plan before any code was written.

### Decisions
- Status code 400, not 422. Verified directly against `node_modules/@supabase/auth-js/src/lib/errors.ts:47` (`AuthApiError(message, 400, code)` constructor).
- Detect via `error.code === "otp_disabled"` (primary) + regex on `error.message` (defense-in-depth fallback). `otp_disabled` is a typed member of the `ErrorCode` union in `error-codes.ts:68`.
- Banner is derived state, not `useState`. `showNoAccountBanner = reason === "no_account" && initialEmail.length > 0 && email === initialEmail` — auto-dismisses on first edit.
- `SUPABASE_ERROR_PATTERNS` adds `/signups? not allowed for otp/i` as defense-in-depth for any future call site that bypasses the redirect.
- Account enumeration framing kept as-is. Confirmed by upstream Supabase Auth issue #1547 — leak exists at the SDK layer; this PR routes the user through the existing leak, does not introduce a new one.
- Suspense wrap required on `/signup` because the new `useSearchParams()` call would otherwise fail `next build` on Next.js 15.5.
- Threshold `none` with sensitive-path scope-out reason — touches `lib/auth/**` but is UX polish; no credentials, no session material.

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:deepen-plan`
- Phase 4.6 User-Brand Impact gate (passed)
- Phase 4.5 Network-Outage gate (skipped — no triggers)
- Context7 MCP: `resolve-library-id` (`/supabase/supabase-js`)
- WebSearch (error response shape + status code verification)
- Direct source inspection: `node_modules/@supabase/auth-js/src/lib/{errors,error-codes,fetch}.ts`
