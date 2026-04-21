---
name: competitive-analysis
description: "This skill should be used when running competitive intelligence scans against tracked competitors, or auditing a peer skill-library repo via peer-plugin-audit. Produces structured knowledge-base reports."
---

# Competitive Analysis

Run a competitive intelligence scan (monthly tiered report) or a targeted peer-plugin audit. Both modes produce structured output in `knowledge-base/product/competitive-intelligence.md`.

## Sub-Modes

| Mode | Invocation | Purpose |
|---|---|---|
| Tier scan (default) | `skill: soleur:competitive-analysis [--tiers 0,3]` | Monthly competitive intel report across tracked tiers |
| Peer-plugin audit | `skill: soleur:competitive-analysis peer-plugin-audit <repo-url>` | Audit a peer skill library/plugin, seed the Skill Library tier with a structured 4-section report |

## Steps

### 1. Detect Invocation Mode

**peer-plugin-audit sub-mode (checked first):**

If arguments start with `peer-plugin-audit`:

- Extract the repo URL (second arg).
- Read [peer-plugin-audit.md](./references/peer-plugin-audit.md) and follow that procedure.
- Stop (do not fall through to tier selection).

**competitive intelligence mode (existing):**

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

Task competitive-intelligence: "Run a competitive intelligence scan for tiers <TIERS>. Research each competitor in the specified tiers, read brand-guide.md and business-validation.md for positioning context, and write the report to knowledge-base/product/competitive-intelligence.md."

### 4. Report Results

After the agent completes:

- Confirm the report was written (or output as code block in CI)
- Display the executive summary

## Scheduled Execution

The `scheduled-competitive-analysis.yml` workflow runs this skill monthly via `claude-code-action`. The agent's prompt includes instructions to commit and push the report to main after creating the audit trail issue. The push must happen inside the agent (not a separate workflow step) because: (1) `claude-code-action` revokes the App installation token in its post-step cleanup, and (2) the Claude App is a bypass actor on the CLA Required ruleset, so only pushes under its identity succeed. The GitHub Issue is still created as an audit trail.
