---
title: Grok hook aliases keep the original name, so exact-name twins double-fire
date: 2026-09-11
category: engineering
tags: [grok, hooks, aliases, double-fire, matcher, guard-2]
symptoms:
  - "PreToolUse run_terminal_command matcher count 21 on Claude, 42 on Grok after adding exact-name twins"
  - "Guard 2 required a Grok duplicate for every Claude matcher, encoding the double-fire as the passing state"
module: plugins/soleur
component: tooling
problem_type: integration_issue
resolution_type: config_change
root_cause: config_error
severity: high
issues: [8064]
pr: 8061
---

# Learning: Grok hook aliases keep the original name, so exact-name twins double-fire

## Problem

Phase 4 of #8064 duplicated `.claude/settings.json` matcher objects under Grok tool names (`run_terminal_command`, `search_replace`, `spawn_subagent`) because the plan forbade regex-OR (`Bash|run_terminal_command`). That was the right prohibition. The wrong premise was that Grok would only match the Grok name.

Live Grok user-guide `10-hooks.md` ("Tool Name Aliases", CLI 1.0.29, 2026-09-11): `Bash` also matches `run_terminal_command`; `Write`/`Edit`/`MultiEdit` also match `search_replace`; `Task` also matches `spawn_subagent`. **A matcher keeps its original name too.** Dedup is cross-source (global/project/plugin/config), not two groups in one `settings.json`. Two objects for an aliased pair therefore fire twice on Grok (PreToolUse `run_terminal_command` 21→42), including `grep-rewrite.sh`, `guardrails.sh`, and `post-dispatch-watch-gate.sh`. Claude is unchanged (`Bash` 21).

## What didn't work

**Regex-OR.** Mixing Claude and Grok names in one matcher (`Bash|run_terminal_command`) is still forbidden. A split-on-`|` parser can miss a mixed OR that a substring check would catch.

**Requiring twins in Guard 2.** The first Guard 2 encoded "every Claude matcher has a Grok duplicate" as the passing state, so the double-fire was the green.

## Solution

Delete standalone matcher objects whose matcher is an **aliased** Grok name (`run_terminal_command`, `search_replace`, `spawn_subagent`). Keep `ask_user_question` (not in the alias table) and `write` (Write aliases to `search_replace`, not to the distinct `write` tool). Keep Skill/Monitor unaliased. Do not invent Skill/Monitor Grok names.

Rewrite Guard 2 to:

- pin `SETTINGS_PATH` to `git rev-parse --show-toplevel` + `.claude/settings.json` (a `/\.claude\/settings\.json$/` suffix matches a fixture)
- require Skill/Monitor exact tokens
- forbid `|` matchers that **substring**-contain a Grok exact name
- require unaliased Grok names present
- **forbid** aliased Grok names as standalone matchers

## Session Errors

**This turn started on `main` in the primary checkout, not the feature worktree.**

- **Recovery:** `git worktree list` + `cd .worktrees/feat-grok-build-claude-parity` before any edit.
- **Prevention:** On resume, `git rev-parse --abbrev-ref HEAD` and `pwd` must contain `.worktrees/` before the first write. Work Phase 0.5 already FAILs on default branch.

**`routingInstructions("unknown")` still contained the bytes `grok --trust` in a "do not invent one" sentence, so a `not.toMatch(/grok --trust/)` test false-failed.**

- **Recovery:** Reword to "no `--trust` flag" so the command-shaped token is absent.
- **Prevention:** A negative test for "do not prescribe command X" must not be satisfied by a comment that quotes X. Assert the command is absent from runnable fences (` ```bash `) first.

**Fence `toEqual(TIER_MAPS)` first-match regex captured the Grok map as Claude.**

- **Recovery:** `matchAll` over the three `{ cheap: … }` literals in fence order (grok, claude, inherit fallback).
- **Prevention:** When a fence contains N similar object literals, parse all of them; `match` returns the first.

## Why this works

The vendor's alias expansion is union, not rename. Coverage for Grok is already provided by the Claude-named object. A second object with the aliased name is a second invocation, not a second matcher grammar. Unaliased names still need twins.

Same family as adding a second copy of a guarded literal: the extra copy looks like coverage and is a second fire (or a disarmed first). See [2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md](2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md).

## Prevention

- Measure matcher grammar from the live vendor doc (`~/.grok/docs/user-guide/10-hooks.md`) before duplicating objects.
- Guard 2 must assert the double-fire is absent, not that twins exist.
- Do not freeze `grok --trust` as a runnable command; live CLI 1.0.29 has none. Use `/hooks` in-session.

## Related Issues

- See also: [2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md](2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md)
- Issue #8064 / draft PR #8061
