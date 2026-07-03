---
title: "A regex containing */ inside a JSDoc /** */ block comment closes the comment early (esbuild transform failure)"
date: 2026-07-03
category: build-errors
module: apps/web-platform/test
tags: [esbuild, vitest, jsdoc, block-comment, regex, typescript]
issue: 5920
---

# Learning: `*/` inside a JSDoc block comment closes it early — esbuild "Expected ; but found <token>"

## Problem

Writing a new structural test (`apps/web-platform/test/supabase-migrations/byok-rpc-body-markers.test.ts`)
whose leading `/** … */` JSDoc documented the comment-strip regex inline as
`` `/--[^\n]*/g` removes line comments … ``. Running the file failed at
collection with an esbuild transform error, NOT a vitest assertion:

```
Error: Transform failed with 1 error:
…/byok-rpc-body-markers.test.ts:39:8: ERROR: Expected ";" but found "throw"
```

The cited line/column pointed *into the docstring*, at prose that is obviously
not code. The real cause is elsewhere on an earlier line.

## Root Cause

The literal two-character sequence `*/` **terminates a `/* … */` block comment**
regardless of surrounding backticks or Markdown fences — a block comment has no
concept of "inline code". The docstring contained the regex `/--[^\n]*/g`; the
`*/` in `…]*/g` closed the JSDoc comment early. Everything after it (the rest of
the prose, plus the real `throw`-containing sentence) was then parsed as
TypeScript, so esbuild choked on the first word it could not parse and reported
a column deep inside what the author still thought was a comment.

The error location is a red herring: it marks where the *post-comment garbage*
first fails to parse, not where the comment was accidentally closed.

## Solution

Never write a literal `*/` inside a `/* … */` / `/** … */` block comment. When
documenting a regex (or any string) that contains `*/`:

- describe it in prose — "the `--` to end-of-line regex" instead of pasting
  `/--[^\n]*/g`; or
- move the example to a `//` line comment (line comments have no close token); or
- break the sequence (`* /`) if you must show it — but prose is cleaner.

The regex itself is fine in *code* (`sql.replace(/--[^\n]*/g, "")` on line 100
compiled without issue) — the hazard is exclusively the block-comment context.

Cheapest detection: after authoring a block comment that mentions a regex,
`grep -nF '*/g' <file>` (or `*/` more broadly) and confirm every hit is real
code, not comment prose.

## Key Insight

An esbuild/tsc "Expected ; but found X" whose reported line points at obvious
prose inside a docstring is almost always a **prematurely-closed block comment**
upstream — look for a stray `*/` (commonly from a regex ending in `*/`, `**/`,
or a glob like `foo/**/*`) earlier in the same comment, not at the reported line.

## Session Errors

- **esbuild transform failure from `*/g` in a JSDoc comment** — Recovery:
  reworded the docstring to prose ("the `--` to end-of-line regex"), removing the
  literal `*/`. Prevention: this learning + a bullet on the work skill's
  TS-test-authoring guidance; `grep -nF '*/' <file>` gate after writing regex-
  documenting block comments.
- **Probe-harness mock `$`-anchor miss (one-off)** — a throwaway `/tmp`
  fixture-exercise harness extracted the fn name with `grep -oE "[a-z_]+$"`
  against a line ending in `'`, so the `$` anchor never matched and every
  scenario hit the "function-not-found" branch instead of the marker-grep path.
  Recovery: `sed -E "s/.*proname = '([a-z_]+)'.*/\1/"`. One-off (test-of-test,
  never in shipped code); no fix/issue.

## Tags
category: build-errors
module: apps/web-platform/test
