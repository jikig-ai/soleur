---
date: 2026-05-24
category: security-issues
tags: [tokens, github-app, child-process, spawn, cache, expiry, ttl]
source_pr: 4377
source_issue: 4376
related_learnings:
  - 2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns
  - 2026-05-19-inngest-substrate-five-bug-cascade
applies_to:
  - apps/web-platform/server/inngest/functions/cron-*.ts (long-running spawns)
  - apps/web-platform/server/github-app.ts (generateInstallationToken cache)
---

# Token cache safety margin ≠ consumer wall-clock budget

## Problem

PR #4377 (TR9 PR-5, `cron-bug-fixer` Inngest migration) introduced a long-running `child_process.spawn` (`claude` binary, 50-min `MAX_TURN_DURATION_MS` budget) whose env carried a GitHub App **installation token** minted via `generateInstallationToken()`. The plan's deepen pass enumerated three facts as if they were independent:

1. Installation token TTL = 1 hour
2. `generateInstallationToken()` has a 5-min cache safety margin (won't return a token with <5min remaining; mints fresh instead)
3. claude-eval step.run budget = 50 min

The implementation called `mintInstallationToken` once at the top of the handler and reused the cached token across all step.runs. **Plan-time reasoning treated these three facts as orthogonal.**

Security-sentinel review caught the actual constraint: **the cached token's REMAINING lifetime at the moment of consumer-entry must envelope the consumer's wall-clock budget.** A token minted 14 min ago has 46 min remaining (well above the 5-min cache margin), but 46 min < 50 min spawn budget → token expires mid-spawn → late-run `gh issue view`, `gh pr create`, or any other GH API call inside the spawned claude fails with `Bad credentials` → agent retries (burning more budget) → eventually self-aborts or hits `MAX_TURN_DURATION_MS` → detect-pr finds no PR → run silently lost.

The failure mode is **silent under-completion**: Sentry sees a `?status=error` heartbeat (because no PR was detected for auto-merge) but the root cause (`Bad credentials` deep inside the agent's tool calls) never surfaces.

## Root cause

**Conflating "cache replacement policy" with "consumer-side validity guarantee."**

The 5-min cache safety margin's purpose is to prevent `mintInstallationToken()` from returning a token that's about to expire **from the perspective of a sub-second consumer** (an Octokit REST call, a GraphQL mutation, a heartbeat fetch). It DOES NOT guarantee the token is valid for arbitrary downstream consumers. A 50-min consumer needs a different guarantee: "min remaining lifetime ≥ 50 min + buffer."

The token cache was designed for the dominant existing consumer class (single-call REST operations completing in milliseconds). Long-running spawns are a NEW consumer class introduced by ADR-033's claude-subprocess pattern. The cache contract was never updated to reflect the new constraint.

## Solution

Extend `generateInstallationToken()` with an optional `minRemainingMs` parameter. When set, the cache check becomes:

```typescript
if (cached.expiresAt - Date.now() < minRemainingMs) {
  // cached token is technically still valid, but won't outlive the consumer's budget
  // — force re-mint
  tokenCache.delete(installationId);
}
```

Callers with long-running consumers pass `minRemainingMs = consumerBudgetMs + slackMs`. PR-5 uses `MAX_TURN_DURATION_MS + 10 * 60 * 1000` (50 min + 10 min slack) — guarantees the spawn starts with a token that outlives the claude-eval AbortController budget.

Implementation: `apps/web-platform/server/github-app.ts` accepts `opts.minRemainingMs`; `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts:mintInstallationToken` passes the 60-min floor.

## Key insight

**Cache replacement policies are defined relative to the dominant consumer class at design time.** When a new consumer class is introduced (long-running spawn, batch operation, websocket session), the cache contract MUST be re-evaluated for the new class. The fix is parametric (caller passes the budget envelope) rather than absolute (bump the global safety margin) so other consumer classes don't pay the cost.

Generalizing: **any time a feature combines (a) a TTL'd credential with (b) a long-running operation that uses it, write down the envelope inequality explicitly:**

```
credential.remaining_at_consumer_entry >= consumer.max_wall_clock + slack
```

If the existing credential factory doesn't expose a way to enforce the inequality, that's the bug. Don't trust the dominant-case safety margin to cover edge cases.

## Prevention

1. **Plan-time envelope check:** when a plan introduces a long-running operation (`step.run` with >10min budget, `setInterval`, websocket open, batch loop) that consumes a TTL'd credential (installation token, signed URL, OAuth access token, JWT), explicitly compute the envelope inequality in the plan's Q-section. Verify the factory can enforce it. If not, scope a factory extension.
2. **Factory API:** any token/credential factory with a cache should expose `minRemainingMs` (or equivalent) as a first-class parameter. Without it, callers must clear the cache + re-mint manually, which is error-prone.
3. **Test pattern:** for handlers that spawn long-running subprocesses with TTL'd credentials, add a test that asserts the credential's remaining lifetime at spawn-entry is ≥ the spawn budget. Mock the cache to return a token with `expiresAt = now + spawnBudget - 1min` and assert the handler forces a re-mint.
4. **Review checklist update:** the security-sentinel review template should include "for any spawn/long-op consuming TTL'd credentials, verify the envelope inequality holds against the worst-case cached token age."

## Session Errors

1. **Plan-time blind spot on token-cache vs spawn-budget envelope** — Recovery: HIGH-1 review finding + `minRemainingMs` parameter extension. **Prevention:** add plan-time gate "for any TTL'd credential consumed by a >10min operation, write the envelope inequality explicitly" to deepen-plan Phase 4 checklist.
2. **stdio:"inherit" + write-scoped GH_TOKEN = prompt-injected leak vector** — Recovery: HIGH-2 fix switched to `stdio:"pipe"` with readline-based `redactToken()` line interception. **Prevention:** when copying a spawn pattern from a sibling handler, re-evaluate the stdio shape against the new env contents — `inherit` is safe ONLY if the spawn env contains no write-scoped credentials.
3. **Auto-merge GraphQL idempotency documented but not implemented** — Recovery: case-insensitive substring match on 4 "already enabled" error message variants. **Prevention:** any plan section that documents idempotency MUST have a corresponding test case that exercises the idempotent path; otherwise the prose is decorative.
4. **Test gaps: token-redaction sentinel sweep, workspace cleanup, auto-merge replay** — Recovery: 6 new tests added in commit `af61e8b6`. **Prevention:** when the plan declares defense-in-depth invariants (`redactToken` everywhere, `try/finally` cleanup, idempotent retries), each invariant needs a dedicated test — assertion-by-absence is fragile.
5. **Comment rot: `/mnt/data/repos/jikig-ai-soleur` option-letter framing** — Recovery: rewrote handler header to positive frame. **Prevention:** before commit, grep handler files for plan-deliberation language ("option (a)", "option (b)", "preferred path", "fallback option") — these are plan-time leftovers that don't belong in shipped code.
6. **mkdtemp prefix mismatch with header docs** — Recovery: prefix aligned to `"soleur-cron-bug-fixer-"`. **Prevention:** when header comment cites a literal path, grep for it in the same file to confirm implementation matches.
7. **`buildSpawnEnv` comment framed as denylist when implementation is allowlist** — Recovery: comment reworded. **Prevention:** when a helper enforces an invariant via "include only X" (whitelist) shape, the comment MUST use whitelist language; "NEVER include Y" framing is a denylist pattern that fights the implementation.
8. **`SOLEUR_PLUGIN_PATH` env override unvalidated** — Recovery: added `/app/` prefix allowlist with VITEST bypass. **Prevention:** any env-var override that resolves to a filesystem path MUST validate the path is under an allowed prefix; otherwise an attacker who controls env owns the symlink target.
9. **Sharp Edge #6 (Hetzner bare-clone path) deferred at plan time without Phase 0 verification** — Recovery: /work Phase 0 ran `grep -rE 'git clone|bare|/mnt/data/repos|jikig-ai-soleur' apps/web-platform/infra/cloud-init.yml` (0 matches) → confirmed option (b) not provisioned → fell back to option (c) (in-handler clone). **Prevention:** when a plan declares a Sharp Edge as "the SINGLE biggest deferral risk", the plan MUST cite a Phase 0 verification command that resolves the risk to a concrete (option-locked) outcome before /work starts. Don't ship plans with unresolved single-biggest deferrals.

## Related

- PR-1 #3985 (cron-daily-triage) — pattern source; does NOT spawn with a write-scoped GH_TOKEN, so HIGH-2 didn't apply
- PR-3 #4227 (cron-oauth-probe) — first cron-* with `createProbeOctokit`; sub-second consumer, HIGH-1 didn't apply
- PR-4 #4303 (cron-github-app-drift-guard) — `createAppJwtOctokit` for app-level JWT; spawn is `child_process.spawn` of a bash script (not a long-running claude run), HIGH-1 didn't apply
- ADR-033 (Inngest cron functions invoke claude-code via child_process.spawn) — introduces the long-running-spawn consumer class
- Code: `apps/web-platform/server/github-app.ts:generateInstallationToken` (cache + minRemainingMs)
- Code: `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts:mintInstallationToken` (60-min floor)
