---
title: "fix: Vision foundation card shows green checkmark for stub files"
type: fix
date: 2026-04-13
---

## Enhancement Summary

**Deepened on:** 2026-04-13
**Sections enhanced:** 5 (Implementation, Architecture, Tests, Edge Cases, Learnings)
**Research sources:** Local codebase analysis, 6 institutional learnings, kb-reader concurrency patterns

### Key Improvements

1. Precise `buildTree` refactoring that preserves bounded concurrency (`mapWithConcurrency` pattern from learning 2026-04-12)
2. Complete `buildMockTree` helper update with size parameter and default value strategy
3. Edge case analysis: threshold boundary, YAML frontmatter overhead, binary files, concurrent writes
4. Identified 4 existing tests that need mock updates (with exact line changes)

### New Considerations Discovered

- The `buildTree` stat call pattern uses `.then().catch()` chaining, not `await` -- refactoring must preserve this to avoid changing error handling semantics
- The `buildMockTree` helper in `start-fresh-onboarding.test.tsx` is shared across 12+ tests -- default size must be >= 500 to avoid breaking existing passing tests
- `visionExists` (first-run gate) must remain file-existence-only to preserve the UX of "user already submitted idea but agent hasn't enhanced yet"
- The 500-byte threshold aligns with `buildVisionEnhancementPrompt` but should be exported as a shared constant to prevent drift

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

- Add `size?: number` to the `TreeNode` interface (line 12-19)
- In the `mapWithConcurrency` callback (lines 181-194), refactor the stat
  call to capture the full stat result instead of chaining `.then()`

### Research Insights

**Concurrency preservation (learning: 2026-04-12-buildtree-bounded-concurrency-emfile):**
The current `mapWithConcurrency` pattern bounds stat calls to 50 concurrent.
The refactoring must stay inside this callback -- do NOT move the stat call
outside or add additional parallel operations.

**Current stat pattern (lines 183-186):** Uses `.then().catch()` chaining:

```typescript
const modifiedAt = await fs.promises
  .stat(fullPath)
  .then((stat) => stat.mtime.toISOString())
  .catch(() => undefined);
```

**Refactored pattern:** Capture full stat result, extract both fields:

```typescript
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

**Why `.catch(() => null)` instead of try/catch:** Preserves the existing
functional chaining style and keeps the same error semantics -- a failed stat
produces `undefined` for both `modifiedAt` and `size` instead of throwing.

**TreeNode interface change:**

```typescript
// Add after line 17 (modifiedAt):
size?: number;
```

#### 2. Add size to `flattenTree` output on the dashboard

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`

Change `kbPaths` from `Set<string>` to `Map<string, { size?: number }>` so
the dashboard knows both existence and size. Update `flattenTree` to populate
the map.

### Research Insights

**`Map.has()` is a drop-in for `Set.has()`:** Both return boolean for key
existence. The only API difference is `Map.get()` for size retrieval. All
existing `kbPaths.has(...)` call sites work unchanged after renaming.

**TreeNode interface on the client side:** The dashboard already declares a
local `TreeNode` interface (lines 39-44) that mirrors the server type. Add
`size?: number` there too.

**State type change (lines 111, 137):** `useState<Set<string>>(new Set())`
becomes `useState<Map<string, FileInfo>>(new Map())`. The `new Map()`
default matches `new Set()` semantics (empty collection).

```typescript
// Current (line 39-44):
interface TreeNode {
  name: string;
  type: "file" | "directory";
  path?: string;
  children?: TreeNode[];
}

// Updated:
interface TreeNode {
  name: string;
  type: "file" | "directory";
  path?: string;
  size?: number;
  children?: TreeNode[];
}

// Current flattenTree (lines 46-50):
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

Add a minimum content size constant and update the `done` derivation.

### Research Insights

**Shared constant to prevent drift:** The 500-byte threshold already exists
in `server/vision-helpers.ts` (line 67: `if (stat.size >= 500) return null`).
To prevent future drift, extract to the shared constants file:

**File:** `apps/web-platform/lib/kb-constants.ts` (already exists with `KB_MAX_FILE_SIZE`)

```typescript
// Add to existing file:
/**
 * Minimum file size (bytes) to consider a foundation document "complete".
 * Used by:
 * - dashboard/page.tsx: Foundation card completion check
 * - vision-helpers.ts: buildVisionEnhancementPrompt threshold
 *
 * A typical stub (# Title + placeholder) is ~100-300 bytes.
 * Real authored content (multiple sections) exceeds 500 bytes.
 */
