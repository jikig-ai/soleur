---
name: competitive-analysis
description: "This skill should be used when running competitive intelligence scans against tracked competitors, or auditing a peer skill-library repo via peer-plugin-audit. Produces structured knowledge-base reports."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

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

Spawn the soleur:product:competitive-intelligence agent via Task tool:

Task soleur:product:competitive-intelligence: "Run a competitive intelligence scan for tiers <TIERS>. Research each competitor in the specified tiers, read brand-guide.md and business-validation.md for positioning context, and write the report to knowledge-base/product/competitive-intelligence.md."

### 4. Report Results

After the agent completes:

- Confirm the report was written (or output as code block in CI)
- Display the executive summary

## Scheduled Execution

The `scheduled-competitive-analysis.yml` workflow runs this skill monthly via `claude-code-action`. The agent's prompt includes instructions to commit and push the report to main after creating the audit trail issue. The push must happen inside the agent (not a separate workflow step) because: (1) `claude-code-action` revokes the App installation token in its post-step cleanup, and (2) the Claude App is a bypass actor on the CLA Required ruleset, so only pushes under its identity succeed. The GitHub Issue is still created as an audit trail.
