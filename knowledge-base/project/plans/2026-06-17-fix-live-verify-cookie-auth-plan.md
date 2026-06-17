---
title: "fix(live-verify): harness injected session cookie does not authenticate against prod (lands on /login)"
issue: 5485
branch: feat-one-shot-5485-live-verify-cookie-auth
worktree: .worktrees/feat-one-shot-5485-live-verify-cookie-auth
lane: cross-domain
brand_survival_threshold: none
created: 2026-06-17
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this fix is pure code against the already-provisioned
     live-verify surface. It introduces NO new server, secret, vendor, cron, DNS,
     or runtime process. The prod synthetic-principal bootstrap + seed
     (LIVE_VERIFY_* in Doppler prd) is PRE-EXISTING infrastructure owned by
     #5452 (bootstrap-live-verify.sh, already terraform-routed) and is NOT
     provisioned by this PR. AC8's "observe a real-deploy PASS" is a genuinely
     operator-gated observation step (requires a real qualifying deploy), not a
     provisioning step — documented with an Automation-not-feasible justification. -->

# fix(live-verify): injected synthetic-principal session cookie must authenticate against prod

## Enhancement Summary

**Deepened on:** 2026-06-17 · **Passes:** verify-the-negative (7 claims),
SSR-`setAll`-timing source trace, live MCP-browser prod recon, precedent-diff.

### Key refinements folded in
1. **Empty-jar RULED OUT.** Source trace of `@supabase/ssr@0.6.1` +
   `@supabase/auth-js` confirms `signInWithPassword` flushes `setAll` synchronously
   via the `onAuthStateChange('SIGNED_IN')` listener before it resolves
   (`createServerClient.js:36-54`, `GoTrueClient.js:649-651,2246`,
   `cookies.js:296-346`). The jar IS populated; the fix is the INJECTION shape, not
   the mint. Phase 2 reordered accordingly.
2. **Prod URL live-confirmed** = `https://api.soleur.ai` (fetched the deployed JS
   chunks via Playwright MCP this session) → cookie name `sb-api-auth-token`. Name
   divergence ruled out.
3. **"Host-only" wording corrected.** Both proven-working references
   (`bot-signin.ts`, `e2e/global-setup.ts`) set an EXPLICIT `domain` attribute
   (not a Domain-less host-only cookie); the harness's `domain: prodHost` matches
   that shape. The PRIMARY suspect is the forced `httpOnly: true` / dropped per-cookie
   `options` in `addCookies`.
4. **Encoding mismatch ruled out** — the SSR reader accepts both `base64-`-prefixed
   and raw-JSON values (`cookies.js:146-147,253-254`).

### New consideration discovered
The fix is now narrowly scoped: most-likely a one-attribute change (`httpOnly`),
but the live MCP repro (Phase 1) remains the binding gate — deepen narrows the
suspect set but does not replace the issue-mandated capture of the real cookie.

🐛 **Type:** bug · **Scope:** `apps/web-platform/scripts/live-verify/run.ts` (+ a unit test) · **Detail level:** MORE

## Overview

The live-verify harness (`scripts/live-verify/run.ts`, ADR-064) signs in as the
synthetic principal `live-verify@soleur.ai`, captures the Supabase SSR auth
cookies into an in-memory jar, injects them into a Playwright browser context,
and drives the **deployed** app. Every pre-launch gate passes (project-bind,
mint, `getUser()` allowlist) — but the browser **lands on `/login`**: the
injected cookies do not authenticate the deployed middleware. This is item 1 of
4 blocking #5463 (the report-only → blocking gate flip): the harness has never
emitted a true `RESULT: PASS`, so `wg-dark-launch-deploy-gates` can never be
satisfied.

**This is a pin-the-divergence-then-fix task, not a guessed one-liner.** The
issue mandates a live Playwright **MCP** repro (the dev host's bundled chromium
cannot run — unsupported OS) that captures the EXACT cookie name/domain/value a
real prod login sets vs. what the harness injects, BEFORE any code change.
Static research below narrows the candidate set and rules several theories out,
but the precise root cause is fixed in Phase 1 by live repro.

## Research Reconciliation — Static Findings vs. the Issue's Three Diagnostic Leads

The issue lists three diagnostic leads. Static reading of the installed
`@supabase/ssr@0.6.1` + `@supabase/supabase-js@^2.49` + the two PROVEN-WORKING
cookie-injection references in the repo lets us pre-classify each lead. **None of
these classifications is a license to skip the live repro — they scope it.**

