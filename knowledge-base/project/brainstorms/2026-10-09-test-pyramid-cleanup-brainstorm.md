---
date: 2026-10-09
issue: 9855
lane: cross-domain
brand_survival_threshold: single-user incident
status: captured
---

# Brainstorm: Test-Pyramid Marker Backfill + e2e Layer Cleanup (#9855 PR 1)

## What We're Building

Scope: **PR 1 of #9855 only** — test-file changes, no CI wiring.

1. Backfill `pyramid-justified:` markers on the e2e files that remain after demotions. Zero markers exist today (`git grep pyramid-justified apps/web-platform/e2e` → empty), so the next PR that adds a case to any of them FAILs the test-design-reviewer pyramid check — ambient failures on unrelated PRs.
2. Demote or delete three layer-inverted e2e files whose assertions need no browser.
3. Machinery critiques (named-dir precedence, `*.test.sh` ratchet, `hasTests` regex, `mu1-integration` spelling, unweighed e2e layer) route to #9771 as an issue comment — no machinery changes in this PR.

**Out of scope (PR 2 of #9855):** wiring the 7 dormant env-gated integration suites (`SUPABASE_DEV_INTEGRATION`, `WORKTREE_LEASE_INTEGRATION_TEST`, `ACQUIRE_SLOT_WS_INTEGRATION_TEST`, `BYOK_INTEGRATION_TEST`, `SLOT_TRIGGER_INTEGRATION_TEST`, `WORKSPACE_BINDING_INTEGRATION_TEST`, `MU1_INTEGRATION`) into CI — deferred; needs dev-Supabase secrets via Doppler and per-suite cost/flake decisions. Recorded as a follow-up on #9855.

## Verified Findings (census re-run, 2026-10-09, at origin/main 01d2b5a0d8)

- **11 e2e files** confirmed; **zero** `pyramid-justified` markers.
- `team-membership.e2e.ts`: 2 active `request.get`-only tests (flag-off 404; conversation-names reachability) + 6 empty `describe.skip` stubs. Flag-off 404 is unit-covered by `test/team-membership-resolver.test.ts` (`AC-A: returns not-found when feature flag is OFF`); conversation-names settings has `test/conversation-names-settings.test.tsx`.
- `smoke.e2e.ts`: **11 tests** — the issue's "2 of 3" characterization is stale (signal counts `request.*`=10/`page.*`≈6 are right). ~8–9 are `request.get` CSP-header/wiring assertions; the browser-needing residue is the nonce-matches-script-tag DOM check and the console-CSP-violations listener.
- `oauth.e2e.ts`: 6 tests — 2 request-only `/callback` 307-redirect tests + 4 page DOM-contract tests. `/callback` redirect logic is already covered at route-invocation level by `test/e2e-oauth-tc-consent.test.ts` ("E2E: OAuth → /accept-terms → RPC", `next`-param terminal-hop cases); DOM contracts by `test/oauth-buttons.test.tsx` (renders 4 providers, enabled/disabled states) and the consent suite.
- `test/csp.test.ts` covers `buildCspHeader` content exhaustively at unit level; what e2e uniquely covers is **middleware wiring** — header presence per route, nonce rotation across requests, `x-forwarded-host` connect-src handling.
- **No booted-server vitest harness exists** (`test/helpers/bundled-server.ts` is an esbuild-fixture harness, not Next). "Demote to integration layer" therefore means **route/middleware-invocation tests**, matching the established `e2e-oauth-tc-consent.test.ts` pattern — not a new harness.
- All 7 dormant env gates confirmed absent from `.github/` and `scripts/` (`TENANT_INTEGRATION_TEST` is the only wired one, in `tenant-integration.yml`).
- Issue states: #9762 CLOSED (machinery shipped), #9771 OPEN (owns machinery critiques).

## Why This Approach

The reviewer's classification table keys on path + framework signals: anything under `apps/web-platform/e2e/` importing `@playwright/test` is e2e regardless of browser use, and there is no vitest-side Next-server harness to "demote into". Building one would be machinery-shaped work that belongs to #9771. The repo's proven pattern for HTTP-contract tests without a browser is route/middleware invocation in vitest (`e2e-oauth-tc-consent.test.ts` invokes `GET /callback` directly with mocked deps). Demoting to invocation tests is a real layer drop — often to *unit*, which is better than the issue's "integration" target — at zero new-infrastructure cost.

Deletion beats demotion wherever unit coverage already exists: duplicated coverage at a lower layer is the pyramid goal, not relocated duplication.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | PR 1 only (markers + demotions); PR 2 deferred as a tracked follow-up | Operator-chosen; PR 2 needs Doppler secrets + cost/flake calls that deserve a separate pass |
| `team-membership.e2e.ts` | **Delete the file** | Both active tests are unit-covered (resolver AC-A; conversation-names component test); `describe.skip` block is dead spec text. Plan-time verify: confirm no assertion lacks a unit equivalent before deleting |
| `smoke.e2e.ts` | **Split**: ~8–9 `request.get` CSP-header/wiring assertions → new vitest `csp-middleware` (or similar) test invoking `middleware.ts` with mocked env; keep nonce-in-DOM + console-violations tests in e2e with a marker | Header *content* already unit-covered; the residual is middleware *wiring* (per-route presence, nonce rotation, x-forwarded-host) — invocable without a server |
| `oauth.e2e.ts` | **Delete the file** after assertion-by-assertion coverage check | `/callback` redirects covered by `e2e-oauth-tc-consent.test.ts`; DOM contracts by `oauth-buttons.test.tsx` + consent suite. Plan-time verify: any uncovered assertion is demoted, not dropped |
| Marker backfill | `pyramid-justified:` on every surviving e2e file, naming the browser need per file (e.g. `nav-states-*` intercept `page.route`; `cc-soleur-go-*` use ws-injector + `browser.newContext`) | Prevents 11 ambient pyramid FAILs on unrelated PRs |
| Demotion mechanics | Route/middleware-invocation vitest tests — **no new server-boot harness** | Established pattern (`e2e-oauth-tc-consent.test.ts`); a booted-server harness is #9771 machinery |
| Machinery critiques | Comment on #9771 enumerating the 5 findings | Issue boundary: machinery-shape changes route through #9771 unless trivial |
| PR 2 (CI wiring) | Follow-up comment on #9855; not this PR | Needs Doppler dev-Supabase secrets + per-PR-vs-scheduled + cost/flake decisions |

## Open Questions

- Does `middleware.ts` invoke cleanly in vitest offline, or does it need a mocked Supabase client/env shim? (resolve at plan time; e2e public server already runs with a fake unreachable Supabase URL, suggesting middleware tolerates it)
- Does any `smoke.e2e.ts` request-only assertion exercise behavior unreachable via middleware invocation (e.g. response headers set outside middleware, on `/health`)? → verify at plan time; demote only what the invocation path actually exercises.
- `conversation-names` reachability: acceptable to drop, or keep a one-line route-invocation test? (plan-time verify)
- Machinery critique fixes that are "small enough to fix inline" (e.g. `mu1-integration.test.ts` naming) — fix here or defer entirely to #9771? (plan-time call; default defer unless truly trivial)

## User-Brand Impact

- **Artifact:** the e2e test layer of `apps/web-platform` (marker backfill + demotions)
- **Vector:** worst case is deleted e2e coverage masking a real regression (e.g. CSP header silently dropped from a route, `/callback` redirect broken) reaching a user — mitigated by the plan-time assertion-by-assertion coverage check before any deletion.
- **Threshold:** `single-user incident`

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

*Note: leader fan-out ran inline (Devin harness exposes only generic subagent profiles; triad prompts assessed by the orchestrator against the verified census).*

### Product (CPO — mandatory triad)

**Summary:** No user-facing surface — test files and CI only. User-brand exposure is indirect: coverage loss masking a regression. The assertion-coverage check before deletion is the brand-survival control.

### Legal (CLO — mandatory triad)

**Summary:** No legal/compliance surface. No PII, auth-flow, or regulated-data changes — `soleur:gdpr-gate` not triggered by scope (canonical regex matches nothing in `e2e/*.e2e.ts` test edits; re-check if PR 2 later wires auth suites).

### Engineering (CTO — mandatory triad)

**Summary:** PR 1 is mechanical: markers, file splits, deletions gated on coverage checks. The one architectural subtlety is that "demote to integration" resolves to middleware/route-invocation tests (unit/integration layer), not a new booted-server harness — that harness is correctly deferred to #9771 machinery. PR 2 (deferred) is where the real decisions live: secrets provisioning, per-PR vs scheduled cadence, flake budget on real dev-project writes.
