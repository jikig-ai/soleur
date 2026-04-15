---
title: Narrow-type filter trap when a corpus expands in one place but not another
date: 2026-04-15
category: logic-errors
module: apps/web-platform/server/kb-reader
issue: 2230
pr: 2281
tags: [pattern, duplication, type-filter, kb]
---

# Learning: Narrow-type filter trap when the corpus expands in one place but not another

## Problem

KB search was hardcoded to `.md` files (`entry.name.endsWith(".md")` in `collectMdFiles`).
The upload route had already expanded to accept 9 extensions (PDF, DOCX, CSV, TXT, PNG,
JPG, JPEG, GIF, WEBP). Uploads worked, files appeared in the file tree, but search
silently dropped every non-markdown file. The user's screenshot showed a PDF upload
returning only `vision.md` when they searched for it.

The bug had been latent since the upload extension set expanded — no test caught it
because the tests asserted the broken behavior ("searchKb returns only .md files").

## Root Cause

Two narrow type filters encoded the "allowed file types" concept:

1. `apps/web-platform/app/api/kb/upload/route.ts` — `ALLOWED_EXTENSIONS` (the gate for writes)
2. `apps/web-platform/server/kb-reader.ts` — `collectMdFiles` hardcoding `.md` (the gate for reads/search)

When one expanded and the other didn't, the feature silently degraded. No runtime error,
no type error, no test failure (because tests were written against the original narrow
filter and never updated when upload expanded).

## Solution

Two-mode search with a single source of truth:

1. Extract `KB_UPLOAD_EXTENSIONS` and `KB_TEXT_EXTENSIONS` to `apps/web-platform/lib/kb-constants.ts`.
2. Upload route derives `ALLOWED_EXTENSIONS` from the shared constant.
3. `kb-reader.ts` derives `FILENAME_SEARCHABLE` and `CONTENT_SEARCHABLE` from the same constant.
4. Filename match runs on the full allowlist; content match runs on the text subset only
   (binary text extraction deferred to the RAG pipeline).
5. New `SearchResult.kind: "content" | "filename"` field lets the UI label filename-only hits.

See PR #2281 for the full diff.

## Key Insight

**When you widen an allowlist in one place, grep for every filter that encodes the same
concept.** If two filters express the same "what's allowed" domain concept in different
shapes (a `Set` of bare strings vs a call to `endsWith`), add a shared constant BEFORE
the next expansion. The cost of extracting the constant up-front is tiny; the cost of
a silent feature regression is a P1 user-visible bug.

**Tests that assert the broken behavior are worse than no tests.** The two deleted tests
(`does not search binary/non-.md files`, `collectMdFiles still returns only .md files`)
locked in the bug as "correct". Any test that says "feature X does NOT do Y" must be
re-examined when the product requirement for Y changes.

## Prevention

- New upload types MUST extend `KB_UPLOAD_EXTENSIONS` in `lib/kb-constants.ts`, not a
  local Set in the upload route.
- Search corpus changes MUST flow through the same constant — never hardcode a fresh
  extension list in a new reader.
- When a test asserts a feature does NOT do something, include a comment explaining
  WHY that restriction exists. "This test encodes a temporary limitation, remove when
  X ships" is better than a silent guardrail.

## Session Errors

- **Security reminder hook false-positive on RegExp method calls** — Recurred twice
  (deepen-plan + implementation). The hook pattern-matches the `exec` substring and
  flags it as `child_process` shell invocation even when the method is the RegExp
  instance method on a local regex. Recovery: switched to `String.matchAll`, which
  has the nice side effect of eliminating manual `lastIndex` reset.
  **Prevention:** Refine `security_reminder_hook.py` to ignore RegExp method invocations
  (where the preceding token is a RegExp identifier like `regex`, `re`, or a regex
  literal). File a tracking issue so the next author doesn't rediscover it.

- **CWD desync between Bash calls** — After a `cd apps/web-platform` in one Bash call,
  the next Bash session inherited that CWD. A follow-up `cd apps/web-platform && ...`
  failed with "No such file or directory".
  **Prevention:** Bash tool calls inherit CWD from the previous call in the same session.
  Skill instructions that use relative paths (`cd <subdir>`) should be converted to absolute
  paths. The work skill's Phase 2 already has this via worktree-absolute paths; carry
  through in ship/qa/compound.

- **GitHub label `type/test` does not exist** — `gh issue create --label "type/test"`
  failed. The available types are `type/bug`, `type/chore`, `type/question`, `type/feature`,
  `type/security`.
  **Prevention:** Update the review skill's issue-creation reference to list actual
  available labels rather than suggest `type/test`. File as a skill-instruction edit.

- **Task tool unavailable in deepen-plan skill context (forwarded)** — Parallel review
  sub-agents couldn't be spawned from within deepen-plan; deepening was done inline.
  **Prevention:** Either expose Task in deepen-plan's tool allowlist, or remove the
  "spawn parallel review sub-agents" guidance from the skill to match reality.

## Cross-References

- PR #2281 — this fix
- Issue #2230 — original bug report with screenshot
- Issue #2332 — workflow feedback tracking (session errors → skill/hook fixes)
- Learning `2026-04-07-promise-all-parallel-fs-io-patterns.md` — per-callback RegExp pattern
- Learning `2026-04-07-symlink-escape-recursive-directory-traversal.md` — enumeration guard
- Spec `knowledge-base/project/specs/feat-kb-rag-evaluation/spec.md` — deferred binary text extraction
