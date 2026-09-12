---
name: qa
description: "This skill should be used when running functional QA before merge."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. Slash `/qa` names the skill; it is not a nested tool_use. **Claude Code:** Skill tool (`soleur:qa`). Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

<!-- lifecycle-handoff-protocol:start -->
**Lifecycle handoff (standalone `/qa`):** When no parent orchestrator (`one-shot`, `work`) owns the pipeline, invoke `/compound` then `/ship` after the QA report — do not end at the report. A PASS is a checkpoint, not completion. If a recorded operator ruling already authorizes shipping (a scope ruling in `session-state.md`, an explicit instruction), proceed under `wg-verified-work-ships-without-asking` rather than pausing to re-confirm — held scope that was never implemented has no files to carry along and is not a reason to halt.
<!-- lifecycle-handoff-protocol:end -->

# Functional QA

Verify that features actually work before merge -- not just that pages render, but that forms submit correctly, external services receive the right data, and data integrity holds across system boundaries.

**Scope boundary with `/test-browser`:** This skill verifies functional correctness (user flows + external service state). `/test-browser` verifies visual rendering, layout regressions, and console errors. They coexist in the pipeline.

## Prerequisites

- Local development server running OR a `dev` script in the project's `package.json` (auto-started if not running)
- Playwright MCP available (for browser scenarios)
- Doppler CLI installed and configured (for API verification scenarios)

## Usage

**Claude:** Skill tool. **Grok:** Read this SKILL.md in this process (`/qa`); slash names the skill.

```bash
skill: soleur:qa, args: "<plan_file_path>"   # Claude Skill tool
/qa <plan_file_path>                         # Grok slash (then Read this SKILL.md)
```

The skill reads the plan file's `## Test Scenarios` section and executes each scenario.

## Workflow

### Step 1: Read Plan and Extract Test Scenarios

Read the plan file passed as `$ARGUMENTS`. Find the `## Test Scenarios` section.

**If no Test Scenarios section exists:** Output "No test scenarios found in plan — skipping QA" and stop. Do not block the pipeline.

**If Test Scenarios section is empty:** Same as above — warn and skip.

**If Test Scenarios contains only Given/When/Then prose with no `Browser:`, `API verify:`, or `Cleanup:` prefixed steps:** Output "Test Scenarios are integration-level Given/When/Then prose (no executable Browser:/API verify: steps) — covered by unit test suite + manual Phase 6 cross-check. Skipping automated QA." and stop. Do not start the dev server. This case is common for plans whose QA gate is explicitly manual (e.g., requires a real Anthropic key + live Supabase apply); a dev-server smoke would not add coverage beyond what the typecheck + unit suite already validate. Never block the pipeline on a confirmation prompt for the dev server in a test environment — auto-skip silently.

### Step 1.5: Ensure Dev Server is Running

Before executing any browser scenarios, check whether the dev server is reachable. If not, attempt to start it automatically.

1. **Check if already running:** `curl -sf --max-time 3 http://localhost:3000/ >/dev/null 2>&1`. If reachable, skip to Step 2 — no action needed. Record that the server was NOT started by QA (so cleanup skips it).

2. **Detect the dev command:** Read `apps/web-platform/package.json` and extract the `scripts.dev` field. If no `dev` script exists, warn: "No dev script found in package.json — cannot auto-start server. Skipping browser scenarios." Continue to API verification steps (do not block the pipeline).

3. **Start the server:** Change to the `apps/web-platform/` directory first (the dev command must run from the app root). Check if Doppler is available (`command -v doppler`). If available, start via `doppler run -p soleur -c dev -- <dev-command> > "$QA_LOG" 2>&1 &` (after `QA_LOG=$(mktemp -t qa-dev-server.XXXXXXXX.log)`). If Doppler is unavailable, start via `<dev-command> > "$QA_LOG" 2>&1 &`. Record the background PID **and echo `QA_LOG=$QA_LOG`** — a later Bash call does not inherit the variable, so the path must be recoverable from the transcript. A fixed name would collide with any concurrent QA session.

