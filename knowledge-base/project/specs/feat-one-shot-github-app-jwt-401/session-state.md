# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-28-fix-github-app-jwt-401-exp-margin-retry-backoff-plan.md
- Status: complete

### Errors
- None. CWD verified before plan write; deepen-plan gates 4.6/4.7/4.8/4.4 passed; PR #4498 verified MERGED; KB citations resolve.

### Decisions
- Scope correction: two App-JWT minting paths exist — hand-rolled createAppJwt() in github-app.ts (THE bug, exp=now+600) and @octokit/app via probe-octokit.ts (uses universal-github-app-jwt, exp=now+570 with built-in 30s margin → NOT vulnerable). drift-guard/oauth-probe are OUT of scope; AC6 asserts probe-octokit.ts untouched.
- Both root causes confirmed against installed code: createAppJwt exp: now+10*60 at github-app.ts:124-125; single 1s 401-retry at :491-496. Fix: exp → now+540 (9 min); widen to 3 attempts with exponential backoff.
- Adopted in-repo canonical backoff precedent (github-api.ts:21-22,56-95: MAX_RETRIES=2, BASE_DELAY_MS*2**attempt, body-drain) verbatim; documented deliberate divergence (401-only retry predicate vs 5xx/network).
- This incident is the unresolved tail of merged PR #4498 (added the single retry, never fixed the exp boundary); 90 events firstSeen 2026-05-25 are post-#4498.
- Test via vitest (bun blocked); exp-margin asserted by decoding the captured Bearer JWT; post-deploy Sentry verification via SENTRY_IAC_AUTH_TOKEN (only token with issue-read scope), no SSH. Threshold single-user incident → requires_cpo_signoff.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Tools: Bash, Read, Write, Edit
