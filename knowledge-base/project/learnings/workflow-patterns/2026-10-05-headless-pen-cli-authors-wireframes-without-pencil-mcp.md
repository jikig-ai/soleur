---
title: "Headless `pen` CLI authors .pen wireframes when Pencil MCP is absent (Devin CLI path)"
date: 2026-10-05
category: workflow-patterns
tags: [pencil, wireframe, brainstorm, devin-cli, headless]
related: ["wg-ui-feature-requires-pen-wireframe", "skills/pencil-setup", "skills/brainstorm"]
---

# Learning: headless `pen` CLI authors .pen wireframes when Pencil MCP is absent (Devin CLI path)

## Problem

Brainstorm Phase 3.55 hard-requires a `.pen` wireframe for any UI-surface
feature (`wg-ui-feature-requires-pen-wireframe`), and the ux-design-lead agent
definition assumes `mcp__pencil__*` tools. On the Devin CLI harness there is no
Pencil MCP server — the skill's documented fallbacks (`check_deps.sh --auto`,
`claude mcp list | grep pencil`) are Claude-Code-shaped. A first reading says
hard-block.

## Solution

The host already carries an installed + authenticated headless Pencil CLI
(`pen`, `@pen.dev/cli`, `pen status` → Active). It authors `.pen` files
one-shot, no MCP and no REPL needed:

```bash
pen --out <abs-path>.pen --prompt "<design brief>" --export <abs-path>.png
pen --in <file>.pen --out <file>.pen --prompt "<revision>"   # iterate
pen status   # auth check — Active session works without PENCIL_CLI_KEY
```

A `subagent_general` acting as ux-design-lead produced a valid 88 KB,
three-frame `.pen` + PNG export this way in this session (wireframe for the
Scope-Grants "Agent web access" toggle,
`knowledge-base/product/design/settings/agent-web-access.pen`). Spawn prompt
must carry: the absolute WORKTREE path (files must land inside the worktree,
not the main checkout), "no mcp__pencil__ tools — use `pen` one-shot mode",
and the output-path convention `knowledge-base/product/design/{domain}/`.

## Key Insight

The hard-block predicate is "Pencil unsatisfiable", not "Pencil MCP absent" —
the headless CLI is a third surface that satisfies it. Verify `pen status`
before ever emitting the Phase 3.55 hard-block message on Devin.

## Session Errors

1. `gh issue create` rejected: `--body-file` given a worktree-relative path —
   the hook resolves against its own CWD. **Prevention:** always pass an
   absolute path to `--body-file` (the skill text already prescribes this).
2. `gh issue create` rejected: `Fix-Size:` written as prose instead of the
   literal `N lines / M files` shape the gate anchors on. **Prevention:** the
   gate message states the format verbatim — copy it exactly, do not
   paraphrase measured sizes into sentences.
