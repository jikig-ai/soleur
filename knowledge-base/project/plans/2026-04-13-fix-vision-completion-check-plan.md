---
title: "fix: Vision foundation card shows green checkmark for stub files"
type: fix
date: 2026-04-13
---

# fix: Vision foundation card shows green checkmark for stub files

## Overview

The Command Center dashboard marks the Vision foundation card as completed
(green checkmark) when `overview/vision.md` merely *exists*, even if the file
contains only a title, a placeholder instruction, and/or a PDF reference. The
completion detection must validate that the document has meaningful content
before showing the green checkmark.

## Problem Statement

The dashboard page (`apps/web-platform/app/(dashboard)/dashboard/page.tsx`)
derives foundation-card completion from a pure file-existence check:

```typescript
// Line 153-157
const foundationCards: FoundationCard[] = FOUNDATION_PATHS.map((f) => ({
    ...f,
    done: kbPaths.has(f.kbPath),
}));
```

`kbPaths` is a `Set<string>` of relative paths returned by the
`/api/kb/tree` endpoint. The `buildTree` function in `server/kb-reader.ts`
already calls `fs.promises.stat()` on every file (to populate `modifiedAt`)
but does not include `size` in the response.

Meanwhile, `server/vision-helpers.ts` already defines a 500-byte threshold
for "minimal" vision documents in `buildVisionEnhancementPrompt`. The
dashboard UI has no access to this signal.

### Scenarios that produce false-positive completions

1. **Start Fresh onboarding:** `tryCreateVision` writes `# Vision\n\n{short
   idea}\n`. A 30-word idea produces ~200 bytes -- well below meaningful
   content.
2. **Existing repo with stub:** User connects a repo that has a template
   `vision.md` with a title, placeholder instruction, and an attached PDF
   link. File exists, so it shows as complete.
3. **Agent partially writes:** CPO agent starts writing but the conversation
   is interrupted. A partial file under 500 bytes is misleadingly shown as
   done.

This same bug can affect **all four foundation cards** (Vision, Brand
Identity, Business Validation, Legal Foundations), though Vision is the most
commonly hit because `tryCreateVision` creates the stub automatically.

## Proposed Solution

Extend the KB tree API to include `size` (already available from the existing
`stat()` call) and apply a minimum-size threshold on the client to distinguish
stubs from real content. This approach:

- Requires minimal server changes (one field addition to `TreeNode`)
- Requires no additional API calls or endpoints
- Aligns with the existing 500-byte threshold in `buildVisionEnhancementPrompt`
- Is generalizable to all foundation cards

### Architecture

```
/api/kb/tree  -->  buildTree() adds `size` field to TreeNode
                         |
                    Dashboard page reads size from tree response
                         |
                    Foundation card `done` = file exists AND size >= threshold
```

### Implementation

#### 1. Add `size` to `TreeNode` interface and `buildTree` output

**File:** `apps/web-platform/server/kb-reader.ts`

- Add `size?: number` to the `TreeNode` interface
- In the `mapWithConcurrency` callback (line ~181-193), the `stat` is already
  being called. Add `size: stat.size` to the returned `TreeNode`

```typescript
// Current:
return {
  name: entry.name,
  type: "file" as const,
  path: path.relative(effectiveTopRoot, fullPath),
  modifiedAt,
  extension: ext || undefined,
};

// Updated:
const stat = await fs.promises.stat(fullPath).catch(() => null);
return {
  name: entry.name,
  type: "file" as const,
  path: path.relative(effectiveTopRoot, fullPath),
  modifiedAt: stat?.mtime.toISOString(),
  size: stat?.size,
  extension: ext || undefined,
};
```

#### 2. Add size to `flattenTree` output on the dashboard

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

Change `kbPaths` from `Set<string>` to `Map<string, { size?: number }>` so
the dashboard knows both existence and size. Update `flattenTree` to populate
the map.

```typescript
// Current:
function flattenTree(node: TreeNode, paths = new Set<string>()): Set<string> {
  if (node.type === "file" && node.path) paths.add(node.path);
  for (const child of node.children ?? []) flattenTree(child, paths);
  return paths;
}

// Updated:
interface FileInfo { size?: number }
function flattenTree(
  node: TreeNode,
  files = new Map<string, FileInfo>(),
): Map<string, FileInfo> {
  if (node.type === "file" && node.path) {
    files.set(node.path, { size: node.size });
  }
  for (const child of node.children ?? []) flattenTree(child, files);
  return files;
}
```

