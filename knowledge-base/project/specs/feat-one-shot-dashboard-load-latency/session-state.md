# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-25-perf-dashboard-section-load-latency-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- `gh pr view --json merged` — invalid field name; recovered using `mergedAt` (PR #5537 confirmed MERGED 2026-06-18).
- No dedicated Skill/Task tool exists in this runtime — `soleur:plan` and `soleur:deepen-plan` were executed inline from their SKILL.md definitions; all halt gates checked mechanically; `lint-guard-contract.py` + `markdownlint-cli2` green.
- Scope note: deepen-plan Phase 4.9 hard-halts UI-surface plans without a committed `.pen` wireframe — `knowledge-base/product/design/dashboard/dashboard-load-states.pen` authored and committed as a planning deliverable.
- Large-read truncations worked around with targeted reads; no secrets exposed.

### Decisions
- Positive-only TTL verdict caches (30s, in-process LRUCache) for revocation RPC and T&C/billing users select — deny/redirect verdicts never cached; bounded-staleness trade-off in provisional ADR-253.
- `x-soleur-auth-user-id` middleware-verified identity header consumed by new `server/request-auth.ts` helper with getUser() fallback — removes duplicated auth RTT in withUserRateLimit + 3 dashboard-hot routes.
- Cache key on JWT sub+iat (locally decoded) rather than user.id; header ordering proven against next@16.3.6.
- Dashboard ungating + server-rendered chrome: closes #5531, #5532, #5533, #5654; #3931, #5644, #5535 deferred open.
- `auth.getClaims()` rejected (HS256 project — no JWKS); deferred as substrate follow-up.

### Components Invoked
- soleur:plan (inline, all phases), soleur:deepen-plan (inline, two rounds), scripts/lint-guard-contract.py, markdownlint-cli2, gh issue/PR verification, curl production probes.
