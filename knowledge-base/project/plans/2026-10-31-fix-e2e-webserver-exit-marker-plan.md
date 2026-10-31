---
title: "fix(e2e): make Playwright webServer mid-run exit observable and close out #9167"
type: fix
date: 2026-10-31
slug: fix-e2e-webserver-exit-marker
branch: feat-one-shot-9167-e2e-otp-signups
issue: 9167
closes: 9167
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix(e2e): make Playwright webServer mid-run exit observable and close out #9167

## Overview

Issue #9167 attributes ~35 authenticated-suite e2e reds to a dev-Supabase
returning `Signups not allowed for otp`. The audit this plan performed shows
no dev-Supabase exists in the e2e harness: Playwright `page.route` fabricates
that exact error string in `apps/web-platform/e2e/otp-login.e2e.ts`, and the
real cascade in the cited run was the Turbopack font-compile failure already
fixed under #8785. The one residual, evidenced mechanism is a Next dev server
dying mid-run with no exit signal in the log (merge-group run 37435711833).
This plan ships a server-exit marker around the two Playwright `webServer`
commands, self-labels the mock-fabricated error string, and posts the 60/60
post-fix measurement that satisfies the issue's own 30-run reassessment bar.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase / run-log reality | Plan response |
|---|---|---|
| "the e2e job's dev-Supabase returns `Signups not allowed for otp`" | e2e never reaches a dev-Supabase. Authenticated tests use `storageState` cookies + an in-process mock (`e2e/mock-supabase.ts`, `e2e/global-setup.ts`) and `page.route("**/auth/v1/otp*")` intercepts browser-side calls. The exact string is the mock payload at `e2e/otp-login.e2e.ts:139` and appears in green runs (e.g. run 37212574590, 115 passed). | No Supabase config change exists to make. The fix hypothesis is descoped; the log line is self-labeled `[e2e-mock]` instead. |
| "the authenticated fixture never lands" | The fixture is a written `e2e/.auth/user.json` storage-state file plus a minted mock JWT (`global-setup.ts` `mintMockJwt`) — no signup request is ever sent. | Nothing to fix; claim is a misread of the log line. |
| cascade of ~35 reds on run 36449125669 | Attempt-1 log shows `Signups not allowed for otp` twice as `[browser]` console noise (16:24:31/34), then the real signature: `Module not found: Can't resolve '@vercel/turbopack-next/internal/font/google/font'` (16:24:58) — the #8785 font failure, CLOSED 2026-10-05. | None — already fixed upstream; verified by the 60/60 measurement below. |
| residual mechanism | Run 37435711833 (2026-10-05, post-fix): 39 failed / 75 passed; first red `nav-states-shell.e2e.ts:655`, then `net::ERR_CONNECTION_REFUSED` at :3100 for every authenticated test — the Next dev server went away mid-run and nothing logged why. | `e2e/web-server.sh` exit marker (this plan). |
| "Fix-Size: ~10 lines / 1 file" | Actual: ~4 files / ~120 lines including the test that keeps the marker honest. | Reflected in phases and estimates. |

## Problem Statement / Motivation

Two triage cycles and one P1 issue were spent on a log line the test suite
prints itself. That is the cheap half of the defect and is closed by
self-labeling the mock payload. The expensive half is live: when the Next dev
server under Playwright `webServer` exits mid-run, Playwright reports nothing
about it — every authenticated test then fails with bare
`net::ERR_CONNECTION_REFUSED`, and a log with no exit code, no signal, and no
timestamp cannot distinguish OOM-kill from crash from harness teardown. The
issue's own evidence comment names the missing piece: "the e2e job would need
a server-exit marker to say why it went away." Meanwhile the issue has stayed
open solely pending a 30-run post-fix measurement, which this planning pass
ran: **60/60 merge-group `e2e` jobs green since 2026-10-06** (four run-level
failures in the window are all `test-scripts` shard flakes, a different
mechanism, none in `e2e`).

## Proposed Solution

