# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-oauth-supabase-url/knowledge-base/project/plans/2026-04-28-fix-oauth-supabase-url-prod-plan.md
- Status: complete

### Errors
- Initial draft cited a non-existent rule `cq-ops-remediation-pr-uses-ref-not-closes`; replaced with `wg-use-closes-n-in-pr-body-not-title-to` during deepen.

### Decisions
- Root cause confirmed live (not hypothesized): deployed JS bundle at `https://app.soleur.ai/_next/static/chunks/app/(auth)/login/page-1145cd8d8475e73c.js` literally contains `https://test.supabase.co`. Doppler `prd` value (`https://api.soleur.ai`) is correct. The build reads `secrets.NEXT_PUBLIC_SUPABASE_URL` (GitHub repo secret, last updated 2026-04-27T10:50:45Z) — that is the actual mis-set source.
- Source-of-truth: Option A (CI-time consistency check between Doppler and GitHub secret) for P1 speed; Option B (migrate build-args to Doppler-only) tracked as deferred follow-up.
- Multi-layer defense: (1) pre-build CI regex `^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$` in `reusable-release.yml`, (2) runtime production guard in `lib/supabase/client.ts` (NODE_ENV-gated to preserve 24 test files), (3) post-deploy bundle probe (chunk filename discovered dynamically), (4) preflight Check 5 extending Check 4 to the GitHub-secrets blind spot.
- Phase 2.0: verify Supabase `uri_allow_list` includes `https://app.soleur.ai/callback` BEFORE rotating the secret — otherwise OAuth fails post-consent with `redirect_to is not allowed`.
- AC9.1 JWT-ref consistency: anon-key JWT `ref` claim must match the project ref behind the URL (direct for canonical, CNAME-deref for custom domain).

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
