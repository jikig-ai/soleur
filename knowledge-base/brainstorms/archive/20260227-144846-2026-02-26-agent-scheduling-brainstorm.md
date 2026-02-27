# Agent Scheduling Brainstorm

**Date:** 2026-02-26
**Issue:** #312
**Status:** Complete

## What We're Building

A general-purpose scheduling primitive that lets users schedule any Soleur agent or skill to run on a recurring basis via GitHub Actions. A `soleur:schedule` skill generates standalone `.github/workflows/scheduled-*.yml` files that use `claude-code-action` to invoke the specified agent/skill on a cron schedule. Output is flexible per task — issues, PRs, or Discord notifications.

## Why This Approach

**Core constraint:** Claude Code has no persistent runtime. Sessions are ephemeral and user-initiated. The plugin architecture is static — no daemon, no server, no inter-session triggers. Scheduling must live outside the plugin.

**Why GitHub Actions:** Already proven in the codebase (`review-reminder.yml`, `claude-code-review.yml`). Secrets management is solved. Logging and retry are built-in. `claude-code-action` already runs Claude Code with plugins in CI. No new infrastructure needed.

**Why generated workflows (not a config registry):** Each schedule is a real workflow file — inspectable, editable, version-controlled. No intermediate abstraction layer. Users who know GitHub Actions can hand-edit. The skill is a convenience generator, not a required intermediary.

**Why flexible output:** Use cases span audits (-> issues), maintenance (-> PRs), content (-> Discord). A single output mode would force awkward workarounds for half the use cases.

## Key Decisions

1. **Runtime: GitHub Actions** — Not local cron, not Telegram bridge, not a persistent daemon. GitHub Actions cron handles scheduling, secrets, and logging.

2. **Definition: Generated workflow files** — Each schedule produces a standalone `.github/workflows/scheduled-<name>.yml`. No central config file, no agent frontmatter metadata.

3. **Interface: Single `soleur:schedule` skill** with subcommands:
   - `create` — Interactive generation of a workflow file
   - `list` — Scan and display existing scheduled workflows
   - `delete <name>` — Remove a workflow file
   - `run <name>` — Trigger manual run via `gh workflow run` (testing)

4. **Output: Flexible per task** — Each schedule definition specifies its output mode (issue, PR, Discord). The generated workflow prompt instructs the agent to route results accordingly.

5. **Cost controls: Deferred (YAGNI)** — Model selection per schedule is the only cost lever for now. No budget caps or aggregate limits. Revisit when actual spend data is available.

6. **Model selection: Per schedule** — Each schedule specifies which model to use (haiku for cheap checks, sonnet for substantial work).

## CTO Technical Assessment

### Architecture Risks
- **Concurrent scheduled runs** could cause git conflicts. Worktree isolation is mandatory per run.
- **Silent failures** — failed runs produce no alert. Post-run reporting (issue comment, Discord) should be built into the workflow template.
- **GitHub Actions cron granularity** — minimum ~5 min, practical variance ~15 min. Not suitable for sub-minute scheduling.
- **GITHUB_TOKEN cascade limitation** — workflows triggered by GITHUB_TOKEN don't trigger other workflows. All downstream effects must be in a single workflow.

### Capability Gaps Identified
- No run-history or job-log mechanism (use GitHub Actions run history)
- No cost-gate mechanism (deferred)
- No health-check or alerting skill (post-run reporting in workflow template addresses this)

## Open Questions

1. **Workflow template structure** — How much of the workflow is templated vs. customizable? Should users be able to pass custom environment variables or workflow inputs?
2. **Plugin requirement** — Does the CI runner need the Soleur plugin installed? How is `claude-code-action` configured to discover it?
3. **State across runs** — Some scheduled tasks (e.g., "check for new vulnerabilities since last run") need state. Where does this live? A file in the repo? Workflow artifacts?
4. **Permissions** — Should `scheduled-*.yml` workflows have restricted `permissions:` blocks? What's the minimum required?
5. **Notification on failure** — Should workflow failures auto-create issues or notify Discord?