1. **`apps/web-platform/e2e/web-server.sh` (new, ~25 lines).** A thin wrapper:
   spawn the passed command, `wait` on it, and on its exit print
   `e2e-webserver: exited rc=<n> port=<PORT> distdir=<NEXT_DIST_DIR> uptime=<s>`
   to stderr, then exit with the child's code. `128+N` encodes death-by-signal
   (137=SIGKILL/OOM, 143=SIGTERM), so the marker discriminates OOM from crash
   from clean-exit-with-error. Playwright pipes webServer stderr into the job
   log with the entry's `name` prefix, so the marker lands exactly where the
   missing evidence was needed.
2. **`apps/web-platform/playwright.config.ts`.** Point both `webServer`
   entries' `command` at `bash e2e/web-server.sh npm run dev` (webServer `cwd`
   defaults to the config directory) and give each a distinct `name`
   (`e2e-public`, `e2e-auth`) so every piped line — including the marker — is
   attributable to one server. Playwright `webServer` has no onExit hook
   (verified: docs + microsoft/playwright#20343, maintainer answer is
   "make sure the server never dies"), so a command-level wrapper is the
   minimal insertion point.
3. **`apps/web-platform/e2e/otp-login.e2e.ts`.** Tag the fabricated payload's
   `msg`/`message` with `[e2e-mock]` and expand the existing comment to say the
   string is intentionally fabricated and appears in CI logs as browser
   console noise — do not triage it as an environment failure. Safe because
   the app maps on `error.code === "otp_disabled"` (`lib/auth/error-messages.ts`
   `isNoAccountError`), never on `msg`.
4. **`apps/web-platform/test/playwright-web-server-exit-marker.test.ts`
   (new).** Vitest coverage that (a) runs the wrapper against stub commands
   (`true`, `exit 42`, self-`SIGKILL`) asserting rc pass-through and marker
   shape, and (b) text-asserts the config wiring via the `stripComments`
   helper — comments must be stripped before matching so a commented-out
   `command:`/`name:` line cannot satisfy the assertion, the same convention
   `playwright-dev-server-distdir.test.ts` uses for `NEXT_DIST_DIR`
   (`cq-assert-anchor-not-bare-token`).
5. **Issue close-out.** Post the 60/60 measurement as a comment on #9167 and
   carry `Closes #9167` in the PR body.

## Technical Considerations

- Teardown noise is excluded by construction: Playwright's default shutdown is
  a process-group `SIGKILL` (`gracefulShutdown` unset), which kills the
  wrapper and child together — the marker only survives to print when the
  child exits while the wrapper lives, i.e. genuine mid-run death. No green-run
  noise.
- `reuseExistingServer: !process.env.CI` means a locally running dev server
  skips the wrapper entirely; the marker is CI-first, which is where the
  diagnostic gap was.
- `npm run dev` here is the repo's custom esbuild+bundle dev server
  (`package.json` `dev` script), not bare `next dev` — the wrapper is
  command-agnostic (`"$@"`) so it does not care.
- If `npm` exits but a `node` grandchild lingers holding the port, the marker
  still prints npm's rc; port re-use is a non-issue because CI starts fresh
  each run and teardown group-kills.
- NFR impacts: none user-facing — CI-harness instrumentation only.
- **AI-generated files:** `e2e/web-server.sh` and
  `test/playwright-web-server-exit-marker.test.ts` are new; shell exit/signal
  semantics under `set -u` and Playwright teardown timing warrant a closer
  `soleur:review` pass.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing — worst case is a red `e2e` CI check on PRs, invisible to end users.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the change adds a shell wrapper and a test-payload string in CI-only code; no data path is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** CI-harness instrumentation with no shipped surface; a landed-broken outcome is a blocked merge queue, not a user-visible defect, so `none` rather than `single-user incident`.

## Observability

The change *is* an observability fix; the section declares the marker's own
signal contract.

