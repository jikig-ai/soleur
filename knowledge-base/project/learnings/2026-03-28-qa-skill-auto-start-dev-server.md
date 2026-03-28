# Learning: QA skill auto-start dev server — intent-based SKILL.md instructions

## Problem

The `/soleur:qa` skill listed "Local development server running" as a hard prerequisite and failed browser scenarios with "Server not reachable" when the dev server was not running. In one-shot pipelines, this caused QA to be skipped entirely because no human was present to start the server. This was one of the top 6 friction points across 100 sessions (identified in the 2026-03-28 insights report).

## Solution

Added Step 1.5 (auto-start) and Step 5.5 (cleanup) to `plugins/soleur/skills/qa/SKILL.md`. The skill now:

1. Checks if the dev server is reachable via curl
2. If not, detects the dev command from `apps/web-platform/package.json`
3. Starts the server via `doppler run` (or bare command), logging output to `/tmp/qa-dev-server.log`
4. Polls for readiness with a 30-second wall-clock timeout
5. On timeout, includes last 20 lines of server log in the failure report
6. Kills the auto-started server after QA completes (Step 5.5)

Updated the Graceful Degradation table and Prerequisites section to reflect the new behavior.

## Key Insight

When writing AI agent instructions (SKILL.md files), write **intent** not **implementation**. The simplicity reviewer caught that prescriptive bash snippets (exact curl flags, jq commands, loop implementations) are unnecessary — Claude can derive these. Intent-based instructions ("poll until server responds or 30 seconds elapse") are clearer, shorter, and more resilient to changes than copy-paste bash templates.

Review agents caught 4 issues in the initial implementation that intent-based writing would have partially prevented:

- Polling timeout math: "30 iterations with 2s timeout + 1s sleep" = 90s, not 30s. Wall-clock phrasing ("poll for up to 30 seconds") avoids the math entirely.
- Missing working directory: prescriptive commands omitted `cd apps/web-platform/` because the focus was on the command, not the intent.
- Output suppression: `/dev/null` was copied from the plan without considering debuggability. Intent-based ("capture output for failure diagnostics") leads naturally to a log file.

## Session Errors

1. **Plan subagent didn't complete deepen-plan** — The plan+deepen subagent completed the plan but returned without running deepen-plan or producing the expected Session Summary format. Recovery: ran deepen-plan inline from the main context. Prevention: subagent prompts should list ALL steps with explicit "Do NOT return until step N is complete" language, and the Session Summary format should be the FIRST thing described (not buried at the end).

2. **Review agents flagged 4 implementation issues** — Polling timeout math wrong (90s vs 30s), missing working directory, output suppression hiding errors, ambiguous Step 5 continuation language. Recovery: all 4 fixed inline during review phase. Prevention: the review phase caught these correctly — this validates that the multi-agent review pipeline works as designed for SKILL.md changes.

## Tags

category: workflow-patterns
module: plugins/soleur/skills/qa
