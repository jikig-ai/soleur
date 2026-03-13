# Learning: External API integration scope calibration

## Problem

When adding X/Twitter support to the community agent (#127), the brainstorm assumed X API Free tier provides unlimited reads. Reality: X migrated to pay-per-use credits; Free tier is extremely limited (1 req/24h on most endpoints). This cascaded into three scope problems:

1. **Stale API tier assumption** -- brainstorm treated model knowledge as fact for API pricing
2. **Spec self-contradiction** -- TR2 said "curl + jq only" but OAuth 1.0a needs `openssl`
3. **Plan overscoped 3x** -- adapter refactor, engage sub-command, rate limit counter were all YAGNI

The plan was cut from ~42 tasks to ~19 after review.

## Solution

### 1. Verify API capabilities before spec

Fetch live API documentation (WebFetch or official docs site) before writing spec requirements. Model training data is stale for API pricing and tier capabilities.

### 2. Cross-check dependency constraints

When a spec TR constrains tools ("curl + jq only"), verify all FRs are achievable within those constraints. OAuth 1.0a requires `openssl` -- the TR was updated to "curl + jq + openssl."

### 3. Apply scope ratio heuristic

If a plan introduces >3 new files or >2 new sub-commands for "add X support to existing Y," flag as potentially overscoped. Ask: "Does the first user need this on day one?"

### 4. File deferred issues, don't comment

Cut items become GitHub issues (#469-#472), not TODO comments. An issue has an owner and lifecycle; a comment rots.

### 5. Budget agent descriptions

After updating agent descriptions, run `grep -h 'description:' agents/**/*.md | wc -w`. Must stay under 2500 words. Descriptions are loaded every turn -- keep them routing-only (1-3 sentences).

## Key Insight

API pricing changes faster than model training. The brainstorm → spec → plan pipeline amplifies stale assumptions: one wrong assumption ("Free tier has unlimited reads") cascaded into 20+ unnecessary tasks. The fix is a single verification gate before spec finalization, not more process.

## Session Errors

1. X API Free tier assumption wrong -- brainstorm treated as fact without verification
2. Spec TR2 contradiction -- "curl + jq only" vs. openssl requirement
3. Plan overscoped ~3x -- adapter refactor, engage, rate limit counter all YAGNI
4. Agent description token budget exceeded 2500 words, required two rounds of trimming
5. Spec directory not found in worktree -- `mkdir -p` needed before write

## Related

- `2026-02-06-parallel-plan-review-catches-overengineering.md` -- same scope reduction pattern
- `2026-02-18-token-env-var-not-cli-arg.md` -- secrets via env vars pattern (applied in x-setup.sh)
- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` -- `${N:-}` guards (applied in dispatch functions)
- `performance-issues/2026-02-20-agent-description-token-budget-optimization.md` -- budget enforcement
- Issues filed: #469 (engage), #470 (adapter refactor), #471 (X monitoring), #472 (discord 429 bug)

## Tags

category: implementation-patterns
module: plugins/soleur/skills/community
