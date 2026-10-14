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

## Work Phase
- Status: implementation complete; pre-commit battery in progress (run 3 — prior runs queued ~40min behind sibling session batteries and failed on 5 test-layer findings, all fixed inline)
- Execution: Tier-0 lifecycle parallelism — code agent + test agent from interface-contract.md; ux-design-lead implementation brief consumed for Phase 4/6 render semantics
- Tier-0 artifacts: interface-contract.md committed (35e728ea99); ADR-253 authored (ADR-0253→ADR-253 ordinal-naming fix applied after plugins/soleur check-adr-ordinals failure)

### Implementation deltas vs plan
- lib/feature-flags/server.ts also edited (contract gap — Identity/ANON_IDENTITY live there, not identity.ts)
- Foundation shimmer condition = `foundationData === undefined && !foundationErr && conversations.length > 0` (`!foundationErr` added — error must not pin shimmer)
- command-center-empty branch gains `!loading` (ux brief recommendation — "No conversations yet" must not flash while list in flight)
- isAdmin guarded on non-null userId (closes ADMIN_USER_IDS="" anonymous-match edge)
- page.tsx orphan-count SWR fetcher getUser→getSession (same Phase-5 defect class, plan-silent)
- VerifiedUser named type exported from request-auth.ts; 10 consumer signatures + 2 shared handler factories narrowed
- Identity literals across 9 server/route files + test fixtures gained explicit `email: null, subscriptionStatus: null` (type widening fallout — plan claimed "existing consumers unaffected" which held only for readers, not constructors)

### Battery-run fixes (pre-commit red)
- matcher-coverage.test.ts: `**/` inside a /* */ JSDoc comment self-terminated the block (regex/template cascade) — rewrote as // lines
- ADR-0253 → ADR-253 (ordinal convention is unpadded)
- update-status.test.tsx: added getSession mock + SwrTestProvider wrap (missed by repair pass)
- sentry-scope-isolation.test.ts + with-user-rate-limit.test.ts + request-auth.test.ts: addBreadcrumb added to @sentry/nextjs mocks
- billing-enforcement.test.ts AC5: distinct user id — positive-only tcRowCache legitimately serves warm pass through DB blip (cold-path contract is what AC5 pins)
- conversations-rail-insert.test.tsx: unused `url` arg → `_url` (+1 over no-unused-vars baseline)
- eslint-config ratchet: count now 74 ≤ baseline 74 (verified via full eslint -f json)

## Review Phase
- Mode: sequential-fallback (10 seats spawned as background subagents on the pushed branch; semgrep ran inline: 79 rules, 0 findings)
- Seats: code-simplicity, architecture-strategist, performance-oracle (design-validity pass, design-risk set), security-sentinel, pattern-recognition, data-integrity-guardian, test-design (B 8.75/10), code-quality (8.5/10), user-impact, agent-native, structural-enumeration
- Merge-tree vs origin/main: clean; branch pushed before panel (rf-before-spawning-review-agents-push-the)

### Findings → dispositions
- P1 (4-seat convergence): LRUCache sliding TTL voided ≤30s verdict bound → FIXED (absolute expiry; tcRowCache.set gated !tcRowHit; _roleCache noted as absolute too); lru-cache.test pins write-anchored expiry through hits
- P2: matcher extension-suffix bypass on dynamic-terminal routes (unpaid-write/revocation/T&C skip live today) → FIXED (single-segment + icons/ carve-out); Guard-1 extended (app/ walk, group-strip, .png probes, floor 100)
- P2: foundation non-503 error had no surface + no mirror → Sentry mirror added; past_due banner SSR dismissed-flash → mount-gated; realtime repo-less workspace-visibility insert divergence → shouldDropForScope drops on repoUrl null
- P3 batch fixed: /health pre-strip return, empty revokeData→grace, rpc sync-throw containment, dead deps/fields/comments, use-onboarding .catch arms, no-store iatSeq flake vector, request-auth breadcrumb assertions, CSP-invariant detector update
- Deferred: filter-change double-refetch+resubscribe (pre-existing shape → noted), ~70 unmigrated getUser() sites (#8926), isAdmin derivation dedup, flagIdentity factory, isAdmin page .png CSP residual (pages, not handlers)

## Compound Phase
- Learning: knowledge-base/project/learnings/2026-09-26-the-shared-primitive-not-the-call-site-was-the-bug.md
- Recurring triage: battery log loss → filed #8940 (meta/machinery); sliding-TTL + matcher bypass + Guard-1 scope → fixed inline; PromiseLike/JSDoc/ADR-pad/test-shape items → recorded in learning's Session Errors
- Deviation analyst: no hard-rule violations detected; hook-incident log not present in this environment
