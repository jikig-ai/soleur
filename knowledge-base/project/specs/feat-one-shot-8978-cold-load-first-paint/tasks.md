# Tasks — perf(dashboard): cold load misses ≲500ms first-paint AC

Plan: `knowledge-base/project/plans/2026-09-26-perf-dashboard-cold-load-first-paint-plan.md`
Closes: #8978, #8969

Spec lacks valid lane: — no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Phase 0 — Instrument the cold path

- [ ] 0.1 `apps/web-platform/middleware.ts`: classify document-ness on `sec-fetch-mode: navigate` OR `request.mode === "navigate"` in addition to the `sec-fetch-dest`/`NON_DOCUMENT_DESTS` check — restores `Server-Timing` + `no-store` on SW-proxied navigations (closes #8969). Extend `test/middleware.test.ts` + `test/middleware.no-store.test.ts` with the SW-shaped request case (`sec-fetch-dest: empty`, `sec-fetch-mode: navigate`).
- [ ] 0.2 `middleware.ts`: move the `Server-Timing` header set out of the document-only gate so authenticated `/api/*` responses carry `mw-auth`/`mw-revoke`/`mw-tc`; keep the `Cache-Control: no-store` set document-only.
- [ ] 0.3 `apps/web-platform/sentry.server.config.ts`: replace `tracesSampleRate: 0` with `tracesSampler` — 1.0 when the request carries `x-perf-probe: 1`, ~0.02 floor otherwise. Verify `server/sentry-scrub.ts` transaction-envelope handling; add a test asserting scrub compatibility (#3829 interaction).
- [ ] 0.4 Create `apps/web-platform/scripts/live-verify/perf-probe.ts` (bun + bundled `@playwright/test` chromium, `live-verify@soleur.ai` principal, `run.ts` allowlist/teardown invariants): captures FCP/LCP paint entries, navigation TTFB, per-request `Server-Timing` headers, `/api/*` waterfall; emits redacted JSON; sets `x-perf-probe: 1` on every request; runs cold (no SW) + warm (SW-controlled) passes.
- [ ] 0.5 Run the probe cold + warm; post the committed measurement table to #8978 and embed in the PR body (DoD item 1: which tier dominates the 8–15s cold `/api/*` window).

## Phase 1 — Remove known fixed tax

- [ ] 1.1 Migrate `app/api/workspace/list-memberships/route.ts`, `app/api/workspace/pending-invites/route.ts`, `app/api/byok/effective-status/route.ts`, `app/api/vision/route.ts` from `auth.getUser()` to `verifiedUserId(req)` (401 on null; preserve all data-query clients). Update their route tests.
- [ ] 1.2 `lib/feature-flags/identity.ts`: `resolveIdentity` reads `x-soleur-auth-user-id` via `headers()` and decodes `email`/`sub` from the session JWT (`getSession()` local read — the middleware's own decode pattern); absent header or missing claims → remote `getUser()` fallback, unchanged semantics. Update `test/` identity suites for both arms.
- [ ] 1.3 Conditional (Phase-0-gated): if `mw-auth` dominates cold `/api/*`, add the positive-only auth-verdict `LRUCache` keyed on access-token hash (`MW_VERDICT_TTL_MS = 30_000`, only `user != null` stored) AND amend ADR-253 in the same commit. If rejected by measurement, record rejection + numbers in the PR body; this task is then N/A.
- [ ] 1.4 Amend `knowledge-base/engineering/architecture/decisions/ADR-253-*.md` — either arm (verdict-cache adoption records the ≤30s auth-staleness bound; rejection arm records the render-path header-consumption extension). Same PR, not a follow-up.

## Phase 2 — Verify

- [ ] 2.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green; `node node_modules/vitest/vitest.mjs run` green for touched suites (middleware*, request-auth, identity, sentry-scrub, perf-probe).
- [ ] 2.2 Post-merge: re-run perf probe against deployed build; attach FCP/TTFB/per-API table to #8978; verify warm FCP ≲500ms or attach measured floor + residual filing.
- [ ] 2.3 Record the cold-path bound (p50/p95 over ≥5 cold samples) in the closing comment on #8978.
