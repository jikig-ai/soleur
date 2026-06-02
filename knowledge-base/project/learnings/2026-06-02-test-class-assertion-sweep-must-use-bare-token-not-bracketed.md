---
title: Sweeping for tests that assert a Tailwind class must grep the bare token, not the bracketed form — regex-literal assertions escape the brackets
date: 2026-06-02
category: testing-patterns
module: web-platform/chat
tags: [tests, tailwind, grep-sweep, regex-literal, ci-caught, false-confidence]
feature: fix-chat-input-unified-box
pr: 4832
---

# Learning: class-assertion test sweeps must use the bare token

## Problem

Changing the chat-input textarea height class `min-h-[72px]` → `min-h-[40px]`,
I swept for tests asserting on it with
`grep "min-h-\[72px\]" apps/web-platform/test ...` and found only one file
(`chat-input.test.tsx`, which uses `toContain("min-h-[72px]")`). I updated it,
ran that suite green, and shipped. CI then failed on a **second** file,
`chat-input-auto-grow.test.tsx`, which asserts the same class via a regex
literal: `expect(textarea.className).toMatch(/min-h-\[72px\]/)`.

## Root cause

The two test styles store the token differently on disk:

- `toContain("min-h-[72px]")` → file bytes are `min-h-[72px]` (plain brackets).
- `toMatch(/min-h-\[72px\]/)` → file bytes are `min-h-\[72px\]` (backslash-escaped
  brackets, because `[` is a regex metachar).

A grep pattern `min-h-\[72px\]` matches the first (literal `[`/`]`) but **not**
the second (the file has an extra `\` before each bracket). So the literal-string
test matched and the regex-literal test was silently skipped — a sweep that
looks complete but isn't.

## How to apply

When updating a Tailwind/CSS class (or any bracketed token) that tests assert on,
sweep by the **bare, bracket-free substring** — `grep -rn "72px" apps/web-platform`
or `grep -rn "min-h-" …` — never the bracketed form. The bracketed form misses
both regex-literal assertions (`toMatch(/…\[…\]/)`) and any test that builds the
selector dynamically. Confirm the change end-to-end by running the **whole**
affected suite (`vitest run` for the package), not just the one file the first
sweep surfaced — a green single-file run after a narrow grep is false confidence.

Relates to [[wg-verified-work-ships-without-asking]]: "verified" means the full
affected suite is green, not one hand-picked file.
