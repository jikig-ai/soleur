---
title: A `{/* */}` JSX comment beside an expression inside a parenthesized ternary branch breaks parsing
date: 2026-06-09
category: best-practices
module: apps/web-platform/components
tags: [jsx, tsx, react, syntax, ternary]
pr: 5076
---

# Learning: `{/* */}` JSX comments are child-position only — don't put them in a `( … )` ternary branch

## Problem

Adding an inline rationale comment above a `<form>` that lives in the `else`
branch of a JSX ternary produced a cascade of opaque TypeScript syntax errors:

```
error TS1005: ')' expected.
error TS1382: Unexpected token. Did you mean `{'>'}` or `&gt;`?
error TS17002: Expected corresponding JSX closing tag for 'div'.
```

The offending edit:

```tsx
{status === "success" ? (
  <p>…</p>
) : (
  {/* pt-0.5 keeps the focus ring off the clip boundary */}   // ← breaks it
  <form …>…</form>
)}
```

## Root cause

A `{/* … */}` JSX comment is **not** a general-purpose comment — it is a
*child-position* construct (an empty JSX expression container). The parens of a
ternary branch `( … )` may contain exactly **one** expression. Writing
`{/* … */}<form/>` inside them is two sibling expressions, which is a syntax
error. The same `{/* */}` is perfectly valid one level down, *as a child* of a
JSX element (`<div>{/* ok here */}<form/></div>`), because there the parser is
already in child position.

## Solution

Inside a parenthesized ternary branch (or anywhere you need a comment beside a
single returned element), use a **plain block comment** — no braces:

```tsx
) : (
  /* pt-0.5 keeps the focus ring off the clip boundary */
  <form …>…</form>
)}
```

`( /* comment */ <form/> )` is a single expression with a leading block comment —
valid. Alternatives: move the `{/* */}` comment to be the first *child* of an
element, or hoist the comment to a normal `//` line above the whole `{ternary}`.

## Key insight

`{/* */}` works as a JSX *child*, not as a free-standing statement. The "it
breaks in a ternary branch" symptom is the tell: the branch's `( … )` wants one
expression, and the JSX-comment container is a second one. Reach for a bare
`/* */` block comment in expression position; reserve `{/* */}` for between an
element's children.

## Session Errors

1. **`{/* */}` JSX comment in a ternary `else` branch → TS1005 / TS1382 / TS17002**
   (this learning). Recovery: switched to a plain `/* */` block comment.
   Prevention: in expression/ternary-branch position use `/* */` (no braces);
   `{/* */}` is for child position only. tsc catches it immediately — run
   `tsc --noEmit` right after the edit rather than discovering it at suite run.
2. **`${PIPESTATUS[0]}` after `| head` rendered empty** — transient shell quirk;
   re-ran `tsc` with `echo "tsc-exit=$?"`. One-off, no recurrence vector.