#### 3. Update foundation card completion logic

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

Add a minimum content size constant and update the `done` derivation:

```typescript
/**
 * Minimum file size (bytes) to consider a foundation document "complete".
 * Aligned with buildVisionEnhancementPrompt threshold in vision-helpers.ts.
 * A typical stub (title + placeholder) is ~100-300 bytes.
 * Real authored content (Mission, Target Audience, etc.) exceeds 500 bytes.
 */
const FOUNDATION_MIN_CONTENT_BYTES = 500;

// Updated completion check:
const foundationCards: FoundationCard[] = FOUNDATION_PATHS.map((f) => ({
  ...f,
  done:
    kbFiles.has(f.kbPath) &&
    (kbFiles.get(f.kbPath)?.size ?? 0) >= FOUNDATION_MIN_CONTENT_BYTES,
}));
```

Also update `visionExists` (used for first-run detection) to retain
file-existence behavior (Vision existing but being a stub should NOT show the
first-run input -- the user already submitted their idea):

```typescript
const visionExists = kbFiles.has("overview/vision.md");
```

#### 4. Update state variable naming

Rename `kbPaths`/`setKbPaths` to `kbFiles`/`setKbFiles` to reflect the richer
type (`Map<string, FileInfo>` instead of `Set<string>`).

#### 5. Update tests

**File:** `apps/web-platform/test/command-center.test.tsx`

Update the mock KB tree to include `size` fields. Add a test case where
`vision.md` exists but is below the threshold (should NOT show green
checkmark).

**File:** `apps/web-platform/test/start-fresh-onboarding.test.tsx`

Update mock tree builders to include `size` fields. Verify that stub vision
files do not trigger the "all foundations complete" state.

## Acceptance Criteria

- [ ] KB tree API response includes `size` (number, bytes) for each file node
- [ ] Foundation cards show green checkmark only when file exists AND size >= 500 bytes
- [ ] Stub vision.md (< 500 bytes) shows as incomplete (clickable card with prompt)
- [ ] Substantial vision.md (>= 500 bytes) shows as complete (green checkmark, link to KB)
- [ ] First-run state (no vision.md at all) still shows the "What are you building?" input
- [ ] Vision exists but is stub: shows foundation cards with Vision as incomplete
- [ ] All four foundation cards use the same size-based completion check
- [ ] Existing tests pass with updated mocks
- [ ] New test: stub vision.md (size < 500) does not show green checkmark

## Test Scenarios

- Given a KB tree with `overview/vision.md` at 200 bytes, when the dashboard loads, then the Vision card shows as incomplete (no green checkmark)
- Given a KB tree with `overview/vision.md` at 800 bytes, when the dashboard loads, then the Vision card shows as complete (green checkmark)
- Given a KB tree with no `overview/vision.md`, when the dashboard loads with no conversations, then the first-run "What are you building?" input is shown
- Given a KB tree with `overview/vision.md` at 100 bytes and no other foundation files, when the dashboard loads, then foundation cards are shown with Vision marked incomplete
- Given all four foundation files exist at >= 500 bytes each, when the dashboard loads with no conversations, then "Your organization is ready." is shown with suggested prompts
- Given all four foundation files exist but Vision is only 300 bytes, when the dashboard loads, then foundations section is shown (not "Your organization is ready.")

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- bug fix to internal completion detection logic.

## Context

### Related code

- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` -- Dashboard page with foundation cards (lines 28-33, 153-158)
- `apps/web-platform/server/kb-reader.ts` -- `buildTree` function that generates the tree (lines 144-204)
- `apps/web-platform/server/vision-helpers.ts` -- `buildVisionEnhancementPrompt` with 500-byte threshold (lines 55-77)
- `apps/web-platform/test/command-center.test.tsx` -- Dashboard test with KB tree mock
- `apps/web-platform/test/start-fresh-onboarding.test.tsx` -- Onboarding tests with foundation card assertions

### Existing threshold precedent

`vision-helpers.ts:buildVisionEnhancementPrompt` uses `stat.size >= 500` as
the threshold for "substantial" content. The dashboard should align with this.

## References

- `buildVisionEnhancementPrompt` in `server/vision-helpers.ts:55-77`
- `TreeNode` interface in `server/kb-reader.ts:12-19`
- Foundation card definitions in `dashboard/page.tsx:28-33`
