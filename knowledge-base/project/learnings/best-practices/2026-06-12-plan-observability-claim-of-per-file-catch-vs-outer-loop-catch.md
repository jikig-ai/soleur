---
title: "Plan Observability claim of a per-file catch ≠ the code's outer-loop catch"
date: 2026-06-12
category: best-practices
module: apps/web-platform/app/api/kb/c4/project
tags: [error-handling, test-design, plan-vs-code, best-effort-loop, c4]
pr: "feat-one-shot-likec4-code-panel-file-dropdown"
---

# Learning: a plan's "inner per-file catch swallows it" claim must be verified against the actual try/catch granularity before writing a resilience test

## Problem

While surfacing `README.md` read-only in the C4 Code panel (widening the owner
`/api/kb/c4/project` sources filter to `f.endsWith(C4_SOURCE_EXT) || f === "README.md"`),
the plan's `## Observability` section asserted:

> "the inner per-file catch already swallows (sources optional); README simply
> absent from the dropdown"

A route test was written against that claim: plant a **symlinked** `README.md`
(O_NOFOLLOW → ELOOP) and assert the response still 200s **with `model.c4` present**
in `sources`. It failed (1/20):

```
× rejects a symlinked README ... expect("model.c4" in body.sources).toBe(true)  // got false
```

## Root cause

There is **no inner per-file catch**. The sources read is a single loop wrapped
by ONE outer best-effort `try/catch` (`route.ts:117-135`):

```ts
const sources: Record<string, string> = {};
try {
  for (const file of (await fs.readdir(dirAbs)).filter(...).sort()) {
    const abs = path.join(dirAbs, file);
    if (!isPathInWorkspace(abs, kbRoot)) continue;
    let h;
    try { h = await fs.open(abs, O_RDONLY | O_NOFOLLOW); sources[file] = await h.readFile("utf8"); }
    finally { await h?.close(); }   // <-- finally, NOT catch
  }
} catch { /* sources are optional for rendering */ }
```

The inner `try` has only a `finally` (handle close), no `catch`. So an ELOOP from
ANY file throws clear out of the loop to the **outer** catch — aborting every
not-yet-read file. Because files are `.sort()`ed and `"README.md"` (ASCII `R`=0x52)
sorts before `"model.c4"` (`m`=0x6D), the symlinked README throws first and
`model.c4` is never read → `sources` ends up `{}`.

## Key insight

A plan's prose description of error-handling **granularity** ("per-file", "inner
catch", "degrades to that field absent") is a hypothesis to verify against the
actual try/catch nesting — not a fact to encode in a test. The real behavior here
is whole-loop-abort, and it is **identical** for `.c4` and `README.md` (the plan
correctly mandated "keep the README read identical to the `.c4` read"). The honest
test asserts what the guard actually proves — O_NOFOLLOW rejects the symlink, the
content never leaks, and the response degrades to 200 (sources optional) — without
over-claiming per-file resilience that the code does not implement:

```ts
expect(res.status).toBe(200);
expect("README.md" in body.sources).toBe(false);
expect(JSON.stringify(body.sources)).not.toContain("secret");
```

Generalizable: when a plan claims "failure of X degrades to X-absent (others
unaffected)", grep the implementing loop for an **inner** `catch` (not just
`finally`) before writing a "siblings survive" assertion. No inner catch ⇒ one
bad element aborts the batch.

## Session Errors

1. **Symlinked-README test over-specified per-file resilience** — asserted
   `model.c4` survives a symlinked README. **Recovery:** read the route's loop,
   saw the inner `try` has only `finally`; rewrote the test to assert the actual
   contract (200 + README absent + no content leak). **Prevention:** this learning
   — verify inner-catch presence before asserting batch-sibling survival.
2. **`gh` offline during the planning subagent** — overlap check + PR-state premise
   re-queued to /work. **Recovery:** /work re-ran `gh issue list --label code-review`
   (online), zero matches. **Prevention:** already the plan's documented behavior
   (re-run at /work time); one-off network state.
3. **CWD drift on a Bash `sed` call** — `sed … components/icons/index.tsx` ran from
   the wrong dir (Bash tool doesn't persist CWD). **Recovery:** re-ran with
   `cd <worktree>/apps/web-platform &&`. **Prevention:** existing guidance to chain
   `cd <abs-path> && <cmd>` in one Bash call.
