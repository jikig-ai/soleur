---
title: Schedule Skill Template Gaps (First Consumer)
date: 2026-02-27
category: plugin-architecture
tags: [integration-issues, schedule, github-actions]
---

# Learning: Schedule Skill Template Gaps (First Consumer)

## Problem

The `soleur:schedule` skill generates workflow YAML from a fixed template, but the first real consumer (`competitive-analysis`) exposed five gaps that required manual post-generation edits.

## Solution

All six gaps have been resolved in the template. Five are now generated automatically; one remains manual:

1. **Skill-specific arguments** (MANUAL): The template prompt says `Run /soleur:<SKILL_NAME> on this repository.` with no way to pass arguments like `--tiers 0,3`. Edit the prompt line to include them after generation.

2. ~~**`--max-turns` in `claude_args`**~~: Fixed in #443. Template now includes `--max-turns <MAX_TURNS>` (default 30) in `claude_args` using `>-` block scalar format.

3. ~~**Label pre-creation**~~: Fixed in #443. Template now includes an "Ensure label exists" step with `gh label create ... 2>/dev/null || true`.

4. ~~**`timeout-minutes`**~~: Fixed in #443. Template now includes `timeout-minutes: <TIMEOUT>` (default 30) on the job block.

5. ~~**`id-token: write` permission**~~: Fixed in #341. Template includes `id-token: write` in the permissions block.

6. ~~**`--allowedTools` in `claude_args`**~~: Fixed in #344. Template includes `--allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch` in `claude_args`.

## Key Insight

After #443 (and prior fixes #321, #341, #344), the schedule skill template generates complete workflows that match the reference implementations. The only remaining manual step is skill-specific argument passthrough. The `claude-code-action` sandbox is restrictive by default — the most dangerous gap was `--allowedTools` because the workflow reports success even when all Bash commands are silently blocked (now fixed in the template).

## Session Errors

- Security reminder hook fired on first workflow file write (non-blocking, correctly identified no injection risk)

## Tags

category: integration-issues
module: schedule, github-actions
