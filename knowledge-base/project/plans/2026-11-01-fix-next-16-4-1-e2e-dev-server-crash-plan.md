---
title: "chore(deps): bump next to ~16.4.1 (3 critical/high advisories) — blocked by e2e dev-server crash"
date: 2026-11-01
slug: fix-next-16-4-1-e2e-dev-server-crash
branch: feat-one-shot-11772-next-dev-server-crash
issue: 11772
closes: 11772
type: fix
priority: critical
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(deps): bump next to ~16.4.1 — unblock the e2e dev-server crash

## Overview

Re-apply the `next` ~16.4.1 bump that was bisected out of the merged 2026-10-31
critical/high Dependabot batch (PR #11691, merged 2026-11-01) because the
bumped tree killed the e2e dev server deterministically (3 consecutive e2e
failures while sibling PRs were green): mid-run
`⨯ uncaughtException: Error: aborted` (ECONNRESET), then connection-refused for
every remaining test. The bump closes the last two CRITICAL advisories
(GHSA-2464-fhr4-w9xw, GHSA-673q-mjm6-r5xr — unauthenticated RCE) plus one HIGH
(GHSA-p3m5-59mp-jv5r — Server Actions DoS); all three fix at next ≥16.4.1.

Plan-time research located the root cause upstream. vercel/next.js #49587 (the
consolidated tracker; #84649 closed as its duplicate on 2026-08-31) documents
that when the proxy/middleware layer clones a request body,
`getCloneableBody(req).finalize()` → `replaceRequestBody` copies the buffered
stream's enumerable properties onto the `IncomingMessage` — including `_events`,
which wipes the `'error'` listeners already attached. A client disconnect then
reaches `abortIncoming` → `req.destroy(err)` with zero `'error'` listeners →
`uncaughtException: Error: aborted` (`code: 'ECONNRESET'`). The upstream repro
shows stock `next start`/`next dev` **logs `⨯` and keeps running** — the death
in our tree is `server/crash-handlers.ts:installCrashHandlers()` calling
`process.exit(1)` on every uncaught exception (ADR-062 Deliverable C). The
upstream commenter reproduced end-to-end on `next@16.4.2`; no released fix
exists (latest stable 16.4.3; the suggested one-line upstream fix is carried as
a downstream patch by the reporter only).

The fix: teach the crash handler to classify the benign inbound client-abort
signature (`Error`, `message === "aborted"`, `code === "ECONNRESET"` — Node's
`connResetException` shape) as **non-fatal**: emit a per-abort pino warn plus a
`mirrorWarnWithDebounce`-bounded `warnSilentFallback` Sentry arm (the existing
warn-level mirror, `server/observability.ts`; the trigger is unauthenticated so
the Sentry arm is debounced under a constant key while the pino line preserves
the per-abort burst count) and keep running,
restoring the stock-Next behavior stock servers already exhibit. Then re-apply
the bump, guard rows, and the re-measured egress header pin exactly as the
reverted change had them.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-01 · **Mode:** sequential-fallback (Devin CLI harness —
no Task/AskUserQuestion tool; all gates and deep-dives ran inline against the
repo, never claimed as independent agent review).

**Halts evaluated (§4.5–§4.13):** all pass — §4.5 fired (ECONNRESET) and the
Network-Outage Deep-Dive is recorded under Hypotheses; §4.55 downtime trigger
does not fire (normal container-restart deploy path); §4.6/§4.7 sections present
and non-placeholder; §4.8 PAT sweep clean; §4.9 non-UI; §4.10 no store/connection
added; §4.11 `lint-guard-contract.py` green on 2 guard entries; §4.12 Scope Check
compliant (1 unfenced section, 5/5 asks mapped); §4.13 no autonomous task.

**Key deepen findings:**

1. **Near-miss population measured (verify-the-negative pass):**
   `server/dsar-export.ts` throws `new Error("aborted")` at 48 sites
   (abort-signal arms), plus 4 in `server/dsar-export-co-uploader.ts` —
   seat-verified 2026-11-01 (git-history seat; an earlier "35 sites + CTO-verified"
   figure was undercounted, corrected at review). These carry NO `.code`, so the exact-pair predicate
   (`message` + `code: "ECONNRESET"`) still exits on them — the no-code test arm
   covers the population. A future contributor adding `.code = "ECONNRESET"` to a
   thrown Error is the only masking path; the Guard-2 matrix pins that mutation.
2. **Rule-id + attribution audit clean:** every `hr-*`/`wg-*`/`cq-*` citation
   resolves live (`wg-architecture-decision-is-a-plan-deliverable` is
   migrated-but-active in `scripts/migrated-rule-ids.txt`); #11772 open,
   #11691 merged (squash `075b1889` is ancestor of origin/main), #11783 filed,
   #9167/#7591/#8450 closed, #2591 open code-review (no file overlap), #5417 open.
3. **Precedent-diff (§4.4):** the benign-abort branch is the first non-fatal
   class in `crash-handlers.ts` — no precedent; pattern is novel (the sibling
   `reportFatalAndExit` path is the only shape to mirror). The ADR-062 amendment
   is the corresponding record.
4. **Post-edit self-audit:** no symbol the plan drops or renames; all backticked
   identifiers re-read from source (`warnSilentFallback`,
   `isBenignClientAbort` is new-by-design, `FLOOR_ANCHORS`/`REQUIRED`/`MIN_*`
   constants confirmed at their cited lines).

## Problem Statement

Dependabot could not ship `next` 16.4.1 because the e2e job failed
deterministically on the bumped tree. Three critical/high advisories are open
against the production app (`app.soleur.ai` — `/dashboard` and every
authenticated route) until `next` reaches ≥16.4.1:

| Advisory | Severity | Class |
|---|---|---|
| GHSA-2464-fhr4-w9xw | CRITICAL | unauthenticated RCE |
| GHSA-673q-mjm6-r5xr | CRITICAL | unauthenticated RCE |
| GHSA-p3m5-59mp-jv5r | HIGH | Server Actions DoS |

The same abort-crash path also exists in **production**: `installCrashHandlers`
exits the process on this exception class under `next start`-equivalent serving
(the custom server runs `next({dev:false})` in prod), so an unauthenticated
client aborting a body-bearing, proxy-handled request can restart the prod
container — the upstream issue's reporters call this a DoS surface. The
classifier is therefore not an e2e-only shim; it changes prod crash semantics
and is planned, gated, and ADR-amended accordingly.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on origin/main | Plan response |
|---|---|---|
| "`next` was bisected out after e2e failed deterministically 3x" | Confirmed. `apps/web-platform/package.json:55` is back at `~16.3.8`; lockfile resolves 16.3.8; squash commit `075b1889ad` (PR #11691) carries the bisect note. | Re-apply the same bump shape. |
| "Suspects: next 16.4.x dev-server abort handling, or @sentry/nextjs 10.77 request wrapping" | Resolved `@sentry/nextjs` is 10.77.1, but upstream repro (next.js #49587, #84649) needs **no Sentry, no custom server** — `next start` logs `⨯ uncaughtException` and keeps running. The proximate killer in our tree is `installCrashHandlers` → `exit(1)`. | Fix `server/crash-handlers.ts`, not Sentry config. The issue's "reproduce with Sentry env set" lead is recorded as a hypothesis, not a requirement. |
| "Preceded by `/api/team-names` → 500s on the authenticated path" | `e2e/mock-supabase.ts` has **no `/rest/v1/team_names` endpoint** — the catch-all 404 → `namesResult.error` → route returns 500 (`app/api/team-names/route.ts` › `GET()` 500 return). The 500s are pre-existing mock-coverage noise on 16.3.8 too, not a crash precursor. | Out of scope (noise reduction, not causal); recorded here so the implementer does not chase it as a reproduction signal. |
| "Re-apply `\"next\": \"~16.4.1\"`" | Latest published stable is **16.4.3**; `~16.4.1` resolves to it — the same resolved version that crashed. No fixed upstream release exists to prefer. | Bump as asked; mitigation is ours. |
| Guard rows "MIN_ROWS/MIN_RESOLVED 35→36; test arm `next:16:16.4.1`; MIN_ASSERTIONS 33→34" | Verified: `scripts/assert-dependabot-drain.py` `MIN_ROWS = 35` (line 279), `MIN_RESOLVED = 35` (line 287), `WATCHED_PACKAGES` has no `next` (line 41), `FLOOR_ANCHORS` has no `next` (line 163), REQUIRED comment at line ~121 already says the next row "lands in its own PR with its own row re-added here". Test file has `MIN_ASSERTIONS=33` (line 452) and the spec-grep loop lacks a `next:16:16.4.1` arm (line 232). The fixture `web` list already synthesizes `node_modules/next@16.999.999` (test.sh:94) so the re-added row resolves. | Re-add exactly those edits. |
| "Re-pin `test/egress-audit-ingest.test.ts` minor to `^16\.4` (headers already re-measured on 16.4.3)" | Verified: line 244 pins `/^16\.3\./`; the re-measurement comment ("Measured on Next 16.3.8, re-measured on 16.4.3 (identical four-header set, grepped from dist/compiled/next-server/server.runtime.prod.js)") survived the bisect at line ~262. | Restore `^16\.4` — the evidence is already in the file. |

## Hypotheses

Phase 1.4 trigger (`ECONNRESET`) — layers in L3→L7 order per
`plan-network-outage-checklist.md`, each with verification artifact or cited
opt-out. **Network-Outage Deep-Dive status (deepen §4.5):** L3 firewall —
not-applicable (loopback, artifact below); L3 DNS/routing — not-applicable
(readiness poll succeeded earlier in the same job); L7 TLS — not-applicable
(plain HTTP dev servers); L7 application — verified (the process threw).
`SOLEUR_RULE_APPLIED` telemetry emitted for `hr-ssh-diagnosis-verify-firewall`.

1. **L3 firewall allow-list** — opted out: the aborted connection is Playwright→dev-server on `127.0.0.1` inside one CI container; no host firewall filters loopback, and post-crash symptom is `ERR_CONNECTION_REFUSED` (nothing listening), not filtered SYN. Artifact: `playwright.config.ts` `baseURL: http://localhost:3099|3100`, `web-server.sh` exit-marker comment ("a mid-run death reads as bare net::ERR_CONNECTION_REFUSED").
2. **L3 DNS / routing** — opted out: `localhost` resolves via the container's hosts file; the readiness poll `http://localhost:3100/login` succeeded earlier in the same job (the suite ran tests before dying), which proves resolution + routing worked. Artifact: e2e job log shape in #11772 — tests ran, then refused.
3. **L7 TLS / proxy layer** — opted out: e2e dev servers serve plain HTTP on loopback; no TLS, no CDN/edge between client and server. Artifact: `webServer[].url` is `http://` in `playwright.config.ts`.
4. **L7 application layer** — verified: the dev server's own stderr carries `⨯ uncaughtException: Error: aborted` (`code: 'ECONNRESET'`) immediately before death, i.e. the packet reached the service and the **process** threw. Artifact: failure signature quoted in #11772; `web-server.sh` prints `e2e-webserver: exited rc=<n>` on child exit.
5. **H1 — upstream proxy-body-clone listener wipe (primary, confirmed by upstream repro).** Per vercel/next.js #49587: `getCloneableBody().finalize()` → `replaceRequestBody` copies `_events` off the buffered stream onto the `IncomingMessage`, deleting its `'error'` listeners; a mid-response client disconnect then surfaces as `uncaughtException: Error: aborted`. Requires: request has a body + proxy/middleware returns the response (or clones for header modification — our `middleware.ts` sets request headers via `NextResponse.next({ request: { headers } })` and `proxyClientMaxBodySize: 25MB` keeps cloning on that path) + client disconnects mid-response. Reproduced by upstream on 16.4.2; no released fix.
6. **H2 — crash-handler converts log-only abort to process death (confirmed by code read).** `server/crash-handlers.ts:62-68` exits on every uncaughtException/unhandledRejection; the upstream repro shows stock Next logs `⨯` and continues. Both `uncaughtException` (full-body-then-abort) and `unhandledRejection` (abort mid-body-write) shapes must be covered — upstream #84649 notes both.
7. **H3 — why 16.4.x trips it where 16.3.8 did not (unverified, attribution hypothesis).** The `_events` wipe exists across versions (upstream: same on 14.2.35/15.5.4). The 3× determinism on 16.4.3 suggests 16.4 widened either the set of requests that take the body-clone path or the abort window (compile/serve timing). The implementation phase verifies the repro on 16.4.3; whether 16.3.8 shares it is informational only — the classifier is correct either way because the abort is provably benign.
8. **H4 — @sentry/nextjs request wrapping as a second emitter (downgraded).** Sentry's `withSentryConfig` request wrapping could in principle re-emit the same signature, but the upstream repro excludes Sentry entirely; deprecation warnings (`withSentryConfig` import path, `disableLogger`) are warnings, not a crash mechanism. No Sentry-env requirement for reproduction.

## Research Insights

**Premise Validation (Phase 0.6):** Issue #11772 OPEN; PR #11691 MERGED
2026-11-01T06:09:53Z. All cited paths verified on origin/main: `~16.3.8` pin,
guard script constants (WATCHED_PACKAGES/REQUIRED/FLOOR_ANCHORS/MIN_ROWS=35/
MIN_RESOLVED=35), `MIN_ASSERTIONS=33`, `^16\.3\.` egress pin with the 16.4.3
re-measure comment intact. ADR corpus check for the mechanism: ADR-062
Deliverable C codifies the capture→close→exit contract this plan refines →
in-scope ADR amendment (Phase 2.10). Collision pre-check
(`scripts/collision-precheck.sh 11772`, exit 10): open PR #11780 names #11772 —
it is **this pipeline's own draft** on `feat-one-shot-11772-next-dev-server-crash`
(body: "Draft PR created automatically"), not a competing fix. Foreign
`test-all.sh` processes belong to sibling worktrees
(feat-one-shot-11556-epic-ci-time-batch, feat-one-shot-post-merge-leftovers-npm-tally)
— informational; no duplicate work on #11772.

**Property List (Phase 0.6b):**

1. `next` ≥16.4.1 installed for web-platform — verbatim ask (3 advisories).
2. e2e dev server survives benign client request aborts — verbatim ask ("e2e-clean").
3. Drain-guard coverage re-added so the floor cannot silently regress — verbatim ask.
4. Fatal-attribution contract preserved: non-abort fatals still capture → close → exit — implicit ask (do not break #5417/ADR-062's control).
5. Egress-audit Next-minor pin tracks 16.4 — verbatim ask.

**Cut List (Phase 0.6b):**

- E2e dev-server respawn/retry wrapper — buys property 2 redundantly; the classifier buys it more cheaply and also fixes prod. Cut.
- `node_modules` patch machinery (patch-package/postinstall patch of `body-streams`) — no patch mechanism exists in the repo; heavier than the classifier for the same property. Cut (upstream-fix adoption is a tracked deferral instead).
- @sentry/nextjs pin/deprecation-warning churn — buys no listed property; the crash mechanism does not involve Sentry. Cut.
- `middleware.ts` restructure to avoid proxy-returned responses — cannot be made airtight (redirects must return; body cloning also fires on request-header modification) and the property is already bought by the classifier. Cut.

**Repo patterns and file paths:**

- `apps/web-platform/server/crash-handlers.ts` — `installCrashHandlers()` (lines 62-68), `reportFatalAndExit` (36-60), `FATAL_FLUSH_MS` (27).
- `apps/web-platform/server/observability.ts` — `warnSilentFallback` (`observability.ts` › `warnSilentFallback()`): warn-level pino+Sentry mirror; the correct sink for a non-fatal class per `cq-silent-fallback-must-mirror-to-sentry`.
- `apps/web-platform/test/crash-handlers.test.ts` — existing RED/GREEN suite: mocks `@sentry/nextjs` (`captureException`, `close`) and `process.exit`; extend for the classifier arms.
- `apps/web-platform/server/index.ts:83` — sole `installCrashHandlers()` call site; `server/index.ts:156` — `handle(req, res, parsedUrl)` inside `createServer`.
- `apps/web-platform/middleware.ts` — returns `NextResponse.redirect` (proxy-returned responses = the upstream trigger shape) and `NextResponse.next({ request: { headers } })` (header modification → body-clone path).
- `scripts/assert-dependabot-drain.py` + `.test.sh` — guard structure verified (constants at lines 41/163/279/287; test spec-loop line 232, `MIN_ASSERTIONS=33` line 452, `web` fixture already includes `("next", 16)` at line 94).
- `apps/web-platform/test/egress-audit-ingest.test.ts:244` — `/^16\.3\./` pin; re-measure comment at ~262.
- `apps/web-platform/e2e/web-server.sh` — prints `e2e-webserver: exited rc=<n> port=<p> distdir=<d> uptime=<t>s` on child death (#9167); the post-fix observability line for any residual mid-run death.
- `apps/web-platform/e2e/mock-supabase.ts` — no `/rest/v1/team_names` route (catch-all 404); explains the pre-crash 500s as pre-existing noise.
- CI pins npm@11 (`ci.yml` "Override bundled npm with npm@11", line ~919) — lockfile regen must run `npx --yes npm@11 install --package-lock-only` in `apps/web-platform/`. Root `package-lock.json` contains no `next` package entry (verified via `packages` scan) — only the web-platform lockfile changes. `lint-dual-lockfile.sh` is an existence guard (bun-vs-npm), not a content-sync one.
- `package.json:dev` — `esbuild server/index.ts --bundle ... --outfile=.next/dev-server.mjs && node .next/dev-server.mjs`; `build:server` uses `--external:next`, so the crash-handler edit reaches both dev and prod bundles.

**External research (Phase 1.6b — warranted: upstream-bug territory):**

- vercel/next.js #49587 — canonical issue (OPEN). Root cause + minimal repro + suggested fix (`p2.on('error', () => {})` in `cloneBodyStream`), reproduced on `next@16.4.2` 2026-10-16; reporter carries a downstream patch.
- vercel/next.js #84649 — closed-as-duplicate of #49587 (2026-08-31); documents the `unhandledRejection` variant (abort before body fully written) and notes "nextjs seems to suppress this by default" for stock servers.
- vercel/next.js #56529 — SSE-disconnect sibling; confirms `Error: aborted`/ECONNRESET reaches `uncaughtException` on client close, still open on 16.x.
- `npm view next` — latest stable 16.4.3; 16.5.0 is canary-only. No released fix.

**Institutional learnings applied:**

- `knowledge-base/project/learnings/` — `2026-03-17-planning-direction-confirmation-required` (direction is unambiguous: re-apply, not re-route), ADR-176/#7418 checkpoint discipline (this skeleton was written before the fan-out).
- `cq-silent-fallback-must-mirror-to-sentry` — the non-fatal path mirrors via `warnSilentFallback`, never swallows.
- `hr-observability-as-plan-quality-gate` — Observability section present; discoverability probe is a grep of the emitted tag.

**Related issues/PRs:** #11772 (target), #11691 (merged batch), vercel/next.js #49587/#84649/#56529, #9167 (web-server exit marker), #5417/ADR-062 (crash attribution), #7591 (prior next-16 discharge of postcss/sharp rows — MUST_STAY_ABSENT stays inverted), #8450 (e2e applicability classifier — a package.json+lockfile diff is `applicable=true`, so the e2e job will actually run this time).

**Phase 1.5 community discovery:** TypeScript/Node only — covered by built-in agents; skipped.
**Phase 1.5b functional overlap:** no Task agent on this harness; assessed inline — the deliverable is a repo-local crash classification + a dep re-apply; no community skill plausibly covers it. Skipped.
**Phase 1.8 skill-description budget:** no `SKILL.md` `description:` edit is a candidate. Skipped.

## Proposed Solution

1. **Classify the benign abort at the process boundary.** In
   `server/crash-handlers.ts`, add `isBenignClientAbort(err)` — true iff
   `err instanceof Error && err.message === "aborted" && err.code === "ECONNRESET"`
   (Node's `connResetException` shape, produced by `abortIncoming` on
   `_http_server` when an inbound client resets mid-request). In
   `installCrashHandlers()`, for both `uncaughtException` and
   `unhandledRejection`: on match, call
   `warnSilentFallback(err, { feature: "crash-handlers", op: "client-abort" })`
   and **return** (no `Sentry.close`, no `exit`); on non-match, existing
   `reportFatalAndExit` path unchanged.
2. **Re-apply the bump.** `apps/web-platform/package.json` `next` → `~16.4.1`;
   `npx --yes npm@11 install --package-lock-only` in `apps/web-platform/`;
   confirm resolved 16.4.x ≥16.4.1.
3. **Re-add guard coverage.** In `scripts/assert-dependabot-drain.py`: `next`
   into `WATCHED_PACKAGES`, row `("web-platform", "next", 16, "16.4.1")` into
   REQUIRED beside the existing 2026-10-31 batch comment, `("next", 16): "16.4.1"`
   into FLOOR_ANCHORS with the three GHSA cites, `MIN_ROWS`/`MIN_RESOLVED`
   35→36. In `scripts/assert-dependabot-drain.test.sh`: add `next:16:16.4.1` to
   the FLOOR_ANCHORS spec-grep loop, `MIN_ASSERTIONS` 33→34 (fixture already
   synthesizes `next@16.999.999`, so the row resolves in-fixture).
4. **Re-pin the egress minor.** `egress-audit-ingest.test.ts` `/^16\.3\./` →
   `/^16\.4\./` — headers already re-measured identical on 16.4.3 (comment in
   file).
5. **Amend ADR-062** (Deliverable C): record the benign-inbound-abort
   classification in `## Decision` and the rejected alternatives in
   `the `Rejected alternatives:` record in its Deliverable C carve-out.
6. **Verify end-to-end** (implementation-phase repro below), then ship; the e2e
   CI job is the acceptance oracle.

## Implementation Phases

### Phase 1: Reproduce and attribute (failing-proof first)

- Pin `next` to 16.4.3 locally (worktree `npm install next@16.4.3` or edit +
  `npm@11 install`), run the upstream-shaped repro against our dev server:
  start `PORT=3100 NEXT_DIST_DIR=.next/repro npm run dev`, wait for `/login`
  readiness, then run the socket-level repro — POST with `Content-Length`
  body to a middleware-redirected or proxy-handled path and destroy the socket
  mid-response (the upstream `client.mjs` shape: `net.connect` → write request
  → `socket.destroy()` after ~500ms). Expect `⨯ uncaughtException: Error: aborted`,
  `e2e-webserver: exited`, then process death → **confirms H1+H2** on our tree.
- Repeat once against a request that middleware handles with `NextResponse.next()`
  vs. a redirect-returning path to map the trigger surface (upstream says
  only proxy-returned responses trigger; our middleware's redirect exits are
  the likely prod trigger). Capture which route class fires.
- Success criteria: deterministic crash reproduced ≥1× with the signature in
  the dev-server stderr.

### Phase 2: Crash-handler classifier (RED → GREEN)

- Write failing tests in `apps/web-platform/test/crash-handlers.test.ts`
  (RED): benign-abort → no `process.exit`, `warnSilentFallback`-equivalent
  warn capture (assert via the mocked Sentry layer shape the suite already
  uses — see Files to Edit note on mocking `@/server/observability`);
  `Error("aborted")` without `code` → exits; `code: "ECONNRESET"` with a
  different message (`"socket hang up"`) → exits; non-Error reason → exits;
  genuine error → exits (existing arms).
- Implement `isBenignClientAbort` + the two classify-and-return branches in
  `server/crash-handlers.ts` (GREEN).
- Re-run Phase 1 repro against the patched bundle — dev server logs the abort
  (warn mirror) and **keeps running**.
- Success criteria: new tests green, old tests unchanged-green, live repro no
  longer kills the process.

### Phase 3: Re-apply the bump + lockfile

- `apps/web-platform/package.json`: `"next": "~16.3.8"` → `"~16.4.1"`.
- `cd apps/web-platform && npx --yes npm@11 install --package-lock-only`
  (npm@11 parity with CI — `ci.yml` pins it).
- Verify: `node_modules/next/package.json` ≥16.4.1 after `npm ci`, and
  `npm ls next` shows no stragglers.
- Success criteria: lockfile diff is next-scoped (plus its transitive set);
  `npx --yes npm@11 install --package-lock-only --dry-run`-style re-run is
  byte-stable (CI's sync check).

### Phase 4: Guard rows + test arms

- `scripts/assert-dependabot-drain.py` edits per Proposed Solution §3.
- `scripts/assert-dependabot-drain.test.sh` edits per §3.
- Run `bash scripts/assert-dependabot-drain.test.sh` (33→34 assertions) and
  `python3 scripts/assert-dependabot-drain.py` live (36 resolved rows on the
  bumped lockfile).
- Success criteria: both suites green on the bumped tree; `grep` shows the
  next row/anchor/spec present exactly once each.

### Phase 5: Egress pin + ADR + close-out

- `apps/web-platform/test/egress-audit-ingest.test.ts`: `/^16\.3\./` →
  `/^16\.4\./`; run that vitest file.
- Amend `knowledge-base/engineering/architecture/decisions/ADR-062-*.md`
  (`## Decision` Deliverable C carve-out carrying the `Rejected alternatives:` record).
- File the upstream-watch follow-through issue (see Alternative Approaches /
  deferral row) if not already filed at plan time.
- Success criteria: vitest green; ADR diff committed; deferred item has a
  tracking issue number recorded in tasks.md.

### Phase 6: Verification gate

- `npx vitest run test/crash-handlers.test.ts test/egress-audit-ingest.test.ts`
  in `apps/web-platform`.
- `bash scripts/assert-dependabot-drain.test.sh`; `python3 scripts/assert-dependabot-drain.py`.
- If feasible within session bounds: a bounded e2e subset (`npx playwright
  test` with the auth project) to observe `e2e-webserver: exited` absence and
  warn-level abort events; otherwise rely on the CI e2e required check as the
  oracle (the diff is `applicable=true` per the #8450 classifier — the job
  will run).
- Success criteria: e2e green on CI with no `⨯ uncaughtException` / no
  mid-run `e2e-webserver: exited` line.

## Alternative Approaches Considered

| Option | Verdict | Why |
|---|---|---|
| A. Benign-abort classification in `installCrashHandlers` (chosen) | Adopt | Restores stock-Next semantics at the exact layer that converts the upstream log-line into a process death; ~15 lines + tests; also removes the prod DoS surface. |
| B. Patch `next/dist/server/body-streams` (upstream one-liner `p2.on('error', () => {})`) | Rejected | No patch mechanism in repo (no patch-package/postinstall); a postinstall node_modules patch is invisible to review and regen-fragile. Re-evaluation: adopt the upstream fix instead when a released next carries it — see deferral below. |
| C. Restructure `middleware.ts` to never return proxy-produced responses for body-bearing requests | Rejected | Cannot be made airtight: redirects must return responses, and body cloning also fires on the header-modification path (`NextResponse.next({ request: { headers } })` + `proxyClientMaxBodySize`). |
| D. Respawn wrapper around the e2e dev server | Rejected | Masks the defect, adds machinery, fixes nothing in prod. |
| E. Wait for an upstream release containing the fix | Rejected for the bump; **deferred** for the workaround | Advisories are CRITICAL unauthenticated RCEs — cannot wait. Upstream-watch issue is the deferral tracker (filed at plan time — see below). |
| F. Pin `@sentry/nextjs` or rework `withSentryConfig` to dodge the wrapping suspect | Rejected | Upstream repro excludes Sentry; deprecation warnings are unrelated noise. |

**Deferral tracker (filed at plan time):** "next: drop benign-abort
classification when an upstream release fixes the body-streams `_events` wipe
(vercel/next.js #49587)" — re-evaluation criterion: `npm view next versions`
shows a stable release whose changelog/PR list references the body-streams
error-listener fix; then re-run the Phase-1 repro un-patched and, if clean,
revert the classifier to full-fatal semantics (or keep it, if review prefers
defense-in-depth — a second decision point, not a default revert).

## Files to Edit

- `apps/web-platform/server/crash-handlers.ts` — add `isBenignClientAbort` +
  classify-and-return branches in both `process.on` handlers.
- `apps/web-platform/test/crash-handlers.test.ts` — new arms: benign-abort
  uncaughtException/unhandledRejection → no exit + warn capture; near-miss
  signatures (no `code`, wrong message) → still exit. Mock `@/server/observability`
  alongside the existing `@sentry/nextjs` + `@/server/logger` mocks, or assert
  the Sentry-warn shape directly (implementation chooses; the suite's existing
  mock shape is the constraint).
- `apps/web-platform/package.json` — `"next": "~16.3.8"` → `"~16.4.1"`.
- `apps/web-platform/package-lock.json` — regenerated under npm@11.
- `scripts/assert-dependabot-drain.py` — `next` into WATCHED_PACKAGES, REQUIRED
  row, FLOOR_ANCHORS entry, MIN_ROWS/MIN_RESOLVED 35→36.
- `scripts/assert-dependabot-drain.test.sh` — `next:16:16.4.1` spec arm,
  MIN_ASSERTIONS 33→34.
- `apps/web-platform/test/egress-audit-ingest.test.ts` — `^16\.3` → `^16\.4`.
- `knowledge-base/engineering/architecture/decisions/ADR-062-container-memory-cap-and-restart-attribution.md` — Deliverable C amendment + Alternatives row.

## Files to Create

- None. (The follow-up tracking issue is a GitHub object, not a repo file.)

## User-Brand Impact

- **If this lands broken, the user experiences:** two failure shapes — (a)
  over-broad classifier: a real fatal is mirrored as a warning and the process
  keeps serving in a corrupt state on `app.soleur.ai` (masked outage instead of
  a clean supervisor restart); (b) under-broad: status quo — dev/e2e crash and
  prod container restarts on unauthenticated client aborts continue.
- **If this leaks, the user's data is exposed via:** the two CRITICAL
  advisories staying unpatched — unauthenticated RCE on the production Next.js
  server reaches `/dashboard` and every authenticated route's data plane.
- **Brand-survival threshold:** `single-user incident` — one exploited
  unauthenticated RCE request against one user's workspace is existential;
  conversely a masked-fatal regression is fleet-wide (aggregate), so the
  dominant arm governs neither — the unauth-RCE tail is the sharper one.
- **Threshold decision (challengeable):** unauthenticated RCE advisories on the
  production app are single-user-incident class (one breach = existential);
  `aggregate pattern` would understate the breach tail.
- Artifact/vector pairs for `soleur:engineering:review:user-impact-reviewer`:
  (a) classifier in `server/crash-handlers.ts` ↔ masked-fatal outage on
  `app.soleur.ai`; (b) `warnSilentFallback` mirror ↔ Sentry warn-event volume;
  (c) `next` 16.4.3 runtime ↔ the three advisory vectors on authenticated
  routes.
- CPO sign-off required at plan time before `soleur:work` begins (no CPO agent
  on this harness — recorded in decision-challenges.md as pending).

## Observability

```yaml
liveness_signal:
  what: e2e CI job green + `e2e-webserver: exited rc=<n>` absence mid-run; in prod, container restart attribution via Sentry "Server startup" frequency (ADR-062 monitor unchanged)
  cadence: per-PR e2e run; prod continuous
  alert_target: required-check red on the PR; prod container_restart_burst Sentry alert (existing)
  configured_in: .github/workflows/ci.yml e2e job; apps/web-platform/e2e/web-server.sh

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN — benign aborts emit warnSilentFallback via mirrorWarnWithDebounce (level warning, tags feature=crash-handlers, op=client-abort, ≤1 envelope/5min/process; per-abort pino warn carries the burst count); real fatals keep fatal-level capture → close → exit
  fail_loud: mid-run `e2e-webserver: exited rc=` line in the e2e job log; in prod, a genuine fatal still exits 1 and attributes via the existing fatal event

failure_modes:
  - mode: client aborts a proxy-handled, body-bearing request mid-response
    detection: warn-level Sentry event tagged feature=crash-handlers, op=client-abort (grouped; burst readable as event count)
    alert_route: none new — warn-level observation; a burst is DoS-shaped signal for the existing security lens
  - mode: classifier too broad — a non-abort error matches the signature
    detection: signature is exact-pair only (message "aborted" + code ECONNRESET); unit arms pin near-miss rejections (wrong message, missing code, non-Error)
    alert_route: vitest red in `test` job
  - mode: a different exception class still kills the dev server mid-e2e
    detection: `e2e-webserver: exited rc=<n>` line + `⨯ uncaughtException` stderr in job log
    alert_route: required-check red

logs:
  where: dev/e2e — dev-server stderr via Playwright webServer piping; prod — container stdout (pino) → existing log shipper
  retention: CI job logs (Actions retention); prod per existing pipeline

discoverability_test:
  command: grep -n "client-abort" apps/web-platform/server/crash-handlers.ts
  expected_output: client-abort
```

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` (98 issues) bodies for
each planned file (`server/crash-handlers.ts`, `assert-dependabot-drain`,
`egress-audit-ingest`, `web-server.sh`, `middleware.ts`, `package-lock`,
`mock-supabase`): **none match a planned file.** #2591 ("docs(security):
document CSP middleware + route intersection") mentions `middleware.ts`, which
this plan does not edit — acknowledged, no disposition needed.

## Domain Review

**Domains relevant:** Engineering (architecture-adjacent: the crash-handler
contract amendment) — assessed inline; no domain-leader Task tool on this
harness, and no brainstorm document exists for this branch (one-shot path).

- **Engineering:** relevant — the change extends the ADR-062 Deliverable C
  decision surface (which exceptions are fatal). Handled by the in-plan ADR
  amendment task (Phase 5) rather than a separate leader review.
- **Product:** none — no user-facing surface (mechanical UI-surface scan of
  Files to Edit/Create: zero matches against `ui-surface-terms.md`; all paths
  are server/test/script/lockfile).
- **Marketing / Sales / Finance / Legal / Operations / Support:** none —
  dependency bump + server crash semantics.

*Harness note:* domain leaders could not be spawned (no Task tool); sweep ran
as a single LLM pass per `brainstorm-domain-config.md` assessment questions.

## GDPR / Compliance Gate (Phase 2.7 disposition)

Trigger fired via clause (b) — `single-user incident` threshold declared —
plus adjacency to `apps/web-platform/server/`. Inline assessment (no
`soleur:gdpr-gate` agent on this harness): the diff introduces no new
processing activity on personal data — the abort path mirrors the same `err`
object already handled by `reportFatalAndExit`, and `warnSilentFallback` runs
`redactErrorForEmit` + `hashExtraUserId` + the existing `beforeSend` scrubber
(`sentry.server.config.ts` → `scrubSentryEvent`). No Art. 9 surface, no new
lawful-basis question, no Art. 30 trigger beyond what crash attribution already
records. Disposition: no compliance finding; `soleur:gdpr-gate` flagged for
review-time invocation per the expanded-trigger clause.

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-062** (`knowledge-base/engineering/architecture/decisions/ADR-062-container-memory-cap-and-restart-attribution.md`): Deliverable C currently reads capture → `close(2000)` → `process.exit(1)` for `uncaughtException`/`unhandledRejection` unconditionally. This plan adds the first non-fatal class — the Node `connResetException` signature (`Error: aborted` + `code: ECONNRESET`, inbound client abort per vercel/next.js #49587) — which logs `warnSilentFallback` and keeps the process. `## Decision` gets the carve-out carrying a `Rejected alternatives:` paragraph recording the upstream-patch, middleware-restructure, and respawn rejections (ADR-062 has no `## Alternatives Considered` section — the record lands inside Deliverable C). Deliverable of this plan, Phase 5.

### C4 views

- **No C4 impact.** Enumeration per the completeness mandate, checked against
  `diagrams/{model.c4,views.c4,spec.c4}`: (a) external human actors — none new
  (the aborting client is the existing browser-user actor); (b) external
  systems — none new (`sentry` is already modeled; the warn event rides the
  existing `webapp → sentry` edge that already carries fatal crash events);
  (c) containers/data stores — none new or touched; (d) access relationships —
  none change (no new listener, no new credential, no new network edge). The
  `.c4` model files need no edit; `c4-code-syntax`/`c4-render` tests are
  unaffected.

## Guard Contract

### Guard 1 — dependabot-drain floor row for next 16

**Property.** The `next` package's 16.x line in `apps/web-platform/package-lock.json`
can never resolve below 16.4.1 (the three-advisory floor) without the drain
guard going red — a floor expressed by one REQUIRED row, one FLOOR_ANCHOR, one
WATCHED_PACKAGES membership, and the test-file spec-grep arm that pins the
anchor text.

**Assembly.** `scripts/assert-dependabot-drain.py` is the sole chokepoint:
REQUIRED rows → per-manifest resolution against `LOCKS` (5 manifests);
FLOOR_ANCHORS is the second, independent floor the source-grep in
`assert-dependabot-drain.test.sh` pins, so lowering the floor is a two-file,
two-language edit. The fixture `web` tree in the test already synthesizes
`node_modules/next@16.999.999`, so the row resolves in-fixture — a fixture that
dropped it would leave the row `(absent)` and trip MIN_RESOLVED.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | REQUIRED row floor lowered `16.4.1` → `16.4.0` while FLOOR_ANCHORS stays `16.4.1` | RED (anchor-vs-row disagreement / resolved < anchor) |
| 2 | `next` row deleted from REQUIRED (and nothing else) | RED (MIN_ROWS 36 → 35; MIN_RESOLVED 36 → 35) |
| 3 | `("next", 16): "16.4.1"` deleted from FLOOR_ANCHORS only | RED (test.sh spec-grep finds 0 anchors for `next:16:16.4.1`) |
| 4 | `next` added to WATCHED_PACKAGES but no covering REQUIRED row | RED (completeness sweep: watched package with no row) |
| 5 | Fixture `web` list's `("next", 16)` entry removed | RED (row resolves `(absent)` → MIN_RESOLVED shortfall) |
| 6 | MIN_ASSERTIONS stays 33 while the new spec arm lands | PASS is impossible to fake: the floor is a `<` check on `asserted`, and the added arm raises both — verifies the floor tracks the arm count rather than drifting |

### Guard 2 — benign-abort classification is exact-signature only

**Property.** Only Node's inbound `connResetException` shape (`Error`,
`message === "aborted"`, `code === "ECONNRESET"`) is exempted from the
capture→close→exit fatal path; every other throw keeps the fatal contract —
a filter whose dispatch silently widening would convert real fatals into
warn-level noise.

**Assembly.** `server/crash-handlers.ts` `installCrashHandlers()` — the single
process-level chokepoint all `uncaughtException` and `unhandledRejection`
events flow through (registered once, `server/index.ts:83`, before
`app.prepare()`). There is no second classify site; `isBenignClientAbort` is
the sole predicate and `crash-handlers.test.ts` the sole assertion home.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `isBenignClientAbort` body replaced with `return true` | RED (genuine-error arm still asserts exit; also the no-`code`/`socket hang up` arms) |
| 2 | `message === "aborted"` check widened to `includes("abort")` | RED (near-miss arm: `Error("aborted by user")` + `ECONNRESET` must exit — pinned by a same-code-different-message arm carrying the "abort" substring) |
| 3 | `code === "ECONNRESET"` conjunct deleted (message-only match) | RED (arm: `new Error("aborted")` with no `code` must exit) |
| 4 | classify branch moved after `reportFatalAndExit` (unreachable) or deleted | RED (benign arm asserts `exit` NOT called and warn emitted — a deleted branch drives exit and fails both) |
| 5 | test arm mutated to expect exit on the benign signature | RED-vs-design: must stay must-PASS-only-if-correct — the benign arm asserts `exitSpy` NOT called, so flipping the expectation reds the suite against the implementation |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Reproduce the dev-server crash locally with Sentry env set, identify the exact offender (next 16.4.x vs sentry 10.77 interaction)" | Phase 1 (repro — Sentry-env caveat reconciled in Research Reconciliation: upstream mechanism excludes Sentry) + Phase 2 (classifier) | mapped |
| 2 | "Re-apply `\"next\": \"~16.4.1\"` + lockfile regen under npm@11" | Phase 3 | mapped |
| 3 | "Re-add guard rows: (`web-platform`, next, 16, \"16.4.1\") + FLOOR_ANCHOR + WATCHED_PACKAGES entry; MIN_ROWS/MIN_RESOLVED 35→36; test arm \"next:16:16.4.1\"; MIN_ASSERTIONS 33→34" | Phase 4 + Files to Edit (`scripts/assert-dependabot-drain.py`, `.test.sh`) | mapped |
| 4 | "Re-pin `test/egress-audit-ingest.test.ts` minor to ^16\\\\.4 (headers already re-measured on 16.4.3 — identical four-header set)" | Phase 5 + Files to Edit (`apps/web-platform/test/egress-audit-ingest.test.ts`) | mapped |
| 5 | "a plan whose implementation makes the next ~16.4.1 bump e2e-clean" (invocation brief) | Phases 1–2 + 6 (classifier + verification) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `isBenignClientAbort` in `server/crash-handlers.ts` + test arms | "identify the exact offender … and fix the e2e dev-server crash" + "any needed compat shim" | asked (the compat shim is this classifier) |
| `warnSilentFallback` as the non-fatal sink | — | inferred — justification: `cq-silent-fallback-must-mirror-to-sentry` forbids a silent non-fatal path; the warn-level helper is the repo's canonical mirror |
| ADR-062 amendment | — | inferred — justification: plan Phase 2.10 gate (`wg-architecture-decision-is-a-plan-deliverable`); the change extends an existing ADR's Decision |
| Upstream-watch follow-through issue | — | inferred — justification: plan Step-6 deferral-tracking check; the rejected upstream-patch option needs a re-evaluation surface |
| Unauthenticated-abort DoS framing in Problem Statement | — | inferred — justification: same code path runs in prod (`server/index.ts` `dev:false`); omitting it would scope the fix to e2e-only and understate the blast radius |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `scripts` (ADR doc under `knowledge-base/` counts as its own root → 3)
- Planned files: 8 | Estimated changed lines: ~120 (60 per issue estimate + classifier ~40 + ADR ~20)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — none tripped
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `apps/web-platform/package.json` carries `"next": "~16.4.1"` and `apps/web-platform/package-lock.json` resolves `node_modules/next` to a 16.4.x version ≥16.4.1, regenerated under npm@11 (CI lockfile-sync check shape).
- [ ] AC2: `server/crash-handlers.ts` classifies `Error`+`message "aborted"`+`code "ECONNRESET"` as non-fatal for BOTH `uncaughtException` and `unhandledRejection`: warns via `warnSilentFallback` (tags `feature=crash-handlers`, `op=client-abort`), calls neither `Sentry.close` nor `process.exit`; every other shape still takes the capture→close→exit path.
- [ ] AC3: `crash-handlers.test.ts` contains arms pinning both directions — benign signature → no exit + warn; near-misses (`Error("aborted")` no-code, ECONNRESET wrong-message, non-Error, genuine error) → exit — and the whole file is green under `npx vitest run test/crash-handlers.test.ts`.
- [ ] AC4: `scripts/assert-dependabot-drain.py` contains `next` in WATCHED_PACKAGES, the `("web-platform", "next", 16, "16.4.1")` REQUIRED row, `("next", 16): "16.4.1"` in FLOOR_ANCHORS, `MIN_ROWS = 36`, `MIN_RESOLVED = 36`; `.test.sh` contains the `next:16:16.4.1` spec arm and `MIN_ASSERTIONS=34`; both suites green.
- [ ] AC5: `egress-audit-ingest.test.ts` pins `/^16\.4\./` and the file is green under vitest on the bumped lockfile.
- [ ] AC6: Live repro (Phase 1 shape: socket-abort against the dev server on the bumped tree) no longer kills the process — server logs/mirrors the abort and stays up; on the un-patched bumped tree the same repro crashed (verified during Phase 1).
- [ ] AC7: ADR-062 `## Decision` Deliverable C records the benign-abort carve-out and the carve-out's `Rejected alternatives:` paragraph records the rejected options; committed in the same PR.
- [ ] AC8: The upstream-watch tracking issue exists (number recorded in tasks.md) — re-evaluation: adopt an upstream body-streams fix when a stable release carries it.
- [ ] AC9: CI e2e job green on this branch (the #8450 classifier marks a package.json/lockfile diff applicable → the job runs) with no mid-run `e2e-webserver: exited` and no `⨯ uncaughtException` death.

## Test Scenarios

- Given `new Error("aborted")` with `err.code = "ECONNRESET"`, when delivered as an `uncaughtException`, then `process.exit` is NOT called, `Sentry.close` is NOT called, and a warning-level mirror is emitted (unit).
- Given the same error delivered as an `unhandledRejection`, then the same non-fatal outcome (unit).
- Given `new Error("aborted")` with NO `code`, when delivered as `uncaughtException`, then `process.exit(1)` is called (unit).
- Given an `Error` with `code === "ECONNRESET"` and `message === "socket hang up"`, when delivered, then `process.exit(1)` is called (unit).
- Given `new Error("boom")`, when delivered, then the existing capture→close→exit path runs unchanged (unit — covered by existing arms).
- Given a non-Error rejection reason (e.g. `"rejected"`), when delivered as `unhandledRejection`, then `process.exit(1)` is called (unit).
- Given the bumped dev server running, when a client POSTs a body to a proxy-handled path and destroys the socket mid-response, then the server emits the warn mirror and remains serving (integration — Phase 1/Phase 6 live repro).
- Given the bumped lockfile, when `assert-dependabot-drain.py` runs live, then the `next` row resolves ≥16.4.1 and `resolved` count is 36 (integration — run by `scripts/test-all.sh`).
- Given the drain guard, when any mutation-matrix row above is applied to a copy, then the guard or its test goes red (integration — existing mutation-arm conventions in `.test.sh`).

## Success Metrics

- `gh pr checks` e2e = green on the bump branch (deterministic, not retry-lucky — the signature is reproduced-locally-then-fixed, not hoped away).
- `assert-dependabot-drain.py` live run prints `resolved` = 36 with the next row at ≥16.4.1.
- GitHub advisory audit: the three GHSAs are no longer flagged against `apps/web-platform` after merge.
- Zero fatal-level `uncaughtException` events in Sentry matching the benign signature post-deploy (warn-level `op=client-abort` events are the expected residual signal).

## Dependencies & Risks

- **Risk — classifier signature too narrow**: if upstream emits a different benign shape (e.g. `unhandledRejection` with `code: "ECONNRESET"` but message `"socket hang up"`), the crash recurs. Mitigation: Phase 1 repro confirms the observed signature is exactly `aborted`+ECONNRESET; the unhandledRejection arm covers the upstream-documented second shape; if Phase 1 shows a different signature, the predicate widens *only* to the observed superset — never a blanket ECONNRESET exemption.
- **Risk — masked fatal**: an unrelated real error coincidentally carrying the exact pair would be swallowed as a warning. Mitigation: measured at deepen time — app code DOES produce `Error("aborted")` (`server/dsar-export.ts`, 48 abort-signal arms, +4 in `server/dsar-export-co-uploader.ts`) but never assigns `.code`, so the exact-pair requirement still exits on that population; the only masking path is a future `.code = "ECONNRESET"` assignment, which the Guard-2 mutation matrix pins. Near-miss arms pin the boundary.
- **Risk — Sentry volume**: prod abort storms create warn-event volume. Accepted: grouped issue, level warning, and a burst is itself a DoS-attempt signal worth having.
- **Dependency — upstream release**: none required; mitigation is local. The upstream-watch issue tracks re-evaluation.
- **Risk — e2e non-determinism on the bumped tree beyond the abort**: Phase 6 relies on the CI e2e run as oracle; a second, unrelated flake class would re-block the bump and is then a new issue, not a silent pass.

## References & Research

- vercel/next.js #49587 — canonical upstream issue; root cause in `getCloneableBody().finalize()`/`replaceRequestBody` (`_events` copy wiping `'error'` listeners); reproduced on 16.4.2; suggested upstream fix `p2.on('error', () => {})` in `cloneBodyStream` (`packages/next/src/server/body-streams.ts`).
- vercel/next.js #84649 — closed-as-duplicate; documents the `unhandledRejection` variant + "stock next suppresses it" note.
- vercel/next.js #56529 — SSE-disconnect sibling, open.
- This repo: `apps/web-platform/server/crash-handlers.ts`, `server/observability.ts` (`warnSilentFallback`), `server/index.ts:83,156`, `middleware.ts`, `next.config.ts` (`proxyClientMaxBodySize`), `playwright.config.ts`, `e2e/web-server.sh`, `e2e/mock-supabase.ts`, `scripts/assert-dependabot-drain.py`, `scripts/assert-dependabot-drain.test.sh`, `test/egress-audit-ingest.test.ts`, `test/crash-handlers.test.ts`, ADR-062.
- PR #11691 (merged 2026-11-01) — the batch minus next; issue #11772 — this plan's ask.
