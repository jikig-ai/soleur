---
feature: feat-one-shot-fix-invite-accept-workspace-linking
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-29-fix-invite-accept-workspace-linking-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — Fix invite-accept → workspace-membership linking

Derived from the finalized plan. The bug: the new-user invite path drops the
return-to target at three points, so `accept_workspace_invitation` is never called —
the invitee gets an isolated new workspace and the invite stays Pending.

## Phase 0 — Preconditions (read before editing)

- [ ] 0.1 Confirm CPO sign-off on Option A vs Option B (plan requires_cpo_signoff). Default: Option A (land-on-invite-page, explicit Accept).
- [ ] 0.2 Confirm test runner: `cat apps/web-platform/package.json | grep -A2 '"test"'` (expect vitest).
- [ ] 0.3 Read `apps/web-platform/lib/safe-return-to.ts` (validator), `connect-repo/page.tsx` `return_to` usage (`:461,473,549`), `accept-terms` + `setup-key` page post-completion pushes — confirm which forward `return_to` and which hardcode.
- [ ] 0.4 `gh issue list --label code-review --state open --json number,title,body --limit 200` and jq each Files-to-Edit path → record overlap disposition in plan.

## Phase 1 — Validator (security-critical, RED first)

- [ ] 1.1 Write failing `safe-return-to.test.ts`: assert valid `/dashboard*`, valid `/invite/<token>`, and reject `https://evil`, `//evil`, `/\evil`, `\\evil`, `/invite/../dashboard`.
- [ ] 1.2 Widen `safeReturnTo()` allowlist to accept `/invite/<token>` shape (safe token charset), keeping all existing rejection vectors. Make 1.1 green.

## Phase 2 — Producer/consumer wiring

- [ ] 2.1 Rename invite links `redirectTo` → `return_to` in `invite-actions.tsx` (`:58`, `:66`, `:107`).
- [ ] 2.2 `signup/page.tsx` `handleVerifyOtp`: read `return_to`, `safeReturnTo()`, redirect there instead of hardcoded `/accept-terms` (loss point 1).
- [ ] 2.3 `login-form.tsx` `handleVerifyOtp` (`:119`): same treatment instead of hardcoded `/dashboard` (loss point 3). Carry `return_to` forward on the no-account → `/signup` bounce (`:78-85`).
- [ ] 2.4 `oauth-buttons.tsx` (`:75`): append validated `return_to` to the Supabase `${origin}/callback` URL.
- [ ] 2.5 `callback/route.ts`: read + validate `return_to`; redirect there after gates pass (instead of `/dashboard`); carry it forward when funneling to `/accept-terms`/`/setup-key`/`/connect-repo` (loss point 2).
- [ ] 2.6 Onboarding pages (accept-terms / setup-key / connect-repo): thread carry-forward `return_to` ONLY where a post-completion push would drop it (per 0.3 findings).

## Phase 3 — Tests + verification

- [ ] 3.1 AC4 integration test `invite-new-user-join.test.ts` (mocked Supabase): invite → signup → verify → return to `/invite/<token>` → Accept → `workspace_members` row in inviter's workspace + `accepted_at` set + invite leaves Pending. Assert RPC-call/row shape, not just HTTP 200.
- [ ] 3.2 Regression: `invite-actions-gating.test.tsx`, accept-invite route test, `callback-route-branches.test.ts`, no-redirectTo new-signup funnel all green (AC6, AC7).
- [ ] 3.3 Observability: callback validator rejection emits `warnSilentFallback(op: redirect_target_rejected)`.
- [ ] 3.4 Run `/soleur:gdpr-gate` against the diff (Phase 2 exit). Run full `package.json scripts.test`.

## Phase 4 — Post-merge (operator, automatable)

- [ ] 4.1 AC8 live verification on **dev** (never prod): Playwright MCP re-run of the invite scenario + Supabase MCP read of `workspace_members` for the new row. `Automation: feasible`.
