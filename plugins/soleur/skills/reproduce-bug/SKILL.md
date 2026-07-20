---
name: reproduce-bug
description: "This skill should be used when reproducing and investigating a bug using logs, console inspection, and browser screenshots. It systematically investigates GitHub issues through log analysis, code inspection, and visual reproduction with Playwright."
---

# Reproduce Bug

Look at github issue #$ARGUMENTS and read the issue description and comments.

## Phase 1: Log Investigation

Think about the places it could go wrong looking at the codebase. Look for logging output to search for.

**Check the observability layer FIRST — before hypothesizing from code.** Server-side / cron / prod failures usually have the real error (the exact failing step, hostname, status, stack) already captured in Sentry or Better Stack. Pull it before theorizing — a code-trace guess can burn many cycles that one Sentry event resolves.

1. **Sentry** — query the project's issues for the error (the `incident` skill's toolchain). Tokens + slugs live in Doppler `prd`: `SENTRY_ISSUE_RW_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_API_HOST` (host needs the `https://` scheme). Example:

   ```bash
   ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain)
   PROJ=$(doppler secrets get SENTRY_PROJECT -p soleur -c prd --plain)
   TOK=$(doppler secrets get SENTRY_ISSUE_RW_TOKEN -p soleur -c prd --plain)
   curl -s -H "Authorization: Bearer $TOK" \
     "https://jikigai-eu.sentry.io/api/0/projects/$ORG/$PROJ/issues/?query=<keyword>&statsPeriod=24h&limit=5" \
     | jq -r '.[]? | "\(.lastSeen) | \(.title) | n=\(.count)"'
   ```
   Then drill into the issue's latest event for `extra` (carries the operative detail — a blocked `DST=` IP, a vendor status, the failing arg). Note: a cron-monitor **error check-in** carries no stack trace; the real exception is a separate `reportSilentFallback`/`captureException` issue — query for it. **Named helper:** once you have an issue id, `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <id>` (add `--latest-event` for the stack/exception) wraps this read-by-id with the least-privilege `SENTRY_ISSUE_RO_TOKEN`. Runbook: `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md`.

