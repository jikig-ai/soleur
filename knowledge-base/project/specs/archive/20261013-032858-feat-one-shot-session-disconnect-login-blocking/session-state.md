# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-15-fix-session-disconnect-and-login-rate-limit-blocking-plan.md
- Status: complete

### Errors
None. CWD verified equal to the worktree on first tool call. Branch is `feat-one-shot-session-disconnect-login-blocking` (not main). All deepen-plan halt-gates passed; all KB citations resolve.

### Decisions
- Two independent root causes, two phases. Symptom 1 (session drop) = the #4307 revocation gate in `middleware.ts` (fail-closed 503-for-all on transient `check_my_revocation` RPC error + cookie-clear-to-/login on non-removal JWT-decode hiccups + redundant `getUser()`+`getSession()`). Symptom 2 (login blocking) = GoTrue default rate limits (`configure-auth.sh` sets zero `rate_limit_*` fields).
- Fix direction: preserve the security boundary, relax only transient/non-removal failures. Genuine-revoked path stays fail-closed; fail-OPEN over-correction (re-opens #4307 leak) is the primary review risk.
- Deepen-plan reversed a wrong hypothesis: migration 067's strict comparison is deliberately deny-favoring; fix is `middleware.ts`-only, no migration.
- Two plan claims corrected against code: login already sets `shouldCreateUser:false`; the two rate-limit error messages are already distinct (AC6 re-scoped to regression guard); vitest `include:` globs corrected.
- GoTrue Management-API fields confirmed via OpenAPI. Marked `single-user incident` / `requires_cpo_signoff: true`; `semver: patch`; domains engineering + product.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agents: learnings-researcher, git-history-analyzer, framework-docs-researcher (x2), Explore
