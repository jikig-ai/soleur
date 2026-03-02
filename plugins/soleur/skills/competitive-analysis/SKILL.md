---
name: competitive-analysis
description: "This skill should be used when running competitive intelligence scans and market research reports against tracked competitors. It invokes the competitive-intelligence agent to produce a structured knowledge-base report. Triggers on \"competitive analysis\", \"competitor scan\", \"market research\"."
---

# Competitive Analysis

Run a competitive intelligence scan producing a structured report at knowledge-base/overview/competitive-intelligence.md.

## Steps

### 1. Detect Invocation Mode

If arguments are present (non-empty):
- If arguments contain `--tiers`, extract the comma-separated tier list.
- Otherwise, use default tiers (0,3).
- Skip to Step 3.

If no arguments, proceed to Step 2.

### 2. Interactive Tier Selection (skipped if args provided)

Use AskUserQuestion to select tiers:
- Tier 0 + 3: Platform threats and CaaS competitors (default)
- All tiers (0-5): Full landscape scan

### 3. Run Competitive Intelligence Agent

Spawn the competitive-intelligence agent via Task tool:

Task competitive-intelligence: "Run a competitive intelligence scan for tiers <TIERS>. Research each competitor in the specified tiers, read brand-guide.md and business-validation.md for positioning context, and write the report to knowledge-base/overview/competitive-intelligence.md."

### 4. Report Results

After the agent completes:
- Confirm the report was written (or output as code block in CI)
- Display the executive summary

## Scheduled Execution

The `scheduled-competitive-analysis.yml` workflow runs this skill monthly via `claude-code-action`. After the agent writes the report, a shell step pushes it directly to main — making `knowledge-base/overview/competitive-intelligence.md` a living document updated each run. The persist step re-authenticates with `github.token` because `claude-code-action` revokes the App installation token in its post-step cleanup. The GitHub Issue is still created as an audit trail.
