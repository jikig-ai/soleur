# Learning: Multi-agent cascade orchestration checklist

## Problem

Implementing a cascade pattern where one agent (competitive-intelligence) spawns 4 specialist agents after completing its primary work. Multiple P1 issues were caught only during code review, any of which would have caused silent failure in production.

## Solution

Three critical items must be verified for any agent-to-agent cascade:

1. **`Task` tool in `allowedTools`**: If the workflow runs in CI via `claude-code-action`, the `Task` tool must be explicitly listed in `--allowedTools`. Without it, the cascade silently never executes. This is the same class of defect that v3.7.6 fixed for other tools.

2. **Explicit write targets for every specialist**: Each spawned agent must have a concrete file path to write to in the delegation table. "Update content strategy gaps" is too vague — specify `Update knowledge-base/overview/content-strategy.md`. Without this, specialists hallucinate write targets or write to the parent's file.

3. **Every specialist must produce a writable artifact**: If a specialist's task is read-only analysis ("flag stale pages"), it has no output for the Cascade Results table. Either give it a concrete write destination (`knowledge-base/marketing/seo-refresh-queue.md`) or explicitly state the output is ephemeral.

Additional review-caught improvements:
- Restrict sub-agent tool access (remove Bash/WebFetch from specialists that only need Read/Write/Edit/Glob/Grep)
- Add explicit Phase 1→2 handoff signal so the agent confirms disk write before cascading
- Specify return contract format precisely (comma-separated paths, not free-form)
- Disclose cascade behavior in agent description frontmatter so callers know it happens

## Key Insight

Multi-agent cascades have a "silent failure" failure mode: when a required tool is missing from allowedTools, when write targets are unspecified, or when a specialist has no output path, the cascade fails without error messages. Every cascade requires a pre-flight checklist: tool permissions, write targets, and artifact verification.

## Session Errors

1. GitHub Actions security hook rejected workflow edit on first attempt (re-submitted successfully)
2. "File has not been read yet" error when editing plugin.json — must Read before Edit
3. marketplace.json path confusion: `plugins/soleur/.claude-plugin/plugin.json` vs root `.claude-plugin/marketplace.json`
4. P1: Task tool missing from workflow allowedTools (caught in review)
5. P1: Write targets missing from delegation table (caught in review)
6. P1: programmatic-seo-specialist had no writable artifact (caught in review)

## Tags

category: integration-issues
module: competitive-intelligence, multi-agent-cascade