| Lead (from issue) | Static finding | Confidence pre-repro |
|---|---|---|
| **(1) Domain scoping** — real login sets `Domain=.soleur.ai`; harness injects host-only | The deployed app sets auth cookies **host-only** (no `domain` in `cookieOptions` at `lib/supabase/server.ts:34-38`, `app/(auth)/callback/route.ts:155-159`, `middleware.ts:158-162`). `app/(auth)/callback/route.ts:202-205` explicitly documents "host-only Set-Cookie (no `domain` in cookieOptions)". `NEXT_PUBLIC_COOKIE_DOMAIN` (`.soleur.ai`) is read ONLY by the revocation-gate **clear** path (`middleware.ts:57,68-72`) — it does NOT configure the SSR client to emit Domain-scoped cookies. So the harness's host-only injection likely MATCHES the real shape. **Lead (1) is probably NOT the root cause** — but the live repro must confirm prod's actual `Set-Cookie` has no `Domain=` (a CF/proxy could rewrite it). |
| **(2) Cookie name / env divergence** — `sb-api-auth-token` vs `sb-<ref>-auth-token` | **Live-confirmed via MCP browser (this session):** the deployed client bundle bakes `NEXT_PUBLIC_SUPABASE_URL = https://api.soleur.ai` (`infra/seo-rulesets.tf:312` corroborates: `api.soleur.ai` is a DNS-only CNAME → `ifsccnjhymdmidffkzhl.supabase.co`). `@supabase/ssr` derives the cookie name as `sb-${hostname.split('.')[0]}-auth-token` = **`sb-api-auth-token`**. The harness mints with the SAME `NEXT_PUBLIC_SUPABASE_URL` (`run.ts:92`), validated host-allowed (`run.ts:127-134`) and ref-bound (`run.ts:137-145`). **Names should match** — but the repro MUST capture the exact jar key names (incl. chunk suffixes) the mint produces and confirm they equal the real login's. |
| **(3) Chunking / encoding** — `<name>.0`/`.1`, `base64-` prefix | `@supabase/ssr@0.6.1` defaults `cookieEncoding: "base64url"` (`createServerClient.js:13`), writing `base64-<b64url(JSON)>` split via `createChunks` (`cookies.js:311-318`). The READER reassembles chunks AND accepts both `base64-`-prefixed and raw-JSON values (`cookies.js:146-147,253-254`) — which is why the raw-JSON `bot-signin.ts` reference also authenticates. Both harness mint and middleware use the same default, so the value shape is internally consistent. **The repro must verify the jar actually contains the chunk set and that `addCookies` re-injects every chunk** (the harness maps `jar.cookies.entries()` 1:1, so it should — unless `setAll` never fired). |

**The strongest static lead the table surfaces (the actual suspect):** the
harness forces a **uniform, lossy cookie shape** in `addCookies` instead of
carrying the SSR client's own per-cookie `options`. `run.ts:255-264`:

```ts
await context.addCookies(
  Array.from(jar.cookies.entries()).map(([name, c]) => ({
    name,
    value: c.value,
    domain: prodHost,        // forces host-only app.soleur.ai (likely fine)
    path: "/",
    httpOnly: true,          // FORCED on every cookie — see risk below
    secure: true,
    sameSite: "Lax" as const,
  })),
);
```

Both proven-working references in the repo write the cookie differently:
- `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts:106-118` — single
  `sb-<ref>-auth-token`, **`httpOnly: false`**, host-only domain, raw-JSON value.
  This recipe IS confirmed to authenticate the deployed-style middleware
  (`knowledge-base/project/learnings/2026-06-02-playwright-mcp-local-auth-dashboard-verification.md`).
- `apps/web-platform/e2e/global-setup.ts:21-37` — same shape, `httpOnly: false`.

The harness's deviations from both working references (forcing `httpOnly: true`;
discarding the SSR `options`) are the live-repro's first suspects, in priority
order:

1. **Uniform-shape injection drops a load-bearing attribute (PRIMARY SUSPECT).**
   The forced `httpOnly: true` / dropped `options` may mis-shape a cookie the
   browser then refuses to send, or the value may not round-trip the reader. The
   repro pins this by comparing the real login's `Set-Cookie` lines (captured from
   a genuine `live-verify@soleur.ai` browser login) against the harness's
   `addCookies` payload, attribute by attribute.