```yaml
liveness_signal:
  what: "`e2e-webserver: exited rc=<n>` line emitted by the webServer wrapper when a dev server exits"
  cadence: "per e2e run (silent in green runs — teardown group-SIGKILL kills wrapper and child together)"
  alert_target: "the `e2e` required check's red status on the PR / merge-group run"
  configured_in: "apps/web-platform/e2e/web-server.sh + apps/web-platform/playwright.config.ts webServer entries"

error_reporting:
  destination: "GitHub Actions `e2e` job log ([e2e-public] / [e2e-auth] prefixes)"
  fail_loud: "`e2e-webserver: exited rc=` line in the job log preceding ERR_CONNECTION_REFUSED test failures"

failure_modes:
  - mode: "Next dev server OOM-killed or crashed mid-run"
    detection: "`e2e-webserver: exited rc=137` (or other 128+N signal code / non-zero rc) in the [e2e-auth] or [e2e-public] log stream, timestamped by the job log"
    alert_route: "e2e check failure on the run; triage reads the marker instead of guessing"
  - mode: "dev server never becomes ready (compile failure class, e.g. #8785)"
    detection: "existing url: readiness poll timeout at 180s (unchanged)"
    alert_route: "e2e check failure at the webServer startup phase"
  - mode: "wrapper itself regressing (marker absent on genuine mid-run death)"
    detection: "vitest test/playwright-web-server-exit-marker.test.ts rc/shape assertions"
    alert_route: "test-webplat check failure"

logs:
  where: "GitHub Actions `e2e` job log"
  retention: "GitHub run-log retention (~90 days); playwright-report artifact retained 7 days on failure"

discoverability_test:
  # `--selftest` runs the wrapper's real spawn+wait+marker machinery against
  # `true` and emits the marker on stdout (Playwright piping needs stderr —
  # webServer `stdout` defaults to `ignore`; Check 10 reads stdout and its
  # shell-metachar reject bans `2>&1`). Both constraints are satisfied by the
  # flag, not by a second script.
  command: bash apps/web-platform/e2e/web-server.sh --selftest
  expected_output: "exited rc=0"
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "needs the e2e Supabase config audited" | Research Reconciliation table + Phase 1 audit findings (performed at plan time) | mapped |
| 2 | "the e2e env's Supabase OTP-signup toggle or fixture bootstrap" | — | descoped — justification: no dev-Supabase or OTP toggle exists in the e2e harness; the string is `page.route`-fabricated (`e2e/otp-login.e2e.ts`) and the real cascade was #8785, already CLOSED |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `e2e/web-server.sh` + playwright.config.ts wiring | "the e2e job would need a server-exit marker to say why it went away" [#9167 evidence comment] | asked |
| `name:` per webServer entry | "the e2e job would need a server-exit marker to say why it went away" [#9167 evidence comment] — attribution is part of "why it went away" | asked |
| `[e2e-mock]` tag on mock `msg`/`message` | — | inferred — justification: the unlabeled fabricated string caused this issue plus two prior mis-triages (#9115/#9155 run reads); a self-labeling line prevents the third recurrence |
| `test/playwright-web-server-exit-marker.test.ts` | — | inferred — justification: a diagnostic mechanism with no test rots silently; the config-text assertion mirrors the existing `playwright-dev-server-distdir.test.ts` contract |
| #9167 measurement comment + `Closes #9167` | "Leaving this open for the 30-run reassessment" [#9167 evidence comment] — the bar is now measured at 60/60 | asked |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 4 | Estimated changed lines: ~120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None — queried open `code-review` issues against `playwright.config.ts`, `e2e/otp-login.e2e.ts`, `e2e/mock-supabase.ts`, `e2e/global-setup.ts`, `lib/auth/useOtpFlow.ts`; zero matches.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — sequential-fallback; plugin subagents unavailable on this harness)
**Assessment:** CTO lens, executed inline. Small blast radius: a command-level
wrapper and a config rewiring in the e2e harness only — no production code, no
workflow edits, no new CI job. The one architectural point worth stating is
that the fix lives at the process layer (exit status propagation) rather than
the test layer (a liveness fixture), which is correct: Playwright owns the
webServer lifecycle, so only a process wrapper sees the exit. Risk is low:
worst case is the wrapper breaking server startup, which the existing 180s
url-readiness poll + this PR's own `e2e` check surface immediately. Complexity
concern: none — ~25 lines of bash with `set -uo pipefail`, argument guard, and
a single `wait`.

