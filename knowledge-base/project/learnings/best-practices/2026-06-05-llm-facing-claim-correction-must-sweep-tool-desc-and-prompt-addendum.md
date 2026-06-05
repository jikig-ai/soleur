---
title: "Correcting an LLM-facing claim must sweep BOTH the tool description and the system-prompt addendum"
date: 2026-06-05
category: best-practices
module: apps/web-platform/server
tags: [mcp-tools, concierge, agent-native, prompt-engineering, c4]
related_pr: 4963
related_issue: 4964
---

# Correcting an LLM-facing claim must sweep BOTH the tool description and the system-prompt addendum

## Problem

The LikeC4 Code-tab Save honesty fix (#4963) needed to remove a false claim —
"Commits directly to the repo and **the diagram re-renders**" — that told the
Concierge agent its edit had visibly updated the diagram (it had not; the diagram
is precomputed and regenerates only out-of-band).

The plan correctly identified that the claim spanned "both write surfaces" (the UI
Save button AND the `edit_c4_diagram` MCP tool). The implementation corrected the
tool **description** in `server/c4-concierge-tools.ts`. But the SAME sentence was
independently re-authored a third time in `c4PromptAddendum` (built in
`server/cc-dispatcher.ts:~1472` and appended to `effectiveSystemPrompt`). After the
first-pass fix, the corrected tool description and the stale addendum **contradicted
each other in the same context window** — the agent was as likely to anchor on the
positive instruction ("the diagram re-renders") as on the corrected description, so
the honesty goal was not reliably achieved.

`git grep "diagram re-renders"` returned TWO hits; the first commit fixed one.
Caught by the `agent-native-reviewer` at post-implementation review, rated P1.

## Solution

When correcting any claim the model reads, grep the **whole** prompt-assembly path,
not just the tool definition. For an in-process MCP tool, the agent's mental model is
built from at least two independently-authored strings:

1. the `tool(name, description, …)` **description**, and
2. any **system-prompt addendum** the dispatcher appends when the tool is registered
   (`c4PromptAddendum` here; the pattern generalizes to any
   `effectiveSystemPrompt += …` capability blurb).

Both restate the same commit/render contract. Fix all of them in one change, and add
a negative-space regression gate that reads BOTH source files and asserts the false
literal is absent + the honest contract present (see
`test/c4-prompt-addendum-honesty.test.ts`). The durable fix is to single-source the
two strings from one shared constant so they cannot drift again — deferred here, but
worth doing when the surface is next touched.

## Key Insight

A tool's "description" is not the only place the model learns what the tool does.
Registration-time system-prompt addenda are a second, parallel source of the same
contract, in the SAME context window. Correcting one and not the other produces a
self-contradicting prompt that is worse than the original lie. Cheapest gate:
`git grep "<the exact claim>"` and require ≤0 stale hits across `server/*-tools.ts`
AND the dispatcher that assembles the system prompt.

## Session Errors

- **Bash CWD drift across worktree pipeline phases** — `git add apps/web-platform/…`
  failed (exit 128, pathspec mismatch) because CWD was already inside
  `apps/web-platform`; later `./node_modules/.bin/tsc` failed (exit 127) because CWD
  had drifted back to the worktree root after the review skill's root-relative bash.
  Recovery: prefix the call with an explicit `cd <abs-path> && …`.
  **Prevention:** already documented in the work skill ("chain `cd <worktree-abs-path>
  && <cmd>` in a single Bash call"); apply it to EVERY test/tsc/git invocation, since
  the Bash tool persists CWD and sibling skills reset it.
- **zsh glob `--include=*.ts`** — `grep … --include=*.ts` aborted with "no matches
  found" (zsh expands the glob before grep sees it). **Prevention:** quote the pattern
  (`--include='*.ts'`) or scope the path list instead.
- **test-design-reviewer returned no substantive output** (stalled, 0 tool uses).
  **Prevention:** known parallel-batch-stall class (review skill documents it);
  proceed with the agents that returned — coverage was absorbed by the others plus the
  verified RED→GREEN cycle.

## Tags
category: best-practices
module: apps/web-platform/server
