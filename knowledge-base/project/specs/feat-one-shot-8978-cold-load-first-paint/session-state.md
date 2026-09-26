# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8978-cold-load-first-paint/knowledge-base/project/plans/2026-09-26-perf-dashboard-cold-load-first-paint-plan.md
- Status: complete

### Errors
- `gh issue create` for the deferral tracker was denied twice by `guardrails.sh` (body needed bare-digit `Fix-Size:`); third attempt succeeded → issue #8985 filed under milestone "Phase 4: Validate + Scale".
- No Task/subagent tool on this harness: plan + deepen-plan fan-outs ran sequential-fallback/inline; all halt gates evaluated and passed inline.
- No push performed (lead owns the branch).

### Decisions
- Diagnose-first: Phase 0 ships instrumentation before fixes — fold in #8969 (`sec-fetch-mode: navigate` document classification), extend `mw-*` Server-Timing to authenticated `/api/*`, header-scoped `tracesSampler` (`x-perf-probe: 1`), authenticated Playwright probe `scripts/live-verify/perf-probe.ts`.
- Warm-path fix via existing mechanisms: migrate 4 unmigrated dashboard-mount routes to `verifiedUserId()` (scoped slice of #8926); `resolveIdentity` header+JWT-decode fast path via `decodeJwtPayloadUnsafe`; ADR-253 absent⇒re-verify contract unchanged.
- Positive-only auth-verdict `LRUCache` (token-hash keyed, 30s TTL) adopted only if Phase-0 shows `mw-auth` dominating; either arm requires an ADR-253 amendment in the same PR.
- Server-side only: no `app/**`/`components/**` edits; client mount-fan-out batching deferred to #8985.
- AC risk flagged honestly: measured warm doc TTFB ~0.65s already exceeds 500ms FCP AC — persisted as User-Challenge in `decision-challenges.md`; `brand_survival_threshold: single-user incident` carried from parent plan.

### Components Invoked
- `soleur:plan` (in-process): premise validation, skeleton checkpoint, property/cut lists, sharp-edges pass, inline domain review, open-code-review-overlap check, tasks.md + decision-challenges.md, 2 commits.
- `soleur:deepen-plan` (in-process): halt gates 4.5–4.11 (4.5 network-outage fired; telemetry + `## Hypotheses` added); Enhancement Summary + Files to Edit/Create.
- `gh`, `git` (read-only + artifact commits `6a7aa4cf91`, `a87e1b6ca5`), `curl` live probes, `lint-guard-contract.py`, `markdownlint-cli2`.

## Work Phase (in progress, 2026-09-26)

### Implemented (uncommitted, pending lefthook gate)
- P0.1+P0.2 `middleware.ts`: SW-proxied navigations now classify as documents via `sec-fetch-mode: navigate` (request.mode belt for runtimes that expose it); authenticated `/api/*` responses emit `mw-*` Server-Timing; `no-store` stays document-only. Tests: SW-shaped cases in `middleware.test.ts` + `middleware.no-store.test.ts`. STAGED, commit blocked by in-flight `test-all.sh --affected` (lefthook).
- P0.3 `sentry.server.config.ts`: `tracesSampleRate: 0` → `tracesSampler` (probe header `x-perf-probe: 1` → 1.0, else 0.02); added `beforeSendTransaction` → `scrubSentryEvent`. Test: `test/sentry-server-config-traces-sampler.test.ts` (18 tests green).
- P0.4 `scripts/live-verify/perf-probe.ts` + `test/live-verify/perf-probe.test.ts` (10 tests green). Exports added to `run.ts`: `readConfig`, `makeJar`/`Jar`, `mintSession`. Fix during live run: zeroed `request.timing()` fields → `-1` sentinel.
- P0.5 measurement done: 5 cold + 1 warm sample posted to #8978 (comment 5848827026). Doc TTFB p50 ≈5.4s / p95 ≈13.7s cold; warm-sw 0.77s. **mw-auth NOT dominant** (0.13–4.38s vs render-path residual up to ~12.7s).
- P1.6: 4 routes migrated to `verifiedUserId()`; `pending-invites` reads email from local session JWT (remote getUser fallback when absent); `resolveOrgMemberships` signature `(service, userId)` — internal getUser RTT removed, sole caller + test updated.
- P1.7: `resolveIdentity` fast path — minted header + local JWT `sub`/`email` decode; any gap → remote getUser. 6 new tests; concurrency test's getUser assertion moved to `vi.waitFor` (headers() await shifts call to next microtask).
- P1.8: auth-verdict LRUCache **REJECTED** by measurement → not implemented.
- ADR-253 amendment written (rejection arm + render-path header consumption + Server-Timing widening + SW classification).

### Pending
- First commit still blocked: `test-all.sh --affected` PID 3163555 running ~1.5h under repo-global flock (iterating suites; sibling run finished first).
- Remaining: commit batch (sentry/routes/identity/probe/ADR/tasks), gdpr-gate on cumulative diff, Phase-2 focused checks, push, soleur:review, soleur:qa, soleur:compound, soleur:ship → merge + post-merge probe re-run.
- Draft PR #8984 exists for this branch.
