# Learning: LLM-as-Script Pattern for CI File Generation

## Problem

The initial plan for the rolling campaign calendar (#558) specified a bash script to parse YAML frontmatter from 6 markdown files, classify entries by status, and generate a markdown table. Three independent reviewers (DHH, Simplicity, SpecFlow) converged on the same feedback: this was overengineered. The content-publisher's 447-line bash script earns its complexity with real I/O (Discord webhooks, X API, OAuth). A calendar generator that reads files and writes markdown does not.

A secondary gap emerged: the spec only had 3 status groups (upcoming, draft, published). The 4th group — overdue (scheduled + past publish_date) — is the exact failure mode the feature exists to surface. SpecFlow caught this before implementation.

## Solution

**LLM-as-script:** When a CI workflow's job is reading markdown and generating markdown, the LLM running via `claude-code-action` IS the script. The skill (SKILL.md) contains the instructions; the LLM reads files, classifies entries, and writes output directly. No bash intermediary.

**Dual-context skills:** Skills that run in both manual (worktree) and CI (direct-to-main) contexts need different commit behavior:
- CI mode (`GITHUB_ACTIONS` env var): write file, commit with `[skip ci]`, push with rebase-retry
- Manual mode: write file only, print `gh workflow run` suggestion

**4-group status classification:** Overdue entries (scheduled + past date) must render first with a warning, not be buried in the "scheduled" group. The status groups are: overdue > upcoming > draft > published.

## Key Insight

The bash-script reflex is strong — even experienced planners default to "write a script" when the task is file I/O. The litmus test: if the workflow already runs an LLM via `claude-code-action`, and the task involves reading structured text and generating structured text, the LLM is the script. Reserve bash for tasks that require real system I/O (APIs, webhooks, OAuth, binary tools).

Plan review convergence (3/3 reviewers flagging the same simplification) is strong signal. When all reviewers independently say "remove this layer," trust the convergence.

## Session Errors

1. **Security hook warning on workflow write** — PreToolUse hook flagged GitHub Actions command injection risk. Fixed by adding a security comment header to the YAML file.
2. **vitest/rolldown MODULE_NOT_FOUND** — Attempted to run `npx vitest` which doesn't exist in this repo. Test runner is `bun test`.
3. **npm test missing script** — `package.json` only has docs scripts. No `test` script defined.
4. **plugin.json path wrong** — Searched at repo root and `plugins/soleur/plugin.json` before finding actual path at `plugins/soleur/.claude-plugin/plugin.json`.
5. **Stale skill counts** — README.md had 56 (actual 57), brand-guide.md had 50. Required correction across 4 files.

## Tags
category: implementation-patterns
module: campaign-calendar
related: 2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md, 2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md, 2026-02-22-skill-count-propagation-locations.md, 2026-02-06-parallel-plan-review-catches-overengineering.md
