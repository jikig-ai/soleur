---
name: qa
description: "This skill should be used when running functional QA before merge."
---

# Functional QA

Verify that features actually work before merge -- not just that pages render, but that forms submit correctly, external services receive the right data, and data integrity holds across system boundaries.

**Scope boundary with `/test-browser`:** This skill verifies functional correctness (user flows + external service state). `/test-browser` verifies visual rendering, layout regressions, and console errors. They coexist in the pipeline.

## Prerequisites

- Local development server running OR a `dev` script in the project's `package.json` (auto-started if not running)
- Playwright MCP available (for browser scenarios)
- Doppler CLI installed and configured (for API verification scenarios)

## Usage

```bash
skill: soleur:qa, args: "<plan_file_path>"
```

The skill reads the plan file's `## Test Scenarios` section and executes each scenario.

## Workflow

### Step 1: Read Plan and Extract Test Scenarios

Read the plan file passed as `$ARGUMENTS`. Find the `## Test Scenarios` section.

**If no Test Scenarios section exists:** Output "No test scenarios found in plan — skipping QA" and stop. Do not block the pipeline.

**If Test Scenarios section is empty:** Same as above — warn and skip.

### Step 1.5: Ensure Dev Server is Running

Before executing any browser scenarios, check whether the dev server is reachable. If not, attempt to start it automatically.

1. **Check if already running:** `curl -sf --max-time 3 http://localhost:3000/ >/dev/null 2>&1`. If reachable, skip to Step 2 — no action needed. Record that the server was NOT started by QA (so cleanup skips it).

2. **Detect the dev command:** Read `apps/web-platform/package.json` and extract the `scripts.dev` field. If no `dev` script exists, warn: "No dev script found in package.json — cannot auto-start server. Skipping browser scenarios." Continue to API verification steps (do not block the pipeline).

3. **Start the server:** Change to the `apps/web-platform/` directory first (the dev command must run from the app root). Check if Doppler is available (`command -v doppler`). If available, start via `doppler run -p soleur -c dev -- <dev-command> > /tmp/qa-dev-server.log 2>&1 &`. If Doppler is unavailable, start via `<dev-command> > /tmp/qa-dev-server.log 2>&1 &`. Record the background PID.

4. **Poll for readiness (30s timeout):** Poll `http://localhost:3000/` until it responds or 30 seconds have elapsed, whichever comes first. If the server responds, proceed to Step 2. If the timeout elapses:
   - Kill the background process by PID
   - Include the last 20 lines of `/tmp/qa-dev-server.log` in the failure report
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

### Step 3: Execute Test Scenarios

For each test scenario in the plan, execute the steps it describes. Scenarios contain three possible step types, identified by their prefix:

- **Browser:** steps — Execute via Playwright MCP tools (`browser_navigate`, `browser_fill_form`, `browser_click`, `browser_snapshot`, `browser_take_screenshot`)
- **API verify:** steps — Execute the exact `doppler run` + `curl` command from the scenario. Compare the output against the expected value stated in the scenario.
- **Cleanup:** steps — Execute cleanup commands to remove test data from external services. Run these regardless of whether the scenario passed or failed.

**Execution order for each scenario:**

1. Execute **Browser** steps (if present)
   - Use Playwright MCP tools to navigate, fill forms, submit, and verify UI state
   - Capture a screenshot after each significant action using `browser_take_screenshot`
   - When in a worktree, always pass absolute paths for screenshot filenames
   - If Playwright MCP is unavailable, warn "Playwright MCP unavailable — skipping browser steps" and continue to API verification
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

If the dev server was started in Step 1.5 (a background PID was recorded), kill the process by PID, remove `/tmp/qa-dev-server.log`, and report: "Stopped auto-started dev server (PID <pid>)." If the server was already running before QA (no PID recorded), do nothing.

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
- This skill does NOT test error paths (network failure simulation, invalid input). That capability is deferred to a future iteration.
- Screenshots from Playwright MCP resolve from the repo root, not the shell CWD. Always use absolute paths when in a worktree.
- Test data cleanup is critical — always include cleanup steps in test scenarios to avoid accumulating garbage data in external services.