4. **Poll for readiness (30s timeout):** Poll `http://localhost:3000/` until it responds or 30 seconds have elapsed, whichever comes first. If the server responds, proceed to Step 2. If the timeout elapses:
   - Kill the background process by PID
   - Include the last 20 lines of `"$QA_LOG"` in the failure report
   - Report: "Dev server failed to start within 30s. See server output above."
   - Continue to API verification steps (do not block the pipeline)

   - When `doppler run` starts the dev server but Supabase env vars (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) are missing from the Doppler config, the server starts but crashes on first request. Check the server log for "Your project's URL and Key are required" before declaring the server ready.

### Step 2: Detect Environment

Determine the Doppler config to use:

```bash
# Check if DEPLOY_URL is set (indicates production context)
echo "${DEPLOY_URL:-not_set}"
```

- If `DEPLOY_URL` is set: use Doppler config `prd`
- If `DEPLOY_URL` is not set: use Doppler config `dev`

Store the config name for use in subsequent `doppler` commands.

### Step 2.6: Structural-UI Visual-Regression Gate (#4834 / ADR-049)

This is the gate's semantic home. Run it when the diff (`git diff --name-only origin/main...HEAD` — the branch-vs-main merge-base diff; do NOT use `origin/<branch>...HEAD`, which only sees unpushed commits and returns 0 files once the branch is pushed, silently skipping the gate) touches `apps/web-platform/app/(dashboard)/**`, `apps/web-platform/components/dashboard/**`, or any `layout.tsx`. Skip silently otherwise.