export const FOUNDATION_MIN_CONTENT_BYTES = 500;
```

**File:** `apps/web-platform/server/vision-helpers.ts` -- Update to use shared constant:

```typescript
import { FOUNDATION_MIN_CONTENT_BYTES } from "@/lib/kb-constants";
// ...
if (stat.size >= FOUNDATION_MIN_CONTENT_BYTES) return null;
```

**File:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx`:

```typescript
import { FOUNDATION_MIN_CONTENT_BYTES } from "@/lib/kb-constants";

// Updated completion check (replaces lines 154-157):
const foundationCards: FoundationCard[] = FOUNDATION_PATHS.map((f) => ({
  ...f,
  done:
    kbFiles.has(f.kbPath) &&
    (kbFiles.get(f.kbPath)?.size ?? 0) >= FOUNDATION_MIN_CONTENT_BYTES,
}));
```

**`visionExists` must remain file-existence-only (learning: start-fresh-shows-import-screen):**
The first-run gate (`!visionExists && conversations.length === 0`) controls
whether to show the "What are you building?" input. A stub vision means the
user already submitted their idea -- the agent just hasn't enhanced it yet.
Showing the input again would be confusing.

```typescript
// Unchanged -- file existence only, NOT size-gated:
const visionExists = kbFiles.has("overview/vision.md");
```

#### 4. Update state variable naming

Rename `kbPaths`/`setKbPaths` to `kbFiles`/`setKbFiles` to reflect the richer
type (`Map<string, FileInfo>` instead of `Set<string>`).

#### 5. Update tests

### Research Insights

**Mock stability (learning: 2026-04-07-userouter-mock-instability):** The
existing tests already use stable mock references. Do not change the
`useRouter` mock pattern.

**`buildMockTree` helper strategy:** The `buildMockTree` helper in
`start-fresh-onboarding.test.tsx` (lines 58-96) builds tree nodes from flat
path strings. It needs a way to specify per-file size. Two options:

- **Option A (recommended):** Default size to 1000 (above threshold) so all
  existing tests pass without changes. Add optional `sizes` map parameter for
  tests that need specific sizes.
- **Option B:** Change each `filePaths` call to include size. Requires
  updating 12+ test call sites.

Option A is safer -- existing tests implicitly expect files to be "complete".

```typescript
// Updated buildMockTree signature:
function buildMockTree(
  filePaths: string[],
  sizes?: Record<string, number>,
) {
  // ... existing logic ...
  if (isFile) {
    children.push({
      name: part,
      type: "file",
      path: p,
      modifiedAt: new Date().toISOString(),
      size: sizes?.[p] ?? 1000, // Default above threshold
    });
  }
  // ...
}
```

**File:** `apps/web-platform/test/command-center.test.tsx`

The inline KB tree mock (lines 139-155) uses direct object literals, not
`buildMockTree`. Add `size: 1000` to each file node to preserve existing
behavior:

```typescript
// Add size to each file node in the mock:
{ name: "vision.md", type: "file", path: "overview/vision.md", size: 1000 },
{ name: "brand-guide.md", type: "file", path: "marketing/brand-guide.md", size: 1000 },
// etc.
```

Add new test case for stub detection:

```typescript
it("shows foundation cards with Vision incomplete when vision.md is a stub", async () => {
  conversationBuilder = createQueryBuilder([]);
  messageBuilder = createQueryBuilder([]);

  globalThis.fetch = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: () =>
      Promise.resolve({
        tree: {
          name: "knowledge-base",
          type: "directory",
          children: [
            {
              name: "overview",
              type: "directory",
              children: [
                { name: "vision.md", type: "file", path: "overview/vision.md", size: 200 },
              ],
            },
          ],
        },
      }),
  });

  const { default: DashboardPage } = await import(
    "@/app/(dashboard)/dashboard/page"
  );
  render(<DashboardPage />);

  await waitFor(() => {
    // Vision exists (no first-run), but stub -- should show foundations
    expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
  });

  // Vision should NOT have the green checkmark (Complete label)
  expect(screen.queryByLabelText("Complete")).not.toBeInTheDocument();
});
```

