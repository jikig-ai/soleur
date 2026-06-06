---
title: "Render off-tree: return bytes (caller owns persistence) and drop the TOCTOU guard with the re-read it protected"
date: 2026-06-05
issue: 4976
pr: 4979
category: best-practices
module: apps/web-platform/server/c4-render.ts, c4-writer.ts
tags: [refactor, observability, security, toctou, git-reconcile, producer-consumer]
---

# Learning: render off-tree — return bytes, and remove TOCTOU hardening together with the re-read it guarded

## Problem

A server render helper (`renderC4Model`, `apps/web-platform/server/c4-render.ts`)
validated a `likec4 export json` artifact in a temp dir and then **published it
onto the tracked working-tree path** (`<diagramsDir>/model.likec4.json` via
`copyFile`→`rename`). Its caller (`rerenderAndCommit`, `c4-writer.ts`) re-opened
that tracked file (`open(O_RDONLY | O_NOFOLLOW)` + fd-stat 4 MB cap + `readFile`),
committed the bytes via the GitHub Contents API, and re-synced the clone.

That in-place write was a **reconcile dirty-tree churn source** (#4976):
- Success path: every `.c4` save left the working tree dirty, so the subsequent
  `git pull --ff-only` aborted `non_fast_forward` → a gated `reset --hard`
  self-heal fired on every save (wasteful; silenced-to-error only after #4972).
- Failure path: any early-return/throw after the render-write stranded the
  uncommitted file, dirtying the NEXT webhook reconcile (the original Sentry
  symptom 9ccf1d86 that #4972 only de-noised).

## Solution (Option A — render off-tree)

`renderC4Model` now **returns the validated bytes** (`{ ok, durationMs, json }`)
instead of writing the tracked path; `rerenderAndCommit` commits `render.json`
directly and the existing `op:"manual"` resync `git pull --ff-only` (now clean →
fast-forwards) brings the committed JSON to disk where `GET /api/kb/c4/project`
(the sole on-disk reader) serves it. The render never touches a tracked path, so
the dirty-tree source is removed **by construction**.

Two non-obvious moves that the multi-agent review confirmed correct:

1. **Removing the on-disk re-read lets you remove its O_NOFOLLOW/TOCTOU guard —
   the surface is *gone*, not merely unguarded.** The `open(O_NOFOLLOW)`+fd-stat
   hardening (CodeQL `js/file-system-race`) existed *only* because the writer
   re-read a tracked file a planted symlink could swap. Once the bytes come back
   in-process there is no on-disk round-trip to harden. The 4 MB cap moves to
   `Buffer.byteLength(render.json, "utf8")` — measuring the *exact* bytes about
   to be committed, strictly more accurate than the old `stat.size`. (The reader
   that still touches disk — `GET /project` — keeps its own O_NOFOLLOW.)
2. **Return the raw validated `utf8` string, never a re-`JSON.stringify`.** The
   committed bytes must be byte-identical to what `likec4` produced and you
   validated — re-encoding risks key-order/whitespace drift. Pin it with a test
   that base64-decodes the GitHub PUT `content` back to the returned string.

## Key Insight

When a producing helper writes its output onto a tracked/destination path and a
consumer re-reads it, the in-place write is the smell. **Return the bytes and let
the caller own persistence** — this is usually the codebase-canonical shape
(here `pdf-linearize.ts`, the helper's own cited precedent, already returned
`{ ok, buffer }`). Option A (remove the source by construction) beats Option B
(restore-on-every-exit / `git checkout --`), which re-introduces git mutations on
the hot path and leaves a wide defensive exit matrix.

Corollary for reviewers/refactorers: **a security guard is only load-bearing
while the thing it guards exists.** When you delete a re-read/round-trip, audit
whether its TOCTOU/symlink hardening is now guarding nothing — keeping it is
cargo-cult, removing it (with the re-read) is the correct net-reduction. Confirm
with a SAST pass that no NEW file-system-race pattern was introduced elsewhere.

Test-guard note: a `.not.toHaveBeenCalled()` spy on a symbol the source no longer
imports is near-vacuous. Because `vi.mock("node:fs/promises", () => fsMock)`
replaces the WHOLE module, keep the spy AND add the *most likely* regression
shape (`writeFile`) so the guard catches a re-introduced in-place publish in any
form, not just the exact prior `copyFile`+`rename`.

## Session Errors

1. **(forwarded) Plan write-hook blocks self-corrected.** The IaC-routing gate
   fired on negation prose in the plan ("introduces no `doppler secrets set`…");
   reworded + added an `iac-routing-ack`. An initial plan write targeted the
   bare-root synced mirror instead of the worktree. — Recovery: redirect to the
   worktree path. — Prevention: already-enforced by the plan subagent's Step-0
   CWD-verification guard, which caught the mirror write.
2. **(forwarded) `Task` tool absent from the planning subagent's deferred-tool
   set**, so deepen-plan ran gates 4.6–4.9 + verify-the-negative + precedent-diff
   directly instead of via fan-out agents. — Recovery: ran them inline; plan
   quality unaffected. — Prevention: one-off harness tool-set config; no workflow
   change warranted.
3. **`git grep --include='*.ts'` failed twice** ("unknown option `include`") — I
   used GNU-grep syntax. — Recovery: switched to the pathspec form
   `git grep -nE '<pat>' -- '*.ts'`. — Prevention: `git grep` scopes by trailing
   pathspec, not `--include`; reach for `-- '*.ext'` (or `:(glob)`).
