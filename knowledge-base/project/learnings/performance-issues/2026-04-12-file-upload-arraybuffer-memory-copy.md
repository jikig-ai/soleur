# Learning: File upload triple memory copy on large files

## Problem

The KB upload route (`app/api/kb/upload/route.ts`) used `Buffer.from(await file.arrayBuffer()).toString("base64")` to encode uploaded files for the GitHub Contents API. For a 20 MB file, this allocates a separate ArrayBuffer alongside the File blob before converting to base64, inflating peak per-request memory.

## Solution

Replace `file.arrayBuffer()` with `file.stream()` to collect `Uint8Array` chunks directly, then `Buffer.concat(chunks).toString("base64")`. This bypasses the intermediate ArrayBuffer allocation -- the File blob's internal bytes stream as chunks into a single Buffer.

```typescript
// Before (allocates File blob + ArrayBuffer + base64 string)
const base64Content = Buffer.from(await file.arrayBuffer()).toString("base64");

// After (allocates File blob + Buffer via chunks + base64 string)
const chunks: Uint8Array[] = [];
for await (const chunk of file.stream()) {
  chunks.push(chunk);
}
const base64Content = Buffer.concat(chunks).toString("base64");
```

## Key Insight

`Buffer.from(ArrayBuffer)` creates a zero-copy view in Node.js, so the real overhead is the ArrayBuffer itself coexisting with the File blob. Streaming eliminates that intermediate allocation. For APIs requiring the full payload (like GitHub Contents API), true streaming to the network is not possible, but eliminating intermediate copies still reduces peak memory.

## Session Errors

- **Stale local main in bare repo** -- worktree was created from local `main` which was behind `origin/main`, so the target file did not exist. Recovery: merged `origin/main` into the branch. Prevention: the worktree-manager script should base new branches on `origin/main` when local main cannot be fast-forwarded (it already tries but falls back silently).
- **Wrong test runner (`bun test` vs `vitest`)** -- the fix-issue skill template uses `bun test` but this project uses vitest. Recovery: checked `package.json` scripts and used `npx vitest run`. Prevention: fix-issue skill should detect the test runner from package.json scripts instead of hardcoding `bun test`.
- **.mcp.json refresh permission denied** -- Bash tool denied file write to bare repo root. Recovery: non-blocking, continued without it. Prevention: run this step before invoking subagents, or accept it as a known limitation of the sandbox.

## Tags

category: performance-issues
module: web-platform/api/kb/upload
