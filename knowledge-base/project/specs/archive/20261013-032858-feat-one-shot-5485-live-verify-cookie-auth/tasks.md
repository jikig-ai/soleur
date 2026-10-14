---
feature: fix-live-verify-cookie-auth
issue: 5485
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-17-fix-live-verify-cookie-auth-plan.md
---

# Tasks — fix(live-verify): injected session cookie must authenticate against prod

Derived from the deepened plan. The live MCP-browser repro (Phase 1) is the
binding gate — do NOT change `run.ts` before the divergence is pinned.

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Read before editing: `apps/web-platform/scripts/live-verify/run.ts`,
  `middleware.ts`, `lib/supabase/server.ts`, `app/(auth)/callback/route.ts`,
  `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts`,
  `apps/web-platform/e2e/global-setup.ts`,
  `apps/web-platform/scripts/live-verify/redact.ts`,
  `apps/web-platform/test/live-verify/gate.test.ts`.
- [ ] 0.2 Confirm `apps/web-platform/vitest.config.ts` include globs collect
  `test/live-verify/*.test.ts` (`test/**/*.test.ts`).
- [ ] 0.3 Confirm the prod synthetic principal is bootstrapped (Doppler `prd`
  has `LIVE_VERIFY_*` + `LIVE_VERIFY_USER_PASSWORD`). If not, the Phase-1 repro is
  blocked — escalate, do not skip.

## Phase 1 — LIVE MCP REPRO (pin the divergence; NO code change)

- [ ] 1.1 Via the Playwright **MCP** browser, perform a genuine
  `live-verify@soleur.ai` login on `https://app.soleur.ai` (password read from
  Doppler `prd` at the keyboard — never echoed).
- [ ] 1.2 Capture the real session cookies with `browser_context.cookies()`:
  record name(s), `domain`, `httpOnly`, `secure`, `sameSite`, `path`, and the
  value PREFIX shape (`base64-` or raw) — names/flags/prefix only, never values.
- [ ] 1.3 Capture the harness mint output: temporarily log `jar.cookies.size` +
  key set (names only) after `mintSession`, OR run `--dry-run` with names-only
  diagnostic. Confirm the jar is populated (deepen says it is). Remove temp
  logging before commit.
- [ ] 1.4 Diff real vs harness attribute-by-attribute; write the pinned
  divergence into the PR body (AC1). Expected: a mis-shaped attribute (`httpOnly`)
  — empty-jar / name / encoding already ruled out by deepen research.

## Phase 2 — Fix `run.ts` (TDD)

- [ ] 2.1 (RED) Write the failing unit test first
  (`cq-write-failing-tests-before`): assert `buildInjectedCookies` output shape
  for a synthesized (non-secret) session fixture — name `sb-api-auth-token`
  (chunked names if applicable), `domain` = app host (not supabase host), and the
  attribute set the live repro pinned. Fixture fabricated
  (`cq-test-fixtures-synthesized-only`).
- [ ] 2.2 (GREEN) Extract a pure `buildInjectedCookies(...)` helper from `run.ts`
  (exported, like `bindProject`/`verifyPrincipal`) and fix the injection shape:
  carry SSR per-cookie `options` through OR set the pinned attributes (most
  likely `httpOnly: false`; keep `secure: true`, `sameSite: "Lax"`,
  `domain: prodHost`). Re-inject every chunk 1:1.
- [ ] 2.3 Preserve `error.name`-only + `redact()` discipline at every log site
  (AC4). `grep -nE 'console\.(log|error|warn)' scripts/live-verify/run.ts` — every
  site emits structural metadata or routes through `redact()`.

## Phase 3 — Unit test landing (AC5)

- [ ] 3.1 Place the test at `apps/web-platform/test/live-verify/cookie-injection.test.ts`
  (matches vitest `test/**/*.test.ts`; never co-located beside `run.ts`).

## Phase 4 — Verify

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC6).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-verify/` (AC7).
- [ ] 4.3 Live MCP-browser: inject harness cookies, navigate `/dashboard`,
  assert conversations rail present (`[data-testid="conversations-rail"]`), URL is
  NOT `/login` (AC3). Record final URL + assertion in PR body.

## Post-merge (operator) — feeds #5463

- [ ] 5.1 After the next real realtime/WS/auth/DOM-timing PR merges, confirm the
  report-only gate emitted a correct `RESULT: PASS` (or a real `FAIL`), not a
  cookie-auth `CANT-RUN`/`/login` artifact. Record on #5463 as the
  `wg-dark-launch-deploy-gates` "observed passing on ≥1 real deploy" evidence.
  Automation: not feasible in-PR (requires a real qualifying deploy + the
  pre-existing prod bootstrap owned by #5452).
