---
name: qa
description: "This skill should be used when running functional QA before merge."
---

# Functional QA

Verify that features actually work before merge -- not just that pages render, but that forms submit correctly, external services receive the right data, and data integrity holds across system boundaries.

**Scope boundary with `/test-browser`:** This skill verifies functional correctness (user flows + external service state). `/test-browser` verifies visual rendering, layout regressions, and console errors. They coexist in the pipeline.

## Prerequisites

- Local development server running (e.g., `npm run dev`, `bin/dev`)
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
- If **any scenario failed**: Output the report with detailed failure information (expected vs actual values, screenshot of failure state). Block the pipeline — output "QA FAILED — fix the issues above and re-run QA."

## Graceful Degradation

The skill handles missing prerequisites without blocking the pipeline:

| Missing Prerequisite | Behavior |
|---------------------|----------|
| No Test Scenarios section in plan | Warn and skip QA entirely |
| Playwright MCP unavailable | Skip browser steps, still run API verification |
| Doppler secret not found | Skip that API verification step with warning |
| Dev server not running | Fail browser scenarios with "Server not reachable" |
| curl command fails (network error) | Fail that scenario with error details |

## Notes

- This skill does NOT test error paths (network failure simulation, invalid input). That capability is deferred to a future iteration.
- Screenshots from Playwright MCP resolve from the repo root, not the shell CWD. Always use absolute paths when in a worktree.
- Test data cleanup is critical — always include cleanup steps in test scenarios to avoid accumulating garbage data in external services.
