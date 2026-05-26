---
title: Linear MCP `extract_images` collapses cache + auth handler designs
date: 2026-05-12
category: integration-issues
module: mcp-linear-server
tags: [mcp, linear, multimodal, image-context, prompt-injection-of-context, redaction]
related_issue: "#3635"
related_pr: "#3631"
related_brainstorm: knowledge-base/project/brainstorms/2026-05-12-linear-issue-image-context-brainstorm.md
---

# Linear MCP `extract_images` returns viewable images directly — no cache, no auth handling

## Problem

Brainstorm for `/soleur:linear-fetch` started with a default assumption: to get a Linear issue's screenshot in front of the agent, we'd need to (a) fetch the markdown via `mcp__linear-server__get_issue`, (b) parse `uploads.linear.app/*` URLs out of it, (c) download the bytes with a Linear bearer token, (d) cache them somewhere — `/tmp` or under `knowledge-base/` — and (e) pass file paths to `Read` so the model sees them. That design pulls in: token boundary, gitignore rules, lifetime/cleanup, signed-URL credential handling, and a precommit guard against committed signed URLs.

The chat-attachments brainstorm (`knowledge-base/project/brainstorms/2026-04-11-chat-attachments-brainstorm.md`) reinforced this framing — its decision was "Agent SDK `query()` is string-only, so multimodal images must be written to workspace filesystem and referenced by path."

CTO challenged this with: "check what `mcp__linear-server__extract_images` actually returns before designing the cache."

## Solution

Loading the tool schema via `ToolSearch` revealed:

```
description: Extract and fetch images from markdown content. Use this to view
screenshots, diagrams, or other images embedded in Linear issues, comments, or
documents. Pass the markdown content (e.g., issue description) and receive the
images as viewable data.

parameters: { markdown: string }
```

"receive the images as viewable data" = the MCP server resolves Linear-authenticated URLs and **streams image bytes directly into the active model conversation**. The agent never needs to handle the Linear token, write image files to disk, or manage a cache. The flow collapses to:

1. Detect Linear ref in user input (regex `[A-Z]+-\d+` or `linear.app/.../issue/<ID>`).
2. Call `mcp__linear-server__get_issue(id)` → get markdown description.
3. Call `mcp__linear-server__list_comments(issueId)` → take 10 most-recent.
4. Concatenate description + comment bodies.
5. Call `mcp__linear-server__extract_images(markdown=<blob>)` → images appear in the conversation.

Zero filesystem, zero auth-handling, zero `/tmp` cache.

## Key Insight

When wiring an MCP server tool that delivers media, **read the tool's description before designing infrastructure around it**. MCP tools commonly broker authentication and content transport on the agent's behalf — the LLM doesn't have to. The chat-attachments brainstorm's "write to workspace filesystem" rule applied to a different transport (Agent SDK `query()` accepts strings only), not to native MCP image tools running inside the harness.

**Heuristic:** if an MCP tool is named `extract_*`, `fetch_*`, `read_*`, or `view_*` and the verb implies media surfacing, the default assumption should be "returns viewable data directly." Designs that add a filesystem cache on top of such tools likely have it backwards.

## Secondary Insight (redaction guard for Linear CDN URLs)

`uploads.linear.app/*` URLs returned by `get_issue` in the markdown body are **bearer credentials** (signed URLs valid for some window). Even though `extract_images` bypasses the filesystem, any code path that persists the *raw markdown* into a committed artifact (brainstorm.md, spec.md, PR body, learnings file, commit message) leaks a credential. The redaction guard isolates: "agent context" (full markdown with URLs intact, model-visible only) vs "persist-safe summary" (URLs replaced with `[linear-image: N attached]`). Second-tier defense: a pre-commit hook greps staged content for `uploads\.linear\.app` and blocks the commit.

This pattern generalizes: **any external SaaS that returns signed-URL attachments via MCP needs a two-form return convention** — full for context, redacted for persistence.

## Session Errors

- **`cd <relative-path>` after a prior persisted CWD change** — A multi-step Bash flow (`cd .worktrees/feat-X && bash ./draft-pr`) persisted the worktree CWD across Bash calls (per harness behavior: working dir persists, shell state does not). A subsequent `cd .worktrees/feat-X` resolved against the already-inside-worktree CWD and failed with "no such file or directory."
  - **Recovery:** switched to absolute paths.
  - **Prevention:** in compound/brainstorm flows that span multiple Bash calls, either (a) use absolute paths for `cd`, or (b) issue `pwd` first to verify CWD before a relative `cd`. Add this to the brainstorm/compound skill Sharp Edges if it recurs.

## Tags

category: integration-issues
module: mcp-linear-server