**File:** `apps/web-platform/test/start-fresh-onboarding.test.tsx`

Update `buildMockTree` as described above. Add new test:

```typescript
it("stub vision.md does not count as foundation complete", async () => {
  fetchMock.mockResolvedValueOnce({
    ok: true,
    status: 200,
    json: () =>
      Promise.resolve({
        tree: buildMockTree(
          ["overview/vision.md"],
          { "overview/vision.md": 200 },
        ),
      }),
  });

  const { default: DashboardPage } = await import(
    "@/app/(dashboard)/dashboard/page"
  );
  render(<DashboardPage />);

  await waitFor(() => {
    // Vision exists but is stub -- should show foundation cards
    expect(screen.getByText(/no conversations yet/i)).toBeInTheDocument();
  });

  // No green checkmarks -- all 4 foundations are incomplete
  expect(screen.queryByLabelText("Complete")).not.toBeInTheDocument();
});
```

### Edge Cases

1. **Threshold boundary (exactly 500 bytes):** A file of exactly 500 bytes
   should show as complete (`>=` not `>`). This matches `vision-helpers.ts`
   which uses `stat.size >= 500`.

2. **YAML frontmatter inflation:** A file with `---\ntitle: Vision\n---\n`
   frontmatter (30 bytes) plus minimal content could appear larger than the
   raw content warrants. However, since we measure raw file size (not parsed
   content size), this is acceptable -- frontmatter-only files are still well
   under 500 bytes. A file that has enough frontmatter to reach 500 bytes
   also has enough structure to be considered "started."

3. **Binary/non-markdown files:** Foundation paths are all `.md` files.
   Binary files (images, PDFs) in the KB tree get `size` too, but
   foundation card logic only checks the specific `.md` paths, so binary
   files are irrelevant.

4. **Concurrent agent writes:** If the CPO agent is actively writing
   `vision.md` and the user reloads the dashboard mid-write, the file
   might be under 500 bytes. This is correct behavior -- the card will
   update to "complete" on the next dashboard load after the agent finishes.

5. **stat failure (file deleted between readdir and stat):** The existing
   `.catch(() => null)` pattern handles this gracefully -- `size` will be
   `undefined`, which the `?? 0` fallback handles correctly (shows as
   incomplete).

6. **KB tree cache:** The `/api/kb/tree` endpoint has no server-side cache.
   Each dashboard load fetches fresh tree data, so size changes are
   reflected immediately.

### Applicable Institutional Learnings

- **2026-04-12-buildtree-bounded-concurrency-emfile:** The `mapWithConcurrency`
  pattern must be preserved. Do not refactor stat calls outside the callback.
- **2026-04-10-dashboard-onboarding-state-independent-of-conversation-loading:**
  The onboarding state (first-run/foundations/command center) is determined by
  KB tree state, not conversation loading. This fix aligns with that principle.
- **2026-04-07-userouter-mock-instability:** Test mocks use stable references.
  Do not change mock patterns when updating tests.
- **start-fresh-shows-import-screen-and-vision-sync-content-20260410:**
  `tryCreateVision` content validation is already in place. The size-based
  completion check is a separate concern from content validation.
- **2026-04-07-promise-all-parallel-fs-io-patterns:** The stat call runs inside
  the bounded `mapWithConcurrency` worker pool, not inside unbounded
  `Promise.all`. No concurrency risk from the refactoring.

## Acceptance Criteria

- [x] KB tree API response includes `size` (number, bytes) for each file node
- [x] Foundation cards show green checkmark only when file exists AND size >= 500 bytes
- [x] Stub vision.md (< 500 bytes) shows as incomplete (clickable card with prompt)
- [x] Substantial vision.md (>= 500 bytes) shows as complete (green checkmark, link to KB)
- [x] First-run state (no vision.md at all) still shows the "What are you building?" input
- [x] Vision exists but is stub: shows foundation cards with Vision as incomplete
- [x] All four foundation cards use the same size-based completion check
- [x] Existing tests pass with updated mocks
- [x] New test: stub vision.md (size < 500) does not show green checkmark

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