2. **Better Stack** logs (the app's pino stream, historical) via the repo-root [betterstack-query.sh](../../../../scripts/betterstack-query.sh) helper (ClickHouse SQL over the Telemetry warehouse). Runbook: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`. The failing fetch's error (with the HOSTNAME) lives here.

3. Check recent commits related to the affected area, then inspect the relevant code paths — now anchored on the real error, not a guess.

**Why (#5088):** a cron silently failed to publish; several turns went to code hypotheses before pulling the Sentry `egress-blocked` event, which pinpointed the firewall dropping a GitHub clone IP in one read. The observability layer already had the answer. See `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` for the egress-specific diagnosis path.

**Blind execution surface (Concierge agent-sandbox, cron worker, container readiness gate) with NO usable observability yet — instrument the deployed code, never ask the operator to run diagnostics.** When the failure lives on a surface you cannot run commands in AND Sentry/Better Stack don't already carry the operative detail, the correct move is to ADD structured, grep-able diagnostics to the deployed code (e.g. what a lock file actually is: type/stat/mount/`rm` errno) so the NEXT occurrence self-reports into the surface's own debug stream — then read that. NEVER ask a (non-technical) Soleur operator to run `ls`/`stat`/`findmnt`/`git config`/etc. — that violates `hr-no-dashboard-eyeball-pull-data-yourself` and `hr-no-ssh-fallback-in-runbooks`. The deployed code is your instrument; the operator is not. Corollary: instrumenting a plugin-runtime surface only helps once it DEPLOYS — verify the delivery path (for Concierge, a web-platform image rebuild re-seeds `/mnt/data/plugins/soleur`), because a merged fix is not a deployed fix. **Why (#5888 / PR #5880 follow-up):** two sessions asked the operator to run sandbox diagnostics for a wedged `.git/config.lock`; the correct fix was to instrument `worktree-manager.sh` so the sweep self-reports the lock's true nature. See `knowledge-base/project/learnings/workflow-patterns/2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md`.

**Even when observability EXISTS, self-pull it — do not ask the operator to paste error output.** The operator's role in a diagnostic loop is DECISIONS, not data retrieval. Query Better Stack `SOLEUR_*` markers yourself (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since <N> --grep <marker>`) and Sentry rather than asking the operator to paste logs or run probes — and if the needed signal is missing from telemetry, ADD a monitored stdout `SOLEUR_*` marker in the emitting code (per the blind-surface bullet above), never escalate to the operator for it. **Why (#5934 worktree-wedge):** the diagnosis twice asked the operator to paste `grep`/`stat` output that the observability layer held (or, once instrumented, would hold — `SOLEUR_GIT_CONFIG_TARGET_MASKED`, `SOLEUR_GIT_WORKTREE_VERIFY_FAILED`). See `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md`.

Keep investigating until a good understanding of the situation is reached.

## Phase 2: Visual Reproduction with Playwright

If the bug is UI-related or involves user flows, use Playwright to visually reproduce it:

### Step 1: Verify Server is Running

```
mcp__plugin_soleur_pw__browser_navigate({ url: "http://localhost:3000" })
mcp__plugin_soleur_pw__browser_snapshot({})
```

If server not running, inform user to start `bin/dev`.

### Step 2: Navigate to Affected Area

Based on the issue description, navigate to the relevant page:

```
mcp__plugin_soleur_pw__browser_navigate({ url: "http://localhost:3000/[affected_route]" })
mcp__plugin_soleur_pw__browser_snapshot({})
```

### Step 3: Capture Screenshots

Take screenshots at each step of reproducing the bug:

```
mcp__plugin_soleur_pw__browser_take_screenshot({ filename: "bug-[issue]-step-1.png" })
```

### Step 4: Follow User Flow

Reproduce the exact steps from the issue:

1. **Read the issue's reproduction steps**
2. **Execute each step using Playwright:**
   - `browser_click` for clicking elements
   - `browser_type` for filling forms
   - `browser_snapshot` to see the current state
   - `browser_take_screenshot` to capture evidence

3. **Check for console errors:**
   ```
   mcp__plugin_soleur_pw__browser_console_messages({ level: "error" })
   ```

### Step 5: Capture Bug State

When the bug is reproduced:

1. Take a screenshot of the bug state
2. Capture console errors
3. Document the exact steps that triggered it

```
mcp__plugin_soleur_pw__browser_take_screenshot({ filename: "bug-[issue]-reproduced.png" })
```

## Phase 3: Document Findings

**Reference Collection:**

- [ ] Document all research findings with specific file paths (e.g., `app/services/example_service.rb:42`)
- [ ] Include screenshots showing the bug reproduction
- [ ] List console errors if any
- [ ] Document the exact reproduction steps
- [ ] **Execute the mechanism, do not infer it.** A reproduction confirms the *symptom*, not the story attached to it. Before recording a root cause, run the mechanism itself. If it has a quantitative precondition (buffer size, timeout, rate limit, row count), check the repro's own numbers actually clear it; and A/B a **single** variable — a comparison whose two cases differ in two ways names no cause. State confidence explicitly ("symptom reproduced; mechanism inferred, not tested"), because an untested mechanism written in the indicative becomes fact on the next read. For hook defects specifically, drive the real hook with a synthetic payload (`jq -nc '{tool_name, tool_input}' | bash .claude/hooks/<hook>.sh`) instead of reasoning about it — seconds of work, and it exercises the actual code path. **Why:** #6501 — `iac-plan-write-guard`'s broken ack bypass was diagnosed as SIGPIPE+`pipefail`, reproduced ("48KB plan → denied / small doc → allowed"), documented, and wrong: pipe capacity is 64KB so the blamed 48KB never blocks, and the two cases differed in *tool* (`Edit` vs `Write`), not bytes. The recorded fix would have changed nothing. See `knowledge-base/project/learnings/2026-07-15-a-reproduced-symptom-does-not-validate-the-mechanism-you-attached-to-it.md`.

## Phase 4: Report Back

Add a comment to the issue with:

1. **Findings** - What was discovered about the cause
2. **Reproduction Steps** - Exact steps to reproduce (verified)
3. **Screenshots** - Visual evidence of the bug (upload captured screenshots)
4. **Relevant Code** - File paths and line numbers
5. **Suggested Fix** - If one exists

## Phase 5: Cleanup

After uploading screenshots to the issue comment, remove local screenshot artifacts. Playwright MCP writes to the main repo root when invoked from a worktree.

```bash
# Remove bug reproduction screenshots from current working directory
rm -f bug-*.png

# If in a worktree, also clean the main repo root
MAIN_REPO=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [[ -n "$MAIN_REPO" ]]; then
  rm -f "$MAIN_REPO"/bug-*.png
fi
```
