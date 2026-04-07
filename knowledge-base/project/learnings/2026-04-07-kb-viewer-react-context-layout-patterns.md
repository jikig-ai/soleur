---
title: "KB viewer layout patterns: context-driven two-panel with App Router"
date: 2026-04-07
category: ui-bugs
tags:
  - next-js
  - react-context
  - app-router
  - rehype-highlight
  - layout
module: apps/web-platform
---

# KB Viewer Layout Patterns

## Problem

Building a two-panel file browser (sidebar tree + content area) in Next.js App Router where:

1. The layout fetches shared data (tree) and provides it via React context
2. Desktop shows both panels, mobile shows one at a time
3. Multiple review agents identified architectural issues in the initial implementation

## Key Findings

### 1. rehype-highlight strips custom className on code elements

When using a custom `code` component in react-markdown alongside `rehype-highlight`, the custom component receives `className` containing `hljs language-xxx` classes. If the custom component replaces `className` entirely (e.g., `className="text-xs text-neutral-300"`), all syntax highlighting classes are lost.

**Fix:** Style block code via a custom `pre` component (background, padding, font size). Let the `code` component preserve its `className` for block code (pass through `rehype-highlight`'s classes) and only apply custom styling for inline code.

### 2. Directory expand keys must include full path, not just name

When using a `Set<string>` to track expanded directories, using just `node.name` as the key causes collisions. Two directories named `docs/` at different tree depths share the same key — expanding one expands both.

**Fix:** Thread a `parentPath` prop through the recursive tree and construct keys as `parentPath/name`.

### 3. Math.random() in render causes hydration mismatches

Using `Math.random()` in skeleton loading components produces different values on server vs client render, causing React hydration warnings.

**Fix:** Use a static array of widths indexed by position.

### 4. useMemo for context value objects

Context values constructed inline (`{ tree, loading, error }`) create new object references on every render, causing all consumers to re-render even when values haven't changed. Wrap in `useMemo` with the actual dependencies.

### 5. Breadcrumb links to directories cause silent redirects

Non-leaf breadcrumb segments link to directory URLs (`/dashboard/kb/project/`), which the catch-all route redirects back to root (since only `.md` files are viewable). Make directory segments non-clickable spans.

## Session Errors

1. **Bash shell SIGABRT crash during review phase** — 5 parallel background review agents likely filled tmpfs with `.output` files, causing all bash commands to fail with exit code 134 (SIGABRT) for ~5 minutes. Recovery: agent output files were cleaned up. **Prevention:** The AGENTS.md rule about bounded output in subagents already covers this. The issue was the accumulated size of 5 concurrent agents, not any single unbounded command. Consider limiting parallel review agents to 3 when review findings are expected to be verbose.

## Tags

category: ui-bugs
module: apps/web-platform