2. **Domain attribute semantics.** Both working refs set an EXPLICIT `domain`
   (`localhost` / computed host) — NOT a truly host-only cookie (which omits
   `Domain` entirely; deepen verify-the-negative Claim 5). The harness's
   `domain: prodHost` is the same explicit-domain shape and is therefore likely
   fine — but the repro must confirm `prodHost` (the `cfg.productionUrl` host,
   `app.soleur.ai`) is the host the cookie must be scoped to, and that the
   navigate target host matches.

**RULED OUT by deepen research (do NOT chase these):**
- **Empty jar / `setAll` never fired.** Deepen traced the installed source: in
  this exact server-client config, `signInWithPassword` `await`s
  `_saveSession → _notifyAllSubscribers('SIGNED_IN')`, and `createServerClient`'s
  registered `onAuthStateChange` listener (`createServerClient.js:36-54`) flushes
  `applyServerStorage → setAll` synchronously **before `signInWithPassword`
  resolves** (`GoTrueClient.js:649-651,2246`; `cookies.js:258-276,296-346`). The
  jar IS populated by `run.ts:195`. Empty-jar is not the bug. (A name-only
  `jar.cookies.size`/key-set log in Phase 1 still confirms this empirically, but
  the fix should NOT be "re-trigger the flush".)
- **Cookie-name divergence.** Live-confirmed prod URL = `https://api.soleur.ai`
  (this session) → `sb-api-auth-token`; the harness mints with the same env var,
  ref-bound. Names match.
- **base64/chunk encoding mismatch.** Both sides use `@supabase/ssr` defaults and
  the reader accepts both shapes (verify-the-negative Claim 3 confirmed).

### Capability-claim verification (`hr-verify-repo-capability-claim-before-assert`)
- `@supabase/ssr@0.6.1` cookie name derivation, base64url default, chunk
  reassembly, and dual-encoding reader: read directly from
  `apps/web-platform/node_modules/@supabase/ssr/dist/main/{createServerClient,cookies}.js`
  and `@supabase/supabase-js` umd bundle (`sb-${r.hostname.split('.')[0]}-auth-token`).
- Prod `NEXT_PUBLIC_SUPABASE_URL = https://api.soleur.ai`: live-confirmed by
  fetching the deployed JS chunks via the Playwright MCP browser this session.
- Working-reference cookie shapes: read from `bot-signin.ts` and
  `e2e/global-setup.ts` directly.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — the
live-verify harness is an internal post-deploy CI gate. A broken harness means
the operator's deploy-verification gate keeps emitting `CANT-RUN`/false-`/login`
and #5463 stays blocked; no end-user surface changes.

**If this leaks, the user's data is exposed via:** the harness handles the
synthetic principal's prod session cookie + password. The existing `error.name`-only
+ `redact()` discipline (`scripts/live-verify/redact.ts`) keeps secrets out of
logs; this fix MUST preserve it (any new diagnostic log emits cookie **names**
and **counts** only, never values).

