# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-probe-octokit-jwt-diag/knowledge-base/project/plans/2026-05-28-fix-probe-octokit-jwt-diagnostics-and-retry-parity-plan.md
- Status: complete

### Errors
None. CWD verification passed. Deepen-plan hard gates 4.6 (User-Brand Impact), 4.7 (Observability), 4.8 (PAT-shaped variable) all passed.

### Decisions
- Framing verified against installed code: universal-github-app-jwt@2.2.2 index.js:17 already normalizes escaped \n and sets iat=now-30, exp=now+570. "Could not be decoded" is a structural/signature rejection, not expiry. Plan does NOT widen margins and does NOT touch github-app.ts/createAppJwt (scope guard AC8).
- Diagnostics-first: capture GitHub status, x-github-request-id, response body (sliced <=500, CR/LF-stripped), and measured clockSkewMs (Date.now() vs response Date header) off the thrown @octokit/request-error RequestError (.status + .response.{headers,data}).
- Retry parity is canonical: 3-attempt (1s,2s) 401-only backoff with fresh App/JWT per attempt, matching github-api.ts and github-app.ts precedent (not novel).
- Test runner is vitest (bunfig.toml blocks bun); extend existing probe-octokit-retry.test.ts RED-first.
- Credential/installation-identity mismatch is an explicit follow-up (refs closed #4543, PR #4557, PR #4565, runbook install ID 122213433); threshold none (platform-owned synthetic traffic, no founder-data surface).

### Components Invoked
- Skill soleur:plan
- Skill soleur:deepen-plan (gates 4.6/4.7/4.8 + precedent-diff 4.4 + verify-the-negative 4.45 inline; no sub-agents)
