---
title: YAML prompt extraction to JS template literal — backtick escaping
date: 2026-05-25
category: best-practices
tags: [inngest, cron-substrate, prompt-extraction, template-literal, escaping]
module: apps/web-platform/server/inngest/functions
related_pr: 4460
---

# Learning: YAML prompt extraction to JS template literal — backtick escaping

## Problem

When extracting a GHA workflow's `prompt: |` YAML block into a JavaScript template literal constant (`const PROMPT = \`...\``), inline backticks (code fences, inline code) need escaping. The correct escape is `\`` (single backslash + backtick). Using `\\\`` (triple backslash + backtick) produces `\` + `` ` `` = `\`` at runtime — a literal backslash followed by a backtick, NOT a bare backtick.

TR9 PR-11 shipped with `\\\`\\\`\\\`` for code fences and `\\\`git log\\\`` for inline code. Two review agents (code-quality-analyst P1, security-sentinel P3) independently flagged the fidelity deviation.

## Solution

In a JS template literal:
- `\`` → bare `` ` `` at runtime (CORRECT for markdown backticks)
- `\\` → bare `\` at runtime
- `\\\`` → `\` + `` ` `` = `\`` at runtime (WRONG — adds visible backslash)

For triple-backtick code fences: use `\`\`\`` (three single-escaped backticks).
For inline code: use `\`git log\`` (single-escaped opening + closing backtick).

## Key Insight

When extracting prompts from YAML into template literals, the ONLY escape needed for backticks is a single `\` prefix. The common error is over-escaping by treating `\\` as "one literal backslash" and `\`` as "one literal backtick" independently — in a template literal, the `\\` is already a complete escape sequence (literal backslash), so `\\\`` produces TWO characters (`\` + `` ` ``), not one (`` ` ``).

## Prevention

Add a post-extraction verification step: `node -e "console.log(PROMPT.includes('\`\`\`'))"` — if this prints `false` but the original YAML had triple backticks, the escaping is wrong.

## Session Errors

1. **Backtick over-escaping** — Used `\\\`` instead of `\``. Recovery: fixed in review commit. Prevention: always verify rendered output of template literal constants against the original YAML source; the test suite should include a triple-backtick anchor assertion.
2. **Negative-class test incomplete** — Omitted 5 sensitive Doppler vars. Recovery: added by review fix. Prevention: grep `prd` Doppler for ALL sensitive-looking vars at write time, not just the ones the plan enumerated.
3. **Missing DEDUP/CLONE DEPTH test anchors** — Copied safety-guard anchors from plan but missed the PR-7 equivalents. Recovery: added by review fix. Prevention: diff the sibling handler's test anchors (`it.each` block) against the new test file before committing.
4. **Plan-scope divergence** — Planner elevated Doppler mirror to pre-merge gate contrary to operator instruction. Recovery: 8 targeted plan edits. Prevention: when operator instruction explicitly says "NOT to fix in this PR", the planning subagent prompt should carry a constraint line; the parent verifies scope before /work.

## Tags

category: best-practices
module: apps/web-platform/server/inngest/functions