**Brand-survival threshold:** none — internal tooling, synthetic principal, no
end-user data surface, no new regulated-data processing. Reason: the change is
confined to how an internal harness re-injects an already-minted synthetic
session into a headless browser; it touches no end-user route, schema, or
auth flow. (Sensitive-path note: `run.ts` is under `apps/web-platform/scripts/`,
not an auth/route/schema surface — preflight Check 6's sensitive-path regex does
not match, so no scope-out bullet is required, but this threshold line documents
the assessment.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Live divergence pinned (Phase 1, MCP browser).** A live Playwright
  **MCP** repro is performed and its findings recorded in the PR body: (a) the
  EXACT cookie name(s), domain attribute, `httpOnly`, `secure`, `sameSite`, and
  value-prefix shape a real `live-verify@soleur.ai` prod login sets (captured via
  `browser_context.cookies()` after a genuine login on `app.soleur.ai`); (b) the
  EXACT name/value/options shape the harness's mint jar produces and what
  `addCookies` injects; (c) the single attribute (or empty-jar condition) that
  differs. No values are echoed — names, counts, and attribute flags only.
- [x] **AC2 — Fix matches the deployed reader.** `run.ts` is changed so the
  injected cookies match what the deployed `@supabase/ssr` middleware reads:
  every chunk is re-injected (the 1:1 `jar.cookies.entries()` map already does
  this — do not regress it), and the per-cookie shape carries the attributes the
  deployed reader expects: `domain` = the app host (`prodHost` = `app.soleur.ai`,
  the same explicit-domain shape both working refs use), `secure: true`,
  `sameSite: Lax`, and the `httpOnly` value the live repro showed the real cookie
  uses — do NOT blindly keep `httpOnly: true` if the repro shows otherwise.
- [x] **AC3 — Authenticated render, not /login (MCP browser).** Verified via the
  Playwright **MCP** browser against prod: after injecting the harness cookies and
  navigating to `/dashboard` (dry-run path) the page renders the authenticated
  dashboard with the conversations rail present (`[data-testid="conversations-rail"]`),
  NOT `/login`. Record the final URL + rail-present assertion in the PR body.
- [x] **AC4 — No-secret-echo discipline preserved.** Any new diagnostic logging
  emits cookie **names**/counts/attribute flags only — never cookie values,
  tokens, the session JSON, or `error.message`. `grep -nE 'console\.(log|error|warn)' scripts/live-verify/run.ts`
  shows every site routes through `redact()` or emits only structural metadata;
  the `error.name`-only sign-in/getUser failure paths (`run.ts:193,215`) are
  unchanged.
- [x] **AC5 — Unit test for the injection shape.** A new test in
  `apps/web-platform/test/live-verify/` asserts the cookie-build/injection helper
  produces the correct shape for a synthetic (non-secret) session fixture:
  derived name `sb-api-auth-token` (chunked names if applicable), host-only domain
  = the app host (not the supabase host), and the attribute set matching the
  deployed reader. Verifies via `cq-test-fixtures-synthesized-only` — the fixture
  session is fabricated, never a real token. Test runs under vitest
  (`test/**/*.test.ts`) per `vitest.config.ts` include globs.
- [x] **AC6 — typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
- [x] **AC7 — existing harness suites green.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-verify/`
  (gate.test.ts + redact.test.ts + the new injection test) all pass.

### Post-merge (operator)

- [ ] **AC8 — Real-deploy PASS observed (feeds #5463).** Automation: not feasible
  in-PR because it requires a real qualifying deploy AND the bootstrapped prod
  synthetic principal (`LIVE_VERIFY_*` + `LIVE_VERIFY_USER_PASSWORD` in Doppler
  `prd`, provisioned out-of-band by the PRE-EXISTING `bootstrap-live-verify.sh`,
  owned by #5452 — NOT provisioned by this PR). After the next real
  realtime/WS/auth/DOM-timing PR merges post-this-fix, confirm the report-only
  gate emitted a correct `RESULT: PASS` (or a real `FAIL` for a genuine rail
  regression) — NOT a cookie-auth `CANT-RUN`/`/login` artifact. Record the run on
  #5463 as the `wg-dark-launch-deploy-gates` "observed passing on ≥1 real deploy"
  evidence. This is the gate-flip prerequisite, tracked by #5463, not by this PR.

## Implementation Phases

### Phase 0 — Preconditions (no code)
- Read `run.ts`, `middleware.ts`, `lib/supabase/server.ts`,
  `app/(auth)/callback/route.ts`, `bot-signin.ts`, `e2e/global-setup.ts`,
  `scripts/live-verify/redact.ts`, `test/live-verify/gate.test.ts` before editing
  (`hr-always-read-a-file-before-editing-it`).
- Confirm vitest include globs in `apps/web-platform/vitest.config.ts` so the new
  test path is collected (`test/**/*.test.ts`).
- Confirm the synthetic principal is bootstrapped in prod Doppler (the live repro
  needs it). If NOT bootstrapped, the Phase-1 live login repro is blocked — escalate
  per the issue rather than guessing; do not skip Phase 1.

### Phase 1 — LIVE MCP REPRO (pin the divergence; NO code change yet)
This phase is the load-bearing deliverable. Per the issue, do NOT change code until
the divergence is pinned.
1. Via the Playwright **MCP** browser, perform a genuine `live-verify@soleur.ai`
   login on `https://app.soleur.ai` (fill the real login form; the synthetic
   principal's password is read from Doppler `prd` at the keyboard, never echoed).
2. Capture the real session cookies with `browser_context.cookies()` (or
   equivalent MCP call) — record name(s), `domain`, `httpOnly`, `secure`,
   `sameSite`, `path`, and whether the value starts with `base64-` (record the
   PREFIX shape only, never the value).
3. Separately, instrument the harness mint locally to log `jar.cookies.size` and
   the jar KEY SET (names only) after `mintSession` — OR run the harness under
   `--dry-run` with temporary name-only logging — to capture what the mint
   produces. Remove the temporary logging before commit (or route it through a
   redacted, names-only diagnostic that stays).
4. Diff (a) vs (b) attribute-by-attribute and write the pinned divergence into the
   PR body (AC1). Deepen research already ruled out empty-jar, name divergence, and
   encoding mismatch (see Research Reconciliation), so the expected outcomes are:
   - **Mis-shaped attribute** (`httpOnly` flag, `sameSite`, or value round-trip) →
     fix Phase 2 (PRIMARY).
   - **A genuinely unexpected divergence the live capture surfaces** (e.g., prod
     `Set-Cookie` carries an attribute the harness drops) → fix Phase 2.

### Phase 2 — Fix `run.ts` (TDD: write the failing test first per `cq-write-failing-tests-before`)
The jar IS populated (deepen-confirmed) — the fix is the INJECTION shape, not the
mint. Carry the SSR client's own per-cookie `options` through to `addCookies`
instead of the hardcoded uniform shape, OR set exactly the attributes the live
repro pinned. Most likely change: `httpOnly: false` to match both proven-working
references (`bot-signin.ts:114`, `e2e/global-setup.ts:29`) — but ONLY if the
repro confirms the real cookie is non-httpOnly; if prod's `Set-Cookie` is
`HttpOnly`, keep `true`. Keep `domain` = the app host (`prodHost`), `secure: true`,
`sameSite: "Lax"`; re-inject EVERY chunk name 1:1 (the harness already maps
`jar.cookies.entries()` 1:1, so chunk coverage is preserved — do not regress it).
Extract the injection mapping into the testable `buildInjectedCookies` helper.
Preserve `error.name`-only + `redact()` discipline at every log site (AC4).

### Phase 3 — Unit test (AC5)
- Add `test/live-verify/cookie-injection.test.ts` (or extend `gate.test.ts`)
  asserting the injection-helper output shape for a synthesized session fixture.
  Export a small pure helper from `run.ts` (e.g. `buildInjectedCookies(jarOrSession, appHost, supabaseUrl)`)
  so the shape is unit-testable without launching a browser — mirrors how
  `bindProject`/`verifyPrincipal` are already exported and tested. Fixture is
  fabricated (`cq-test-fixtures-synthesized-only`).

### Phase 4 — Verify
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC6).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-verify/` (AC7).
- Live MCP-browser confirmation of the authenticated `/dashboard` render (AC3).

## Files to Edit
- `apps/web-platform/scripts/live-verify/run.ts` — fix the cookie
  build/injection (Phase 2); extract a pure `buildInjectedCookies` helper for
  testability. Lines of interest: mint `164-196`, injection `255-264`.

## Files to Create
- `apps/web-platform/test/live-verify/cookie-injection.test.ts` — unit test for
  the injection-shape helper (AC5). (May instead extend
  `test/live-verify/gate.test.ts` if the helper is small.)

## Non-Goals / Out of Scope
- **Flipping the gate to blocking** — that is #5463, gated on AC8's real-deploy
  PASS observation (`wg-dark-launch-deploy-gates`). This PR only makes the harness
  authenticate.
- **Re-homing the harness into a GitHub Action** — separate item in the #5463
  prereq chain.
- **Any change to the deployed app's cookie shape** (`middleware.ts`,
  `lib/supabase/server.ts`, callback) — the fix is harness-side; the deployed
  reader is the fixed contract.

## Open Code-Review Overlap
Checked open `code-review` issues against `scripts/live-verify/run.ts` and
`test/live-verify/cookie-injection.test.ts`: **None.** (Query:
`gh issue list --label code-review --state open --json number,title,body` →
no body contains either path.)

## Risks & Mitigations
- **Risk: shipping a guessed one-line fix without the live repro.** Mitigation:
  Phase 1 is a hard gate — AC1 requires the pinned divergence in the PR body before
  any `run.ts` edit. The static table above deliberately rules theories IN/OUT but
  does not name a single fix.
- **Risk: `httpOnly` guess.** The working references use `httpOnly: false`, but the
  real server-set auth-token cookie may be `httpOnly: true`. Mitigation: AC2/AC1
  force the value to come from the live capture, not from the working-reference
  default.
- **Risk: leaking a secret in a new diagnostic log.** Mitigation: AC4 + the
  existing `redact()` test (`test/live-verify/redact.test.ts`) — any new log emits
  names/counts only; temporary repro logging is removed before commit.
- **Risk: vitest does not collect a co-located test.** Mitigation: place the test
  under `test/live-verify/` (matches `vitest.config.ts` `test/**/*.test.ts`),
  never co-located beside `run.ts`.
- **Precedent-diff (deepen-plan Phase 4.4):** the cookie-injection precedent is
  `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts` (proven-working prod
  auth-cookie writer) and `apps/web-platform/e2e/global-setup.ts` (mock). Diff the
  final `run.ts` injection shape against `bot-signin.ts:106-118`.

## Observability
```yaml
liveness_signal:
  what: the harness's single `RESULT: PASS|FAIL|CANT-RUN` line emitted by emit()
  cadence: per post-deploy gate run (report-only via agent-postmerge today)
  alert_target: the postmerge gate consumer surfaces the RESULT line; #5463 wires the blocking flip
  configured_in: scripts/live-verify/run.ts:413-421 (emit) + the postmerge gate path
