---
title: "chore: app-url hardening PR-A (Sentry-mirror silent fallbacks + consolidate NEXT_PUBLIC_APP_URL)"
type: chore
date: 2026-04-22
bundle: feat-app-url-hardening
closes: [2770, 2768]
related: [2769, 2773, 2774]
pr: 2793
---

# chore: app-url hardening PR-A

Bundles `#2770` (Sentry-mirror silent `??` URL fallbacks) and `#2768` (consolidate `NEXT_PUBLIC_APP_URL` / `NEXT_PUBLIC_SITE_URL`) into one PR. `#2769` (CI guard) ships as PR-B. `#2773` / `#2774` close out of band with a Sentry passive-signal comment.

## Overview

Two coupled cleanups from PR #2767:

1. **Silent-fallback mirroring.** Plan-time grep found **three** silent-fallback sites (issue #2770 names two). All three get `reportSilentFallback` mirroring per `cq-silent-fallback-must-mirror-to-sentry`.
2. **Env var consolidation.** Migrate the two `NEXT_PUBLIC_SITE_URL` consumers in `github-resolve/*.ts` to `NEXT_PUBLIC_APP_URL`; delete the duplicate secret from Doppler `prd` post-merge via explicit per-command ack (`hr-menu-option-ack-not-prod-write-auth`).

Pattern reference: the existing `reportSilentFallback` call in `apps/web-platform/server/agent-runner.ts` (around line 682, `feature: "kb-share"`, `op: "baseUrl"`).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (2026-04-22, verified) | Plan response |
|---|---|---|
| `checkout/route.ts:33` has the fallback | Actually at line **61** | Symbol anchor, not line number |
| `billing/portal/route.ts:29` has the fallback | Confirmed line 29 | OK |
| `agent-runner.ts:675` reference | Actually line **682** | Mirror the runtime call shape, not the line |
| "Two API routes fall back silently" (#2770) | **Three** sites fall back silently — `checkout`, `billing/portal`, `server/notifications.ts` (the third uses `\|\|`, same literal, no Sentry mirror) | **Fold `notifications.ts` into PR-A** — same rule violation, same literal, trivial cost |
| `NEXT_PUBLIC_SITE_URL` has two consumers | Confirmed: `github-resolve/route.ts:15`, `github-resolve/callback/route.ts:163`. No other prod consumers. | Post-migration sweep: `rg NEXT_PUBLIC_SITE_URL apps/ server/ lib/` → zero hits |
| Tests will need creating | **All four test files already exist** (`test/api-checkout.test.ts`, `test/api-billing-portal.test.ts`, `test/notifications.test.ts`, `test/github-resolve.test.ts`); reference `observability.test.ts` from PR #2487 | Edit existing files, create zero new ones |
| `@sentry/nextjs` mocked in route tests | **Not mocked** in any of the four files | First RED-phase task per file is the Sentry mock setup |

## Scope Decisions

### Folded in beyond issue #2770

- **`apps/web-platform/server/notifications.ts`** — `|| "https://app.soleur.ai"` silent fallback. Plan-time grep found 3 sites when issue named 2; the sharp-edge advice is to widen to match the grep, not trust the enumerated list. Rule violation is identical (`cq-silent-fallback-must-mirror-to-sentry`).

### Explicitly out of PR-A

- `middleware.ts` `NEXT_PUBLIC_SUPABASE_URL ?? ""` — different feature; empty-string fail is loud, not silent.
- `server/github-app.ts` / `connect-repo/page.tsx` `NEXT_PUBLIC_GITHUB_APP_SLUG ?? "soleur-ai"` — fallback literal is the correct prod slug; config sanity-check, not a silent degradation.
- `#2769` CI guard — separate PR-B.
- `#2773`/`#2774` follow-throughs — close out-of-band with Sentry passive-signal comment (see `knowledge-base/project/learnings/best-practices/2026-04-22-passive-sentry-signal-closes-followthrough-verification.md`).

## Implementation Phases

### Phase 1 — TDD RED (tests before implementation, per `cq-write-failing-tests-before`)

**Sentry mock factory shape (apply to all four test files):**

```ts
vi.mock("@sentry/nextjs", async (orig) => ({
  ...(await orig<object>()),
  captureException: vi.fn(),
  captureMessage: vi.fn(),
}));
```

Partial mock via `...(await orig())` preserves `init` / `withSentryConfig` at import time — a full replacement risks breaking the observability module's own import graph (Kieran plan-review finding).

- [ ] 1.1 `test/api-checkout.test.ts`
  - [ ] 1.1.1 Add the Sentry partial-mock above. Hoist captured mocks via `vi.hoisted` if the test file's existing mocks use that pattern.
  - [ ] 1.1.2 **Degraded path (new RED):** `given NEXT_PUBLIC_APP_URL unset, when POST /api/checkout runs, then captureException/captureMessage fires with tags { feature: "checkout", op: "create-session" }` AND `then stripe.checkout.sessions.create was called with success_url matching /^https:\/\/app\.soleur\.ai\// (the fallback literal)`.
  - [ ] 1.1.3 **Happy path (anti-tautology per `cq-mutation-assertions-pin-exact-post-state`):** `given NEXT_PUBLIC_APP_URL = "https://test.example", when POST /api/checkout runs, then captureException/captureMessage NOT called AND stripe.checkout.sessions.create.success_url starts with "https://test.example/"`. The positive URL assertion is load-bearing — a silent mutation that forgets to use env would otherwise pass the "not called" assertion.
- [ ] 1.2 `test/api-billing-portal.test.ts` — symmetrical to 1.1: `feature: "billing"`, `op: "portal-session"`. Happy path asserts `billingPortal.sessions.create.return_url` uses env value.
- [ ] 1.3 `test/notifications.test.ts`
  - [ ] 1.3.1 Add Sentry partial-mock.
  - [ ] 1.3.2 Read `server/notifications.ts` to determine the callsite's operation name. Name the op after the function containing the fallback (e.g., `op: "origin"` or `op: "webpush-base"` depending on the site). Decide at implementation-start by reading the file, not at plan time.
  - [ ] 1.3.3 Degraded-path + happy-path pair, same anti-tautology shape as 1.1.2 / 1.1.3.
- [ ] 1.4 `test/github-resolve.test.ts`
  - [ ] 1.4.1 Every `describe`/`it` block must `beforeEach` clear `process.env.NEXT_PUBLIC_SITE_URL` (`delete process.env.NEXT_PUBLIC_SITE_URL`). Without this guard, a shell-leaked value would silently satisfy the legacy code path and hide the migration's RED state.
  - [ ] 1.4.2 Switch every test that previously stubbed `NEXT_PUBLIC_SITE_URL` to stub `NEXT_PUBLIC_APP_URL` instead. These tests fail against current `main` until Phase 2 migration lands.
- [ ] 1.5 From `apps/web-platform/`: `./node_modules/.bin/vitest run test/api-checkout.test.ts test/api-billing-portal.test.ts test/notifications.test.ts test/github-resolve.test.ts` — confirm every new/updated assertion **fails**. Per `cq-in-worktrees-run-vitest-via-node-node`, never `npx vitest run`.

### Phase 2 — TDD GREEN (minimal implementation)

Open `apps/web-platform/server/agent-runner.ts` once for reference (the `reportSilentFallback` call near the `kb-share baseUrl` guard). Mirror that call shape.

- [ ] 2.1 `app/api/checkout/route.ts` — rewrite the `appOrigin` line as `if (!appUrl) reportSilentFallback(null, { feature: "checkout", op: "create-session", message: "NEXT_PUBLIC_APP_URL unset; checkout origin fallback to https://app.soleur.ai" })` followed by `const appOrigin = appUrl ?? "https://app.soleur.ai"`. Keep the call inline inside the handler (`cq-nextjs-route-files-http-only-exports`).
- [ ] 2.2 `app/api/billing/portal/route.ts` — same pattern, `feature: "billing"`, `op: "portal-session"`.
- [ ] 2.3 `server/notifications.ts` — same pattern using the op name decided in 1.3.2. **Rewrite the `||` to `??`** — `||` also falls back on `""` and `0`, but for a URL env var, `""` is semantically identical to unset; the stricter `??` matches the other two sites and keeps the class consistent.
- [ ] 2.4 `app/api/auth/github-resolve/route.ts` — rename local `siteUrl` → `appUrl`; read `process.env.NEXT_PUBLIC_APP_URL`. Preserve the fallback literal.
- [ ] 2.5 `app/api/auth/github-resolve/callback/route.ts` — same migration inside `redirectWithDeletedCookie`.
- [ ] 2.6 Re-run the Phase 1.5 vitest command — all assertions green.

### Phase 3 — Typecheck, build, completeness sweeps

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/next build` — catches route-file export constraints `tsc` misses (`cq-nextjs-route-files-http-only-exports`).
- [ ] 3.3 **SITE_URL sweep:** `rg NEXT_PUBLIC_SITE_URL apps/ server/ lib/` → zero hits in production code. Test-fixture hits asserting absence are OK.
- [ ] 3.4 **Brute-force completeness sweep (Kieran finding):** `rg '"https://app\.soleur\.ai"' apps/ server/ lib/` → expect only five hits, each in one of the five files touched by this PR. This is the deterministic proof that no silent-fallback site was missed (covers single-quoted, backtick-quoted, destructured-default, and variable-indirection patterns that a narrower regex would miss).
- [ ] 3.5 **Enumerated read-check:** For any remaining `rg 'process\.env\.NEXT_PUBLIC_APP_URL' apps/ server/ lib/` hit that reads the env var, open the file and verify a `reportSilentFallback` sits in the enclosing `if (!...)` branch, or the read is guaranteed-set (e.g., middleware with a hard failure). Regex cannot assert "same function/same block" — this is the manual final pass.
- [ ] 3.6 Full `apps/web-platform` test suite: `./node_modules/.bin/vitest run` — zero regressions.

### Phase 4 — Ship

- [ ] 4.1 Run `/soleur:ship`. It handles: markdownlint-fix on changed files, commit, push, QA, multi-agent review, resolve findings inline, mark ready, `gh pr merge --squash --auto`, poll until MERGED, verify release workflow succeeds.
- [ ] 4.2 Pre-ship, ensure PR #2793 body contains:
  - `Closes #2770` and `Closes #2768` on separate lines (not in title, per `wg-use-closes-n-in-pr-body-not-title-to`)
  - `## Changelog` section per plugin AGENTS.md
  - Note that `#2769` ships as PR-B and `#2773`/`#2774` close out-of-band
- [ ] 4.3 Pre-ship, set labels: `semver:patch` + `type/security` (inherit from #2770's labels; surfaces security-scan runners).

### Phase 5 — Post-merge: Doppler `prd` delete + follow-through closure

**Destructive prod write — per `hr-menu-option-ack-not-prod-write-auth`, show the exact command verbatim and wait for explicit per-command go-ahead. Never pass `--force`/`--yes`.**

- [ ] 5.1 Confirm Web Platform Release run for PR-A's merge commit finished green end-to-end (deploy-webhook verify, not just build).
- [ ] 5.2 **Deterministic "new code running" check:** SSH to prod host and run `docker inspect soleur-web-platform | jq -r '.[0].Config.Labels["org.opencontainers.image.revision"]'` — the commit SHA must match PR-A's merge commit. Then `docker exec soleur-web-platform printenv NEXT_PUBLIC_APP_URL` — expect `https://app.soleur.ai`. This is read-only diagnosis, allowed per `cq-for-production-debugging-use`.
- [ ] 5.3 Present delete command for explicit per-command ack:

  ```text
  doppler secrets delete NEXT_PUBLIC_SITE_URL --project soleur --config prd
  ```

  Wait for operator go-ahead. Menu-option / plan-accept is NOT authorization. After ack, run the command — the Doppler CLI's native interactive confirmation will surface.
- [ ] 5.4 Verify deletion: `doppler secrets get NEXT_PUBLIC_SITE_URL -p soleur -c prd --plain --silent` exits non-zero. The deletion is inert for the currently-running container (prod code no longer reads `NEXT_PUBLIC_SITE_URL` — verified by 3.3); no forced redeploy needed.
- [ ] 5.5 Close `#2773` with a comment citing the Sentry passive-signal evidence from the brainstorm (`count`=1, `firstSeen`==`lastSeen`=`2026-04-22T07:44:03Z`, queried ≥8h post-deploy, zero new events). Link to learning `best-practices/2026-04-22-passive-sentry-signal-closes-followthrough-verification.md`. Close `#2774` with a one-line comment: "Redundant per issue body — #2773 confirmed Sentry silence and Phase 5.2 confirmed `NEXT_PUBLIC_APP_URL` in prod container env."

## Files to Edit

**Production code (5):**

- `apps/web-platform/app/api/checkout/route.ts`
- `apps/web-platform/app/api/billing/portal/route.ts`
- `apps/web-platform/server/notifications.ts` (fold-in)
- `apps/web-platform/app/api/auth/github-resolve/route.ts`
- `apps/web-platform/app/api/auth/github-resolve/callback/route.ts`

**Tests (4):**

- `apps/web-platform/test/api-checkout.test.ts`
- `apps/web-platform/test/api-billing-portal.test.ts`
- `apps/web-platform/test/notifications.test.ts`
- `apps/web-platform/test/github-resolve.test.ts`

## Files to Create

None. All test files already exist.

## Open Code-Review Overlap

**None.** Query against 27 open `code-review` issues returned zero hits on any planned file path.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `rg NEXT_PUBLIC_SITE_URL apps/ server/ lib/` returns zero hits in production code.
- [ ] `rg '"https://app\.soleur\.ai"' apps/ server/ lib/` returns exactly five hits — one per file touched by this PR (completeness guarantee).
- [ ] `rg reportSilentFallback apps/web-platform/app/api/checkout/route.ts apps/web-platform/app/api/billing/portal/route.ts apps/web-platform/server/notifications.ts` returns ≥1 hit per file.
- [ ] Degraded-path tests (1.1.2/1.2/1.3.3) assert BOTH (a) `captureException`/`captureMessage` fires with correct tags AND (b) downstream call uses the fallback URL.
- [ ] Happy-path tests assert BOTH (a) `captureException`/`captureMessage` NOT called AND (b) downstream call uses the env-derived URL (anti-tautology per `cq-mutation-assertions-pin-exact-post-state`).
- [ ] Full `apps/web-platform` vitest suite passes with zero regressions.
- [ ] `tsc --noEmit` and `next build` both pass.
- [ ] PR body contains `Closes #2770` and `Closes #2768`, a `## Changelog` section, and `semver:patch` + `type/security` labels.
- [ ] Multi-agent review (`/soleur:review`) pass with findings resolved inline.

### Post-merge (operator)

- [ ] Web Platform Release workflow for merge commit succeeded end-to-end.
- [ ] `docker inspect` image revision label matches PR-A merge commit SHA AND `docker exec … printenv NEXT_PUBLIC_APP_URL` returns `https://app.soleur.ai` (deterministic proof of new code running).
- [ ] `doppler secrets delete NEXT_PUBLIC_SITE_URL --project soleur --config prd` executed with explicit per-command go-ahead.
- [ ] `doppler secrets get NEXT_PUBLIC_SITE_URL -p soleur -c prd --plain` exits non-zero.
- [ ] `#2773` closed with Sentry-passive-signal comment + learning link.
- [ ] `#2774` closed as redundant with cross-reference to `#2773`.

## Risks / Sharp Edges

1. **Doppler `prd` delete ordering.** Deleting `NEXT_PUBLIC_SITE_URL` before the prod container restarts with migrated code would 500 `github-resolve`. Mitigated by Phase 5 sequencing (merge → release green → deterministic code-running check → ack → delete → verify absence). AC 5.2 is the gate.

2. **Sentry mock import-graph drift.** Naive `vi.mock("@sentry/nextjs", { ... })` can break `init`/`withSentryConfig` at import time and cascade into every test file that transitively imports the observability module. Mitigation: the exact partial-mock factory spelled out in Phase 1 (`async (orig) => ({ ...(await orig()), captureException: vi.fn(), captureMessage: vi.fn() })`). Also verify `server/observability.ts` does not export constants consumed by the four test files (`cq-test-mocked-module-constant-import`) before shipping.

3. **Completeness of the silent-fallback sweep.** Regex cannot prove absence of pathological patterns (backtick-quoted fallbacks, destructured defaults, variable-indirection, multi-line wrap). The brute-force `rg '"https://app\.soleur\.ai"'` in Phase 3.4 is the closest we get to deterministic — every hit of the literal must live in one of the five files. Any surprise hit = triage before ship.

## Domain Review

**Domains relevant:** none (carry-forward from brainstorm's `## Domain Assessments` — Engineering assessed inline).

No cross-domain implications — observability + config hygiene chore with no user-facing UI, no schema, no pricing/legal/marketing signal. Mechanical escalation scan: Files to Create = 0, zero `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` paths. **Product/UX Tier: NONE.** UX gate skipped.

## Test Strategy

- **Runner:** vitest via `apps/web-platform/node_modules/.bin/vitest run` (`cq-in-worktrees-run-vitest-via-node-node`).
- **Pattern per test file:** degraded-path (env unset → Sentry fires AND fallback URL used) + happy-path (env set → Sentry silent AND env URL used). Both assertions are load-bearing — one without the other permits silent regressions (finding: Kieran #3).
- **Sentry mock:** partial via `await orig()` spread, replacing only `captureException` / `captureMessage`.
- **Build-time validation:** `next build` catches route-file export constraint violations.
- **Framework:** vitest (existing convention — no new test dependencies).

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-22-app-url-hardening-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-app-url-hardening/spec.md`
- Prior PR: #2767 (original APP_URL missing-secret fix)
- Prior sweeps: #2480, #2484, #2487 (`reportSilentFallback` rollout + `observability.test.ts`)
- New learning (2026-04-22): `knowledge-base/project/learnings/best-practices/2026-04-22-passive-sentry-signal-closes-followthrough-verification.md`
- Rules: `cq-silent-fallback-must-mirror-to-sentry`, `hr-menu-option-ack-not-prod-write-auth`, `cq-write-failing-tests-before`, `cq-in-worktrees-run-vitest-via-node-node`, `cq-nextjs-route-files-http-only-exports`, `cq-mutation-assertions-pin-exact-post-state`, `cq-test-mocked-module-constant-import`, `wg-use-closes-n-in-pr-body-not-title-to`, `cq-for-production-debugging-use`, `cq-code-comments-symbol-anchors-not-line-numbers`
- Bundled issues: `#2770`, `#2768` (closed by this PR); `#2773`, `#2774` (closed out-of-band); `#2769` (PR-B).
