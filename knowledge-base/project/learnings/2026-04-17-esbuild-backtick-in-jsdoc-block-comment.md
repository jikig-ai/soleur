---
date: 2026-04-17
category: build-errors
module: apps/web-platform
tags: [esbuild, vitest, jsdoc, typescript]
related_pr: 2517
---

# Learning: esbuild transform rejects backtick-containing JSDoc block comments

## Problem

In PR #2517 (kb-serve refactor), vitest failed at transform with:

```
ERROR: Expected ";" but found "cachedVerdict"
85 |   * Verdict-cache + hash-stream + serve orchestration for shared binary
86 |   * files. Returns ONLY a Response — no side-channel fields like
87 |   * `cachedVerdict` or `logEmitted`. Log emission happens inside the helper
     |      ^
88 |   * using the caller's logger so field names, events, and codes stay exact.
```

The JSDoc block had legitimate markdown:

```ts
/**
 * Verdict-cache + hash-stream + serve orchestration for shared binary
 * files. Returns ONLY a Response — no side-channel fields like
 * `cachedVerdict` or `logEmitted`. Log emission happens inside the helper
 */
export async function serveBinaryWithHashGate(...)
```

Vitest's esbuild transform pass parsed the backtick inside the block comment
as the start of a template literal, then demanded a `;` before `cachedVerdict`.
`tsc --noEmit` was happy; only the esbuild-based vitest transform failed.

## Solution

Replace `/** ... */` blocks containing backtick-wrapped identifiers or
em-dashes (`—`) with `//` line comments, or strip the backticks:

```ts
// Verdict-cache + hash-stream + serve orchestration for shared binary files.
// Returns ONLY a Response — no side-channel fields. Log emission happens
// inside the helper using the caller's logger so field names stay exact.
export async function serveBinaryWithHashGate(...)
```

Line comments survive because esbuild treats them as opaque whitespace.

## Key Insight

The difference between `/** ... */` and `// ...` for esbuild is that the
block-comment variant still gets a limited intra-token scan (for JSDoc tag
extraction). Backticks can trip that scanner even when the comment is not
position-sensitive code. Standard TS/Node parsers are lenient here; vitest
+ esbuild is not.

**Prevention:** When writing JSDoc that quotes identifiers or uses markdown
inline code (``` ` ```), either use line comments or escape the backtick.
Smoke-test by running the single affected test file immediately after the
edit: `./node_modules/.bin/vitest run test/<file>.test.ts` surfaces the
transform error in <1s.

## Session Errors

1. **Worktree created with long name silently disappeared.**
   `worktree-manager.sh --yes create feat-one-shot-kb-serve-binary-helpers`
   reported success but the directory was not present when the next Bash
   call tried to `cd` into it. Recreating with the shorter name
   `feat-kb-serve-binary-helpers` succeeded.
   Recovery: re-run the create command with a shorter branch name.
   Prevention: constrain worktree branch names to ≤40 chars, or have
   `worktree-manager.sh create` validate the directory exists before
   printing the success banner.

2. **`draft-pr` command failed from bare repo root.**
   `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh draft-pr`
   errored with "Cannot run from bare repo root (no working tree available)."
   Recovery: cd into the worktree dir and re-run. Safe because the script
   already errors loudly — this is working as intended.
   Prevention: one-shot's step 0c could emit the `cd` in the same Bash call:
   `cd <worktree-path> && bash .../worktree-manager.sh draft-pr`. The skill
   currently assumes the shell's CWD persists across Bash tool calls, which
   it does NOT.

3. **esbuild/vitest transform rejected backtick-in-JSDoc-block.**
   Recovery: switched block comments to line comments.
   Prevention: see above section.

## Tags

category: build-errors
module: apps/web-platform/server