**Why this exists:** jsdom (vitest) renders no CSS, so `md:w-14` / `hidden md:block` / `flex-wrap` / `display:none` regressions ship green through the unit suite (the #4810 class — top-level chrome leaking into drilled routes; a collapsed rail with no icon-only form). The gate renders real CSS in real headless Chromium.

**Deterministic layer (BLOCKING).** Run the committed `nav-states-*.e2e.ts` spec in the existing `authenticated` Playwright project — real headless Chromium + real Next.js SSR seeded by the **offline mock-Supabase storageState** (`e2e/global-setup.ts` + `e2e/helpers/supabase-mocks.ts`). Zero credentials; NO `dev-signin`; never point at a live origin (CLO: synthetic fixtures only).

**Browser-readiness preflight (unsupported-host guard — do this FIRST).** On a host newer than the pinned Playwright officially supports (e.g. Ubuntu 26.04 vs the `apps/web-platform` `@playwright/test` pin), a plain `playwright install` fails with `does not support chromium ... on <os>` and every test then dies at `browserType.launch: Executable doesn't exist` **before any navigation** — the false-fail that repeatedly costs a QA session its whole run. Recover automatically by retrying the install with the host-platform override, which pulls the nearest supported fallback build (verified `ubuntu26.04-x64` → `ubuntu24.04-x64`; once the fallback build is in cache the launcher resolves it at runtime with NO override, so the override stays out of the run command and can never leak onto a supported host like CI's Jammy container):

```bash
cd apps/web-platform
npx playwright install chromium >"$(mktemp -t qa-pw-install.XXXXXXXX.log)" 2>&1 \
  || PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64 npx playwright install chromium
```

If BOTH the plain install and the override install fail (a genuinely unsupported host with no fallback build), do NOT run the gate and do NOT spend reasoning re-deriving whether it is a regression: this is **INFRA-BLOCKED**, not a code failure. Record in the QA report — "Step 2.6 nav-states gate INFRA-BLOCKED locally (Playwright browser uninstallable on <os>); CI's containerized `e2e` job (`mcr.microsoft.com/playwright:v1.58.2-jammy`) is the authoritative gate per #5009" — and proceed. Never block the pipeline on this.

Then run the gate (no override — the runtime resolves the installed build):

### Preflight: verify the plugin install before any snapshot

The redactor is reached through `${CLAUDE_PLUGIN_ROOT}`. An ambient value pointing at a
directory that is not a Soleur install would resolve to a path that does not exist — or, worse,
to one an attacker chose. Verify plugin IDENTITY and halt if it does not hold (ADR-179 decision 2);
a `test -f` on the script alone is a shape check and was measured bypassable.

```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
  || { echo "SOLEUR_SNAPSHOT_HALT reason=plugin-root-unverified root=[${CLAUDE_PLUGIN_ROOT}]" >&2
       echo "  Cannot locate the snapshot redactor, so no accessibility snapshot may be taken here." >&2
       echo "  Root EMPTY: no Soleur plugin is loaded in this session. Install it and start a NEW session." >&2
       echo "  Root set but wrong: a repo checkout is not an install. Run 'claude plugin update soleur', then RESTART Claude Code." >&2
       echo "  Nothing has been captured yet, so nothing has leaked." >&2
       exit 2; }
```

```bash
cd apps/web-platform && ./node_modules/.bin/playwright test nav-states --project=authenticated --reporter=list
```

A non-zero exit FAILS this QA run. The assertions read invariants jsdom cannot: drilled routes hide the wordmark + ThemeToggle; the collapsed rail is icon-only with no horizontal overflow; the workspace-identity band is visible (with org + repo content) in every drill state × viewport.

**Discriminate a real fail from an env flake.** If the run exits non-zero, apply the #5009 discriminator (see Notes): untouched-test + failure at `page.goto`/browser-close (before any assertion) + the surface the diff actually changed still passes = pre-existing local env flake → record and defer to CI, do not "fix" unrelated tests. A launch-time `Executable doesn't exist` failure means the preflight above was skipped or its override install also failed — treat as INFRA-BLOCKED, not a regression.

**Advisory vision layer (NON-BLOCKING).** Optionally drive Playwright MCP over the same routes and screenshot each, then run a vision pass for anything the deterministic assertions miss (spacing, color, truncation). This is informational only — headed MCP cannot run in autonomous `/work`/CI, so it never blocks the merge. Surface findings as notes in the QA report.

### Step 3: Execute Test Scenarios

For each test scenario in the plan, execute the steps it describes. Scenarios contain three possible step types, identified by their prefix:

- **Browser:** steps — Execute via Playwright MCP tools (`browser_navigate`, `browser_fill_form`, `browser_click`, `browser_snapshot`, `browser_take_screenshot`)

**Credential safety on the Playwright-MCP path (#7947).** An accessibility
snapshot serializes the **value** of input fields, including a value the agent
never typed — a password manager's autofill, a static `value=`, or a
generated-credential panel.

There is **no runtime guard on the Playwright-MCP path.** The PreToolUse
interceptor covers the `agent-browser` Bash path only (#7980), and
`@playwright/mcp`'s `--secrets` option masks only values named in advance, so it
cannot reach a value the agent never supplied. Do not read the redactor as
covering this path: an MCP tool result is not a shell stream and cannot be piped
through a script.

On a page carrying a password or credential field:

- pass `filename:` to `browser_snapshot` so the tree is written to a file
  instead of returned into the transcript, then filter that file and shred it —
  `python3 "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/redact-a11y-snapshot.py" < FILE && shred -u FILE`;
- on a page **displaying** a credential, capture neither. A screenshot is safe
  for a `type=password` field and renders a readonly `type=text` credential
  panel in clear, exactly as the snapshot does (measured).

- **API verify:** steps — Execute the exact `doppler run` + `curl` command from the scenario. Compare the output against the expected value stated in the scenario.
- **Cleanup:** steps — Execute cleanup commands to remove test data from external services. Run these regardless of whether the scenario passed or failed.

**Execution order for each scenario:**

1. Execute **Browser** steps (if present)
   - Use Playwright MCP tools to navigate, fill forms, submit, and verify UI state
   - Capture a screenshot after each significant action using `browser_take_screenshot`
   - When in a worktree, always pass absolute paths for screenshot filenames
   - If Playwright MCP is unavailable, warn "Playwright MCP unavailable — skipping browser steps" and continue to API verification
   - If `browser_navigate` errors with `Target page, context or browser has been closed`, do NOT retry the same call. Recycle the context: call `browser_close` first (it returns "No open tabs" if already closed — safe), then retry `browser_navigate`. Stale page state can outlive a previous session.
2. Wait 3 seconds for eventual consistency (if the scenario has both Browser and API steps)
3. Execute **API verify** steps (if present)
   - Run the exact command from the scenario via the Bash tool
   - Compare the command output against the expected value
   - If the command fails or output doesn't match, retry up to 3 times (waiting a few seconds between retries) before marking as failed
   - If a `doppler secrets get` fails (secret not found), warn "Doppler secret unavailable — skipping API verification" and skip this step
4. Execute **Cleanup** steps (if present)
   - Run cleanup commands regardless of pass/fail
   - Cleanup failures produce warnings but do not mark the scenario as failed

**Sharp edges for API verification:**

- When verifying Sentry API events, use `statsPeriod=24h` (not `1h` — Sentry only accepts `24h` and `14d`). For EU-region DSNs (`ingest.de.sentry.io`), query `de.sentry.io/api/0/` (not `sentry.io/api/0/`).

**Record the result** for each scenario: PASS or FAIL with evidence (screenshots, API response output, error messages).

### Step 4: Generate Report

After all scenarios complete, output a report in this format:

```markdown
## QA Report

**Plan:** <plan file path>
**Environment:** <dev or prd>
**Result:** <PASS (N/N scenarios passed) or FAIL (N/N scenarios passed)>

### Scenario 1: <scenario description> ✅ or ❌

**Browser:** <what was done, result>
**API:** <command executed, expected vs actual>
**Evidence:** <screenshot filenames>

### Scenario 2: ...
```

### Step 5: Pass/Fail Gate

- If **all scenarios passed**: Output the report and continue. The pipeline proceeds to the next step.
- If **any scenario failed**: Output the report with detailed failure information (expected vs actual values, screenshot of failure state). Output "QA FAILED — fix the issues above and re-run QA."

After outputting the result (pass or fail), always proceed to Step 5.5 for cleanup before returning.

### Step 5.5: Cleanup Dev Server

If the dev server was started in Step 1.5 (a background PID was recorded), kill the process by PID, remove `$QA_LOG` (the path echoed when the server started), and report: "Stopped auto-started dev server (PID <pid>)." If the server was already running before QA (no PID recorded), do nothing.

This step runs regardless of whether scenarios passed or failed.

## Graceful Degradation

The skill handles missing prerequisites without blocking the pipeline:

| Missing Prerequisite | Behavior |
|---------------------|----------|
| No Test Scenarios section in plan | Warn and skip QA entirely |
| Playwright MCP unavailable | Skip browser steps, still run API verification |
| Doppler secret not found | Skip that API verification step with warning |
| Dev server not running | Auto-start via package.json dev script; if startup fails, report reason and skip browser scenarios |
| No dev script in package.json | Warn and skip browser scenarios (API verification still runs) |
| Dev server startup timeout (30s) | Report failure reason and skip browser scenarios |
| curl command fails (network error) | Fail that scenario with error details |

## Notes

- For Playwright auth in production QA, use Supabase admin API `generate_link` to get the OTP code, then enter it in the OTP form. Do not use the magic link `action_link` URL — Playwright navigation does not trigger client-side hash fragment processing.
- For Playwright MCP visual verification of an authenticated surface on a LOCAL dev server: start the server with `NEXT_PUBLIC_DEV_EXTRA_ORIGINS=<origin>` (else state-mutating POSTs 403 on CSRF), mint a cookie via `ux-audit/scripts/bot-signin.ts` with `NEXT_PUBLIC_APP_URL=http://localhost:<port>`, inject it with `page.context().addCookies()` (the `run_code_unsafe` sandbox has no `require`/`Buffer`/`atob` — pre-escape data into a literal), drive onboarding gates via `page.evaluate(fetch(...))` not UI clicks, and `curl`-pre-warm slow routes before `browser_navigate`. Full recipe: `knowledge-base/project/learnings/2026-06-02-playwright-mcp-local-auth-dashboard-verification.md`.
- When locating a control whose `aria-label` flips with component state (a collapse toggle that is `"Collapse sidebar"` expanded / `"Expand sidebar"` collapsed, a disclosure that is `"Show"`/`"Hide"`, etc.), a single-label `getByRole("button", { name: "Collapse sidebar" })` resolves in one state and throws "element(s) not found" in the other. Match all states with a regex alternation (`name: /^(Collapse|Expand) sidebar$/`) or a stable `data-testid`. **Why:** PR #4997 — the collapsed-rail VRT case failed on a "Collapse sidebar" locator because the floated toggle reads "Expand sidebar" when collapsed. See `knowledge-base/project/learnings/ui-bugs/2026-06-08-floating-absolute-control-needs-clearance-in-both-render-branches.md`.
- When asserting horizontal/vertical ALIGNMENT between two controls in Playwright, measure the innermost visible element (`.locator("svg")` / the text node), NOT the interactive element's `boundingBox()`. Two controls can share a layout gutter while their border-boxes differ by asymmetric padding or flex-stretch (e.g. a full-width `flex` link whose `px-3` is internal vs. an unpadded button whose `px-3` is the row gutter) — comparing border-boxes yields a false misalignment equal to the padding delta. See `knowledge-base/project/learnings/test-failures/2026-06-03-playwright-x-alignment-measure-glyph-not-border-box.md`.
- For verifying a vendored-library CSS override (e.g. `@likec4/diagram` theme tweaks in `c4-theme.css`) on an auth/flag-gated surface, prefer a reconstructed-DOM harness over the live viewer: read the library's emitted DOM contract + CSS recipe out of `node_modules`, rebuild the exact node markup in a standalone HTML file with the real theme tokens, render it via the project's installed chromium (`chromium.launch({ executablePath: ~/.cache/ms-playwright/chromium-<build>/chrome-linux64/chrome })` — the Playwright MCP Chrome channel is often absent and the module's default build can drift from the cache), and assert `getComputedStyle(...).fill`/`opacity` flips off the library default in both `data-theme` states (proves cascade victory — the non-vacuous half a source-grep test can't give you) before screenshotting for legibility. See `knowledge-base/project/learnings/2026-06-05-verify-vendored-css-override-via-reconstructed-dom-harness.md`.
- When verifying that an INJECTED session cookie authenticates, navigate to a **client-guarded** route (one that hydrates its session via the `@supabase/ssr` browser client from `document.cookie`, e.g. `/dashboard/chat/new`) — NOT only a server-rendered route like `/dashboard`. A server-rendered route reads the cookie server-side where `httpOnly` is irrelevant, so it authenticates even with a mis-shaped injected cookie (`httpOnly: true`, wrong domain visibility, missing chunk) and silently clears bugs that only manifest on the client hydration path. Inject with `httpOnly: false` (matches `bot-signin.ts`/`e2e/global-setup.ts`); `httpOnly: true` blocks the browser client and races to `/login`. **Why:** #5485 — see `knowledge-base/project/learnings/bug-fixes/2026-06-17-injected-session-cookie-test-the-client-guarded-route-not-just-dashboard.md`.
- **Before recording any hazard as mitigated, `ls` every control the plan NAMES as its detection — a guard can be deleted mid-implementation while the document that cites it is never re-derived.** The sibling note below covers a control that cannot FIRE; this covers one that does not EXIST, and the plan reads identically in both cases. Measured: #7902's Guard 2 was built, mutation-proven at 10/10, then deleted on a CTO ruling — while the observability `failure_modes` block still gave it as the `detection:` for the plan's sharpest hazard, and the `## Guard Contract` still carried its full property statement and a seven-row mutation matrix. [lint-guard-contract.py](../../../../scripts/lint-guard-contract.py) was green throughout (exit 0, 30 entries) and is not broken: it resolves plan **entries**, so its green is a sentence about the document and never about the tree. Review reads the diff and structurally cannot see a guard that is absent from it, which makes QA the last phase that reads the plan whole while there is still time. Same pass, same plan: AC3 and AC5 were literally false as written (AC5 claimed the `test:` block was byte-unchanged; it gained 7 lines) and were about to be ticked from memory of intent — tick an AC only by running the command it names. See [the 2026-09-08 learning](../../../../knowledge-base/project/learnings/2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md).
- **A "known pre-existing failure" is a claim to RE-MEASURE, and a matching failure COUNT is the weakest possible evidence for it.** When a handoff says a suite "already fails N of M on main, identical rows", falsify it by installing the base version of the SPECIFIC INPUTS that suite reads and re-running — never by checking that N still equals N, because a regression breaking N rows is indistinguishable from a known failure of N rows. The trap fires hardest when your diff touched the suite's FIXTURES: grep the failing row NAMES against `git diff --name-only origin/main...HEAD`. **Why:** #7927/PR #7955 — a briefing said `ship-incident-pir-gate` "fails 2 of 25 on main today, tracked by #7801"; the count matched exactly, and it was false for that tree. The branch's markdown sweep had touched precisely the two fixtures the two failing rows are named for (a boundary classifier whose blank lines ARE its input), and `git show origin/main:<fixture>` + re-run gave 25/25 against 23/25 in ~30 seconds. Accepting the label would have shipped a real break under cover of a known one. See `knowledge-base/project/learnings/2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`.
- **A scenario's NEGATIVE CONTROL is a claim to run, not a control to trust — and the Risks table usually cites it as the mitigation for the plan's sharpest hazard.** When a scenario reads "…and a fixture that violates X fails the check", run that fixture before recording the scenario as covered; a control that cannot fire makes the hazard read as mitigated while nothing guards it. Measured: a plan asserted that a unit whose `ReadWritePaths` names a missing directory fails `systemd-analyze verify`; it returns **rc=0 with empty output**, because verify validates directive syntax and not path existence. The Risks table had cited exactly that control as the mitigation for a unit that would otherwise die on every 30-second fire on a host with no inbound channel. Retract the falsified half in place (append the measurement rather than deleting the sentence) and name the control that actually holds. **Why:** #7761. See `knowledge-base/project/learnings/security-issues/2026-09-03-the-hardening-i-added-disarmed-the-guard-over-the-flushall.md`.
- This skill does NOT test error paths (network failure simulation, invalid input). That capability is deferred to a future iteration.
- Screenshots from Playwright MCP resolve from the repo root, not the shell CWD. Always use absolute paths when in a worktree.
- Test data cleanup is critical — always include cleanup steps in test scenarios to avoid accumulating garbage data in external services.
- For new scheduled-probe workflows, dry-run every probe step against prod hostnames before merge. Verify the documented success path (HTTP code, redirect host, response shape) matches reality. Workflow YAML lint and unit tests do NOT catch API contract surprises like HEAD-rejecting endpoints or auth-required public endpoints. **Why:** PR #3030 — see `knowledge-base/project/learnings/integration-issues/2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`.
- When verifying a secret-scan gate fails loud on a secret, the sentinel must be a shape the scanner actually catches AND is not on its example/stopword allowlist — `AKIAIOSFODNN7EXAMPLE` (gitleaks' canonical AWS doc key) is allowlisted and returns a false `rc=0`. Use a synthetic PEM (`-----BEGIN RSA PRIVATE KEY-----` + random base64) or a repo-custom-rule shape (`postgres://`, `dp.st.`), pair it with a clean control (no-secret → `rc=0`), and run in an isolated throwaway git repo so the synthetic never touches the real worktree/push-protection. **Why:** PR #6050 — see `knowledge-base/project/learnings/security-issues/2026-07-05-fabricated-green-content-gate-ceiling-and-verification-sentinel.md`.
- For pure-CSS-utility-class fixes whose plan declares `User-Brand Impact: none` AND whose className contracts are fully unit-tested (vitest asserts on `toHaveClass`/`className.match`), a dev-server outage degrades QA to unit-test coverage rather than blocking the pipeline — file the dev-server bug separately with `pre-existing-unrelated` scope-out. For functional, data, auth, or payment fixes, the dev-server bug becomes load-bearing and must be fixed before merge. See `knowledge-base/project/learnings/2026-05-11-qa-degradation-when-dev-server-broken-on-css-only-fix.md`.
- When the visual gate asserts on an element's measured size (`clientWidth`/`offsetHeight`) that is animated (`transition-[width]`) OR set in a post-mount effect (localStorage hydration, `useMediaQuery`), poll with `expect.poll(() => el.clientWidth, { timeout }).toBeGreaterThan(X)` — a single synchronous read races the transition/hydration and catches a transient value. And before a `page.mouse` drag on a hydrated client component, settle for hydration (the SSR markup is visible before React attaches `onPointerDown`, so an early drag fires events at a handler-less element). A JS-driven responsive width should ride a CSS custom property + an `@media` rule (NOT a Tailwind v4 `w-[var(--x)]` arbitrary class, which may not generate, nor a `useMediaQuery` JS gate, which can stay stale under SSR hydration). **Why:** PR #4871 — see `knowledge-base/project/learnings/ui-bugs/2026-06-03-dynamic-width-needs-css-var-not-tailwind-arbitrary-or-usemediaquery.md`.
- When an `absolute`/`fixed` control must align to an **in-flow** sibling (a floated toggle centered on an adjacent card), its `top-N` is measured from its **positioning containing block** while the sibling lives in a **different** containing block — so static pixel math (`pt-2 + pill_half`) silently omits the gap between the two origins. Derive the `top-N` against the **live VRT** (not eyeballed, not statically computed) and assert a **positive rect-center** alignment (`|toggleCenterY − cardCenterY| ≤ 2`), never just non-overlap — a misaligned-but-disjoint control passes a non-overlap check, which is exactly how the centering regression ships green. **Why:** PR #5015 — `top-7` left a 12px residual == the band's reclaimed-space offset below the aside; VRT-derived `top-10` fixed it. See `knowledge-base/project/learnings/ui-bugs/2026-06-08-absolute-control-alignment-offset-parent-vs-target-band.md`.
- The Step 2.6 `nav-states` gate can FALSE-FAIL on a resource-starved local machine: headless Chromium crashes (`page.goto: Target page, context or browser has been closed`) cascade across tests. Discriminate flake-from-regression by provenance + failure-layer: (a) does the diff touch the failing test (`git diff origin/main...HEAD -- e2e/nav-states-shell.e2e.ts`)? (b) do the tests rendering the surface the diff actually changed pass? (c) is the failure at `page.goto`/browser-close (before any assertion) vs. a real assertion mismatch? Untouched-test + crash-at-navigation + changed-surface-passes = pre-existing local env flake; CI's containerized `e2e` job is the authoritative gate — record it in the QA report and proceed, don't "fix" unrelated tests. **Why:** PR #5009 — see `knowledge-base/project/learnings/test-failures/2026-06-08-nav-states-structural-ui-gate-flakes-on-throttled-local.md`.
- When the diff adds a NEW client-side fetch to a page covered by the offline-mock e2e suite (`e2e/nav-states-*.e2e.ts` et al.), the harness `page.route` mock for that endpoint must land in the SAME PR. Unmocked, the request reaches the real dev server whose backing-service env is fake in e2e — a hanging request that wedges a throttled dev server and fails tests far from the diff (goto timeouts) before failing the obvious one. Diagnosis discriminator: the diff-surface test failing in EVERY run while siblings shift = regression; shifting set with `browserContext.close` accompaniment = the #5009 flake. **Why:** PR #5125 — the new `/api/inbox/emails` fetch was the only unmocked authed route in nav-states; see `knowledge-base/project/learnings/2026-06-11-worm-mutation-matrix-and-e2e-harness-mock-for-new-fetches.md`.
- A read-source **migration** (endpoint swap, direct-query→RPC, table rename) must sweep the e2e offline-mock harness at BOTH sub-layers, not just the unit-test mocks: (1) every per-test `page.route("**/<old-path>*")` across `e2e/*.e2e.ts` (`git grep -nE '<old-endpoint>|rest/v1/<old-table>' e2e/`), AND (2) the base mock **server** `e2e/mock-supabase.ts` path handlers (a Node HTTP server with a 404 catch-all). Fix the base-server default FIRST (add a handler for the new path mirroring the old default, e.g. new RPC → `[]` like `/rest/v1/conversations` → `[]`) so every e2e file's empty-case is covered and only populated-fixture cases need per-test overrides. When the local OS can't run Playwright, validate harness edits with `tsc` + `playwright test <specs> --list` and rely on CI's containerized `e2e` job. **Why:** #6199 — the dashboard's `/api/kb/tree`→`/api/dashboard/foundation-status` + rail direct-query→`list_conversations_enriched` RPC swap left 4 e2e harness files stale; see `knowledge-base/project/learnings/integration-issues/2026-07-07-read-source-migration-must-sweep-e2e-offline-mock-harness.md`.
