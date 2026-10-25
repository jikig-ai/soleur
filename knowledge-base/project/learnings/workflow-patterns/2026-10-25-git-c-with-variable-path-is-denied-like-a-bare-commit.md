---
title: "Devin commit gate: `git -C \"$VAR\"` is denied exactly like a bare `git commit` — the -C path must be a literal"
date: 2026-10-25
category: workflow-patterns
tags: [devin, worktree, commit-gate, hooks, one-shot]
---

# Learning: `git -C "$VAR"` is denied like a bare commit — the -C path must be literal

## Problem

The Devin worktree-commit convention (recorded in
`2026-10-24-devin-one-shot-parent-owns-agent-spawning-gates.md`) is "use `git -C
<worktree-abs> commit`". In the #10904 one-shot run, BOTH the parent session and
the work-phase subagent first wrote the conventional shell form —
`git -C "$PWD" commit` and `git -C "$WT" commit` — and both were denied:

```
BLOCKED: cannot determine which repository this git commit may target (the
path '$PWD' contains an expansion ...) so the staged content was NOT scanned
```

The subagent's variant failed differently and worse: `context-reviewed-gate`
resolved the staged delta against the MAIN repo's index, so it scanned (and
nearly attributed) a sibling session's staged files, not the worktree's. The
deny path is therefore not just "commit refused" — under one hook arm the
wrong index is read.

**Prevention:** write the literal absolute path in every `-C` operand; never a
variable, `$(...)`, backtick, `~`, or `cd -` — the hook's own denial message
enumerates the exact rejected forms. Subagent prompts must inline the literal
path, not tell the subagent to derive it.

## Solution

For worktree commits on Devin (parent or subagent), the operand is the literal
path: `git -C /data/.../<worktree> commit ...`. When briefing a subagent, embed
the absolute worktree path in the prompt text so the variable form is never
generated.

## Key Insight

The hook cannot expand variables because it scans the COMMAND STRING, not the
resolved command — so "the convention is `git -C`" is necessary but not
sufficient; the convention is `git -C <literal>`.

## Session Errors

1. Parent session: `git -C "$PWD" commit` denied — variable form unreadable by
   the gate. **Prevention:** literal path, per above.
2. Work subagent: `git -C "$WT" commit` denied; context-reviewed-gate scanned
   the main repo's index (wrong-index read). **Prevention:** same; the subagent
   prompt now inlines the literal path — this run's prompt DID carry it, and
   the subagent still tried the variable form first, so flag it as load-bearing
   in prompts, not as a footnote.
3. Plan subagent: one markdownlint MD004 (`+` continuation read as a
   plus-bullet) found and fixed pre-commit. **Prevention:** none — lint caught
   it in-time (one-off).

## Tags

devin, worktree, commit-gate, hooks
