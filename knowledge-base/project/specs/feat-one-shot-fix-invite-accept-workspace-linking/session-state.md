# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-fix-invite-accept-workspace-linking-plan.md
- Status: complete

### Errors
None. CWD verified against the worktree path on first tool call. Branch is the feature branch (not main). All three deepen-plan mandatory gates passed (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-halt).

### Decisions
- Root cause confirmed by code reading: new-user invite path drops the return-to target at three points — `signup/page.tsx:94` (hardcoded `router.push("/accept-terms")`), `login-form.tsx:119` (hardcoded `/dashboard`), and `callback/route.ts` (never reads any return param, funnels through onboarding + provisions a fresh workspace). So `accept_workspace_invitation` is never called → invitee gets isolated workspace, invite stays Pending. The accept RPC and `/api/workspace/accept-invite` route are correct but never reached.
- Validator `lib/safe-return-to.ts` `safeReturnTo()` already exists but allowlist is `/dashboard`-only and would silently reject `/invite/<token>`. Plan mandates widening that validator (the single security-critical edit), not adding a parallel one. Flags "naive reuse" as the most likely fix-mistake.
- Param-name drift: invite links emit `?redirectTo=` while codebase convention + validator use `return_to`. Plan standardizes on `return_to`.
- OAuth + no-account nuances captured: `oauth-buttons.tsx:75` `redirectTo` is the Supabase callback URL (must append `return_to` to it); login no-account → `/signup` bounce also drops the target.
- Threshold `single-user incident`; `requires_cpo_signoff: true`; redirect surface treated as open-redirect/phishing vector with mandatory reject-vector tests. Option A (land-on-invite-page, explicit Accept) recommended over Option B (auto-accept) pending CPO sign-off.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash, Read, Write, Edit