error_reporting:
  destination: stdout RESULT line (redacted); harness is a CI script, not a server route — no Sentry surface (edge/server observability does not apply to a bun CLI gate)
  fail_loud: a cookie-auth failure now surfaces as a real FAIL/diagnostic, not a silent /login that masquerades as a rail regression — the fix makes the gate's true-positive reachable
failure_modes:
  - mode: injected cookies still land on /login (fix incomplete)
    detection: AC3 MCP-browser render assertion; post-merge the RESULT line is CANT-RUN/FAIL not PASS
    alert_route: PR-blocking AC3; post-merge #5463 observation gate
  - mode: secret echoed in a new diagnostic log
    detection: AC4 grep + redact.test.ts; review-time silent-failure/no-secret-echo check
    alert_route: PR-blocking AC4
logs:
  where: the single redacted RESULT line on stdout (CI job log); no persistent store
  retention: CI run retention only; raw captures destroyed at end of run (I-ephemerality, run.ts:445-457)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/live-verify/ (no remote shell — local vitest only)"
  expected_output: all live-verify suites green incl. the new cookie-injection shape test
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI tooling bug fix confined to
how a headless-browser harness re-injects an already-minted synthetic session.
No user-facing surface, no schema, no new infrastructure, no new vendor. (Product
mechanical UI-surface override checked: `Files to Edit`/`Files to Create` contain
no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` path — gate
skipped correctly.)

## Architecture Decision (ADR/C4)

No new architectural decision. ADR-064 (live-production-verification-harness)
already records the harness design, binding invariants, and the
chromium.launch + `context.addCookies()` driver choice. This is a bug fix that
makes the EXISTING design's cookie-injection actually work — it does not change
any documented invariant, ownership boundary, or substrate. A competent engineer
reading ADR-064 + C4 is not misled by this fix (it closes the gap between the
ADR's stated behavior and reality). Gate skipped.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan's section is filled with a concrete artifact, exposure
  vector, and a `none` threshold + reason.
- **Do NOT ship a guessed one-line fix.** The static table rules theories in/out
  but Phase 1's live MCP repro is the contract that pins the actual divergence.
  The most-likely suspect (forced uniform `addCookies` shape / possibly-empty jar)
  is a hypothesis, not the answer.
- The cookie NAME derives from `NEXT_PUBLIC_SUPABASE_URL` host (`api` →
  `sb-api-auth-token`), but the cookie DOMAIN must be the **app host**
  (`app.soleur.ai`), not the supabase host — both working references do exactly
  this. Mixing them up reintroduces the `/login` bounce.
- "Host-only" is a misnomer for the injected cookie: Playwright's `addCookies`
  with an explicit `domain` field produces a cookie sent to that host (and
  subdomains). The deployed server's `Set-Cookie` is genuinely Domain-less
  host-only, but the BROWSER-side injected cookie carrying `domain: app.soleur.ai`
  is still sent to `app.soleur.ai` — which is what both working refs rely on.
  Don't "fix" this into a Domain-less injection.
- The jar is NOT empty (deepen-confirmed). If the live repro shows zero cookies
  injected, the bug is upstream of the documented flush (e.g., a thrown mint
  error swallowed as CANT-RUN) — re-read the source trace before assuming the
  flush regressed.
