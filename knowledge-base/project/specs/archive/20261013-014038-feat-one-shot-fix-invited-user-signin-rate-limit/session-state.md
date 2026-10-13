# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-fix-invited-user-signin-otp-rate-limit-plan.md
- Status: complete

### Errors
None. CWD verified equal to WORKING DIRECTORY. Branch is not main. All deepen-plan enforcement gates passed (4.6 User-Brand Impact present, 4.7 Observability 5-field schema valid + no SSH, 4.8 no PAT-shaped variables). All cited rule IDs and learning paths exist on disk.

### Decisions
- Root cause identified and verified (context7 Supabase Auth Rate Limits): "Too many sign-in attempts" is the friendly-map of GoTrue's `email rate limit exceeded` (`lib/auth/error-messages.ts:26`), NOT the in-app `with-user-rate-limit.ts`. The `/auth/v1/otp` endpoint enforces a 60-second per-user window; the broken invite flow forces a second `signInWithOtp` to the same email inside that window.
- The invite→signup→login `redirectTo` chain is broken: `invite-actions.tsx` links to `/signup?redirectTo=/invite/<token>` but `signup/page.tsx` never reads `redirectTo` and hardcodes `router.push("/accept-terms")`, dropping the invite and forcing re-request of a code. Fix: (A) honor `redirectTo` through signup/login/OAuth-callback, (B) add a ≥60s client-side resend cooldown with distinct copy.
- Precedent-diff (Phase 4.4): an existing `lib/safe-return-to.ts` sanitizer was found — plan generalizes it (allowlist `/dashboard` + `/invite/`, return null on reject) and sweeps its one consumer (`connect-repo`), instead of inventing a parallel `lib/auth/redirect.ts`.
- Verified facts: test runner is `vitest`; middleware (`middleware.ts:325-326`) enforces T&C from any route; an authenticated invitee re-opening `/invite/<token>` triggers NO OTP, so the rate-limit cannot recur post-auth.
- Code-review overlap dispositioned: #3184 and #3739 both Acknowledged with rationale; no fold-in.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- mcp__plugin_soleur_context7__query-docs (Supabase Auth rate limits — root-cause verification)
- Bash, Read, Edit, Write, ToolSearch
