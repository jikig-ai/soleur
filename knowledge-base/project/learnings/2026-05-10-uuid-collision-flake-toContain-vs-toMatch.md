---
name: UUID-collision flake — not.toContain("b.png") false-positive
description: Loose substring assertion on attachment context fired when a.png's UUID-suffixed path contained "b.png"
type: test-failures
tags: [test-flake, uuid, vitest, attachment-pipeline]
---

# Learning: UUID-collision flake — `not.toContain("b.png")` false-positive

## Problem

`apps/web-platform/test/cc-attachment-pipeline.test.ts:233` asserted:

```ts
expect(attachmentContext).not.toContain("b.png");
```

The attachment context includes a saved-path line like:

```
- a.png (image/png, 1024 bytes): /workspace/u1/attachments/<uuid1>/<uuid2>.png
```

When `<uuid2>` happened to end in characters that form `b.png` (e.g. `...42eb.png`), the loose `.toContain("b.png")` substring scan matched inside the UUID suffix and the assertion fired as a false-positive.

## Solution

Replace the loose substring check with a regex anchored to the markdown bullet structure:

```ts
// Before (flaky)
expect(attachmentContext).not.toContain("b.png");

// After (stable)
expect(attachmentContext).not.toMatch(/^- b\.png/m);
```

The `^` + multiline flag anchors to line-starts, so only a bullet entry whose filename is literally `b.png` will match — UUID path suffixes cannot collide.

## Key Insight

`toContain` scans the entire string including file-path components. When the asserted substring is a short filename (≤10 chars) and the context includes long UUID-suffixed paths, collision is probabilistic but real. Anchor assertions to structural markers (line-start, bullet prefix, explicit separator) to make them collision-proof.

## Session Errors

**worktree-manager.sh exited 128 on `git fetch origin main`** — Recovery: worktree was still created correctly; the fetch step is best-effort and non-blocking in CI environments without remote access. Prevention: none needed — the existing `hr-when-a-command-exits-non-zero-or-prints` rule covers investigation; this specific failure class is benign and already understood.

## Tags

category: test-failures
module: cc-attachment-pipeline
