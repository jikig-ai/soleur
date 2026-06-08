---
title: "O_NOFOLLOW symlink-rejection tests must place the target INSIDE the workspace"
date: 2026-06-08
category: test-failures
module: web-platform/kb
tags: [testing, security, symlink, O_NOFOLLOW, toctou, vacuous-red, kb-share]
related_pr: feat-one-shot-share-document-not-conversation
---

# Learning: O_NOFOLLOW symlink-rejection tests must place the target INSIDE the workspace

## Problem

Writing the RED test for the new public C4 endpoint (`GET /api/shared/[token]/c4`),
the "symlinked model → 413" case asserted `413` but the route returned `400`.

The route guards a file read with two layers (mirroring
`app/api/kb/c4/project/route.ts`):

1. `isPathInWorkspace(jsonAbs, kbRoot)` — canonicalizes via `realpathSync` and
   checks containment. Returns `false` → **400 Invalid dir**.
2. `fs.open(jsonAbs, O_RDONLY | O_NOFOLLOW)` — atomically rejects a symlinked
   final component with **ELOOP → 413**.

My first test pointed the symlink at a target **outside** `kbRoot`
(`tmpWorkspace/real-model.json`). `realpathSync` resolved the link to that
outside path, so layer 1 rejected it with 400 — `O_NOFOLLOW` never ran. The
test was **vacuous on the guard it claimed to exercise**: it would still pass
even if `O_NOFOLLOW` were removed from the `fs.open` flags.

## Solution

Point the symlink target at a path **inside** the workspace
(`<dir>/real-model.json`). Then `realpathSync` resolves to an in-workspace path,
layer 1 passes, and `O_NOFOLLOW` becomes the **load-bearing** rejection that
produces the 413. Pair it with a **positive control** — a regular file at the
same path returns 200 — to prove the 413 is caused by the symlink-ness, not by
an incidental read failure.

```ts
// 413 case — target INSIDE workspace so isPathInWorkspace passes first
const realTarget = path.join(dirAbs, "real-model.json");
fs.writeFileSync(realTarget, JSON.stringify({ views: {} }));
fs.symlinkSync(realTarget, path.join(dirAbs, "model.likec4.json")); // → ELOOP → 413

// positive control — regular file at the same path → 200
writeModel(DIAGRAMS_DIR, { views: { context: {} } });            // → 200
```

## Key Insight

When two layered guards can both reject the same input with *different* status
codes, a test that targets the cheaper/earlier guard's rejection path proves
nothing about the later guard. To test the inner guard (`O_NOFOLLOW`), the
fixture must **satisfy every guard before it** (here: in-workspace containment)
so the inner guard is the only thing left that can fail. This is the
symlink-specific instance of the general "vacuous RED" trap: confirm the test
goes green-to-red when *only* the guard under test is removed.

Secondary pattern (the fix itself): extending an authenticated viewer to an
anonymous public surface requires a **parallel token-scoped data endpoint** —
the owner endpoint (`/api/kb/c4/project`) is auth-gated + caller-workspace-scoped,
so an anonymous viewer 401s. Resolve the workspace from the share row's
`workspace_id` (never a session), derive the resource dir server-side from
`dirname(document_path)` (never a client `?dir`), and serve a data-minimized
payload (omit `.c4` sources — Code-tab-only) to a read-only component variant.

## Session Errors

1. **CWD drift** — `cd: apps/web-platform: No such file or directory` on the
   first `vitest` invocation. The Bash tool does not persist CWD across calls;
   a prior `cd` had reset. **Recovery:** absolute paths / single
   `cd <abs> && <cmd>`. **Prevention:** already covered by the work skill's
   "chain `cd <worktree-abs-path> && <cmd>` in a single Bash call" rule — no new
   rule needed.
2. **Vacuous RED on the symlink test** (this learning's subject). **Recovery:**
   moved the symlink target inside the workspace + added a positive control.
   **Prevention:** captured here; routed to the work skill's vitest guidance.
3. **Pencil AppImage core-dump** (forwarded from plan phase) — handled by the
   headless CLI via `PENCIL_CLI_KEY`; one-off environment issue, no action.

## Tags
category: test-failures
module: web-platform/kb