**Brainstorm-recommended specialists:** none (no brainstorm ran — pipeline entry via `soleur:one-shot`).

## Acceptance Criteria

- [ ] `apps/web-platform/e2e/web-server.sh` exists, is executable, uses `#!/usr/bin/env bash` + `set -uo pipefail`, and `bash apps/web-platform/e2e/web-server.sh bash -c 'exit 42'` prints `e2e-webserver: exited rc=42` (with `port=`/`distdir=`/`uptime=` fields) to stderr and exits 42; `bash apps/web-platform/e2e/web-server.sh true` prints `exited rc=0` and exits 0.
- [ ] Both `webServer` entries in `apps/web-platform/playwright.config.ts` run `bash e2e/web-server.sh npm run dev` and declare distinct `name:` values (`e2e-public`, `e2e-auth`); `NEXT_DIST_DIR`, `url:` readiness polls, `timeout: 180_000`, and `env:` blocks are unchanged; `apps/web-platform/test/playwright-dev-server-distdir.test.ts` still passes.
- [ ] `apps/web-platform/test/playwright-web-server-exit-marker.test.ts` asserts: rc pass-through (0, 42), signal-death shape (self-SIGKILL → `rc=137`), marker fields present, and config-text wiring on a comment-stripped read (each webServer entry's command references `e2e/web-server.sh` and sets `name:`).
- [ ] The `otp_disabled` mock in `apps/web-platform/e2e/otp-login.e2e.ts` carries `[e2e-mock]` in `msg`/`message` and a comment stating the string is intentionally fabricated (CI-log noise, not an environment signal); the otp-disabled test still maps via `error.code` and passes.
- [ ] The `e2e` CI check is green on this PR (wrapper does not break server startup) and its log shows `[e2e-public]` / `[e2e-auth]` prefixes.
- [ ] A comment is posted to #9167 carrying the measured 60/60 merge-group `e2e` outcome since 2026-10-06, the run-37435711833 `ERR_CONNECTION_REFUSED` signature, and the marker's design; the PR body contains `Closes #9167`.

## Test Scenarios

- Given the wrapper runs `bash -c 'exit 42'`, when the child exits, then stderr contains `e2e-webserver: exited rc=42 port=` and the wrapper exits 42 — `unit`
- Given the wrapper runs `bash -c 'kill -9 $$'`, when the child is SIGKILLed, then the marker reports `rc=137` (128+9), the OOM-death signature — `unit`
- Given the wrapper runs `true`, when it exits, then the marker reports `rc=0` and the wrapper exits 0 — `unit`
- Given the wrapper runs `--selftest`, when it exits, then stdout (not stderr) carries `e2e-webserver: exited rc=0` and it exits 0 — `unit`
- Given the wrapper is invoked with no command, when it starts, then it prints usage and exits 2 — `unit`
- Given `playwright.config.ts`, when its `webServer:` block is text-scanned, then every entry's `command:` references `e2e/web-server.sh` and every entry declares a unique `name:` — `unit`
- Given the otp-login e2e suite runs in the `e2e` job, when the otp-disabled test executes, then it passes and the `[browser] [auth] Supabase error:` log line contains `[e2e-mock]` — `e2e` — `pyramid-justified: the discrimination property only exists on the real browser-console → CI-log path; no unit layer can observe it`
- Given merge-group `e2e` job history since 2026-10-06, when per-job conclusions are listed (`gh run list --workflow ci.yml --event merge_group` + `gh run view <id> --json jobs`), then 60/60 are `success` — verified at plan time; re-verified before posting the #9167 comment — `integration`

## Implementation Phases

### Phase 1 — Server-exit marker

1. Create `apps/web-platform/e2e/web-server.sh` per Proposed Solution §1:
   `#!/usr/bin/env bash`, `set -uo pipefail`, usage guard (`$# -lt 1` → usage +
   exit 2), `start_ts=$(date +%s)`, `"$@" &`, `child=$!`, `wait "$child"`,
   `rc=$?`, `elapsed=$(( $(date +%s) - start_ts ))`,
   `echo "e2e-webserver: exited rc=${rc} port=${PORT:-?} distdir=${NEXT_DIST_DIR:-?} uptime=${elapsed}s" >&2`,
   `exit "$rc"`. Header comment names the mechanism and cites #9167 +
   run 37435711833 (grep-stable anchors, not line numbers).
2. `chmod +x` the script.
3. Edit `apps/web-platform/playwright.config.ts`: both `webServer` entries get
   `command: "bash e2e/web-server.sh npm run dev"` and `name: "e2e-public"` /
   `name: "e2e-auth"` respectively; extend the existing readiness comment with
   one line noting the marker contract.

### Phase 2 — Marker test coverage

4. Create `apps/web-platform/test/playwright-web-server-exit-marker.test.ts`
   (vitest, `spawnSync`): rc pass-through cases (0, 42, 137 via `kill -9 $$`),
   usage-guard case (rc 2), marker-field presence
   (`port=3101` with `env: { PORT: "3101" }`), and the config-text wiring
   assertions per Proposed Solution §4.
5. Run `npx vitest run test/playwright-web-server-exit-marker.test.ts test/playwright-dev-server-distdir.test.ts` in `apps/web-platform` — both green.

### Phase 3 — Mock log self-labeling

6. Edit `apps/web-platform/e2e/otp-login.e2e.ts`: tag `msg`/`message` with
   `[e2e-mock]` and extend the comment per Proposed Solution §3.

### Phase 4 — Issue close-out

7. Re-run the merge-group `e2e` measurement (window since 2026-10-06), then
   `gh issue comment 9167` with the count, the falsified-premise summary, the
   run-37435711833 signature, and the marker design.
8. PR body: `Closes #9167`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6 — filled above.
- Do NOT "fix" a dev-Supabase OTP toggle: none exists in the e2e path; that is the falsified premise this plan corrects.
- Do NOT remove `[e2e-mock]` thinking it breaks gotrue fidelity — the app's contract is `error.code`, and the tag is what makes the CI log line self-labeling.
- Do NOT add `gracefulShutdown` to the webServer entries — group-SIGKILL at teardown is what keeps the marker silent on green runs.
- The marker's absence in green logs is the intended behavior, not a bug — it only prints on mid-run child exit.
- `useOtpFlow.ts` `console.error` stays untouched: it is correct app code; the fix is at the mock payload it logs, not the logger.
- The four `test-scripts` shard failures observed in the measurement window are a different mechanism (not `e2e`, not this issue) — do not fold them in.

## Context

- Issue: #9167 (OPEN, p1-high, type/bug, domain/engineering)
- Cited evidence run: 36449125669 — its attempt-1 `e2e` log shows the real cascade (`Module not found: '@vercel/turbopack-next/internal/font/google/font'`), the `Signups not allowed` lines being `[browser]` console noise 27s earlier.
- Sibling flakes already resolved: #8785 (font compile, CLOSED — fixed by PR #9523 font vendoring), #9170 (`role=status` strict-mode collision, CLOSED).
- Residual signature (one occurrence): run 37435711833, `ERR_CONNECTION_REFUSED` at :3100 — the case the marker exists to diagnose.
- Collision pre-check: `collision-precheck.sh 9167` → PR #11738 is this pipeline's own draft (same branch); three `test-all.sh` processes belong to an unrelated sibling worktree — no foreign work on this issue.
- Playwright maintainer position on mid-run webServer death (microsoft/playwright#20343): no built-in reporting; `stdout`/`stderr: pipe` carries output only.
- Prior art for config-text contract tests: `apps/web-platform/test/playwright-dev-server-distdir.test.ts` (comment-stripped text assertions on `playwright.config.ts`).

## MVP

### apps/web-platform/e2e/web-server.sh

```bash
#!/usr/bin/env bash
# Playwright webServer wrapper: makes a mid-run dev-server exit observable in
# the CI job log (#9167). Playwright pipes webServer stderr but never reports
# the child's exit status — a mid-run death reads as bare
# net::ERR_CONNECTION_REFUSED (measured: merge-group run 37435711833).
set -uo pipefail

# --selftest: run the real spawn+wait+marker path against `true`, marker on
# stdout. The production path emits on stderr — Playwright's webServer pipes
# stderr by default while `stdout` defaults to `ignore` — but a stdout probe
# is what an unauthenticated local check can read.
marker_fd=2
if [[ "${1:-}" == "--selftest" ]]; then
  marker_fd=1
  set -- true
fi

if [[ $# -lt 1 ]]; then
  echo "usage: web-server.sh [--selftest] <command> [args...]" >&2
  exit 2
fi

start_ts=$(date +%s)
"$@" &
child=$!
wait "$child"
rc=$?
elapsed=$(( $(date +%s) - start_ts ))
# rc is 128+N on death-by-signal N (137=SIGKILL e.g. OOM, 143=SIGTERM).
echo "e2e-webserver: exited rc=${rc} port=${PORT:-?} distdir=${NEXT_DIST_DIR:-?} uptime=${elapsed}s" >&"$marker_fd"
exit "$rc"
```

### apps/web-platform/playwright.config.ts (webServer entries, abbreviated)

```ts
    {
      name: "e2e-public",
      command: `bash e2e/web-server.sh npm run dev`,
      url: `http://localhost:${PUBLIC_PORT}/login`,
      // ... unchanged fields
    },
    {
      name: "e2e-auth",
      command: `bash e2e/web-server.sh npm run dev`,
      url: `http://localhost:${AUTH_PORT}/login`,
      // ... unchanged fields
    },
```

### apps/web-platform/e2e/otp-login.e2e.ts (mock payload, abbreviated)

```ts
    // Mock Supabase OTP endpoint to return otp_disabled. The [e2e-mock] tag
    // makes the fabricated error self-labeling in CI logs — the unlabeled
    // string was twice triaged as a real environment failure (#9167). The app
    // maps on error.code, never msg, so the tag changes nothing the test asserts.
    await page.route("**/auth/v1/otp*", (route) =>
      route.fulfill({
        status: 400,
        contentType: "application/json",
        body: JSON.stringify({
          code: "otp_disabled",
          error_code: "otp_disabled",
          msg: "[e2e-mock] Signups not allowed for otp",
          message: "[e2e-mock] Signups not allowed for otp",
        }),
      }),
    );
```

## Research Insights

**Relevant file paths.**

- `apps/web-platform/playwright.config.ts` — two `webServer` entries (`npm run dev`, ports 3099/3100, `url:` readiness, 180s, `NEXT_DIST_DIR` split, `SUPABASE_URL` → mock).
- `apps/web-platform/e2e/mock-supabase.ts` + `e2e/global-setup.ts` — in-process mock Supabase (:54399) + `mintMockJwt` + `e2e/.auth/user.json` storage state; no real signup anywhere.
- `apps/web-platform/e2e/otp-login.e2e.ts` — `page.route("**/auth/v1/otp*")`; the `otp_disabled` mock fabricates `msg: "Signups not allowed for otp"`.
- `apps/web-platform/lib/auth/useOtpFlow.ts` — `console.error("[auth] Supabase error:", error.message)`; logs whatever msg arrives, mock or real.
- `apps/web-platform/lib/auth/error-messages.ts` — `isNoAccountError` keys on `error.code === "otp_disabled"` (typed contract, test-pinned) — `msg` is never parsed.
- `apps/web-platform/test/playwright-dev-server-distdir.test.ts` — the comment-stripped config-text contract test this plan mirrors.
- `.github/workflows/ci.yml` `e2e:` job — `npx playwright test`, `timeout-minutes: 20`, upload-artifact on failure.

**Applicable institutional learnings.**

- `2026-10-05 fix-ci-flakes-pipefail` plan's own Phase 0.6: "#9167's 'Signups not allowed for otp' is a log line the test fabricates itself… the real cascade is the dev-server font compile error." Confirmed independently here from the raw attempt-1 log.
- `2026-09-25-the-flake-was-sigpipe-at-4kib…`: log-line-driven root-cause attribution must be checked against what produced the line, not what the line says.
- `cq-assert-anchor-not-bare-token` + the distdir test's own header: config-text assertions must strip comments or a commented-out line satisfies them — the new test follows the same `stripComments` helper pattern.

**Premise Validation (Phase 0.6).** Checked: #9167 OPEN (not resolved); PRs #9115/#9155 both MERGED (observing runs only, not blockers); cited run 36449125669 attempt-1 log read directly — `Signups not allowed for otp` is `[browser]` console noise from the mock, real failure is the font `Module not found` signature; #8785 CLOSED; mock-supabase/global-setup/playwright.config all present on `origin/main`. Stale/wrong: the issue's premise (dev-Supabase env failure) and its proposed fix (OTP toggle) — both falsified. ADR corpus: no ADR covers e2e webServer lifecycle; the proposed mechanism does not sit in any rejected-alternatives table. Issue-comment direction (server-exit marker + 30-run bar) held and is now satisfied (60/60).

**Property List (Phase 0.6b).**

- P1 — The e2e suite must not cascade-fail with an undiagnosable signature when a dev server dies mid-run. *(Existing coverage: none — Playwright reports nothing on mid-run exit.)*
- P2 — A log line fabricated by the test suite must be identifiable as fabricated. *(Coverage: none — currently byte-identical to a real gotrue error.)*
- P3 — The issue's hold-open condition (30-run post-font-fix measurement) must be answered. *(Coverage: none — needed a run of the measurement, done here: 60/60.)*

**Cut List (Phase 0.6b).**

- Supabase OTP-signup toggle / fixture bootstrap change → P-nothing: the mechanism the issue proposes operates on a component that does not exist in the e2e path (mock-server architecture). Cut.
- Playwright-side liveness fixture / per-test server health probe → P1 partially but adds a polling layer; the process-layer marker covers the same property at ~25 lines with zero new machinery. Cut.
- `dmesg`/OOM-scrubbing inside the wrapper → P1 nicety; container `dmesg` access is unreliable and `rc=137` already discriminates signal-death. Cut.

**External research.** Playwright `webServer` docs verified: options are `command`, `cwd` (defaults to config dir), `env`, `gracefulShutdown` (process-group kill at teardown), `name` (log prefix), `url`, `stdout`/`stderr` — no exit hook. microsoft/playwright#20343: mid-run server death → `ERR_CONNECTION_REFUSED` cascade; maintainer: "make sure the server never dies."

**Related issues/PRs.** #9167 (this), #8785 (font cascade, CLOSED), #9170 (`role=status` strict-mode collision), #9523/#9525 (sibling e2e work referenced in #9167 comments), run 37435711833 (residual signature), PR #11738 (this pipeline's draft).

**CLAUDE.md conventions.** `#!/usr/bin/env bash` + `set -uo pipefail`; kebab-case filenames; symbol anchors not line numbers; `2>&1` for log-capturing diagnostics; test files in `apps/web-platform/test/` (vitest) — all applied.

**Functional overlap (Phase 1.5b, inline):** no community artifact covers a repo-local Playwright-webServer wrapper; zero results, continued silently.

## References

- Related issue: #9167 — `gh issue view 9167 --comments` (evidence chain)
- Playwright webServer docs: [test-webserver](https://playwright.dev/docs/test-webserver)
- microsoft/playwright#20343 — mid-run webServer death → ERR_CONNECTION_REFUSED
