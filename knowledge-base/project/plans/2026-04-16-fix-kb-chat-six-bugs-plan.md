---
title: "fix: KB Chat — 6 bugs (document context, path exposure, timeout, input alignment, cost display)"
type: fix
date: 2026-04-16
issue: TBD
pr: 2422
---

# fix: KB Chat — 6 bugs

## Overview

The KB Chat sidebar has 6 bugs observed in production. Root causes span the backend system prompt construction, the frontend streaming state machine, and CSS alignment. Fixes are organized by layer (backend first, then frontend) so each can be tested independently.

## Root Cause Analysis

| # | Bug | Root Cause | File(s) | Lines |
|---|-----|-----------|---------|-------|
| 1 | CMO "Agent stopped responding" | 30s timeout fires before agent produces first token. Claude API cold-start + routing classification via Haiku can exceed 30s. | `lib/chat-state-machine.ts` | 207-226 |
| 2 | Agents search codebase instead of document | `KbChatSidebar` creates `initialContext = { path, type }` without `content`. `ChatSurface` skips content fetch because `initialContext` is truthy. Agent system prompt gets no artifact content, falls back to tool-based searching. | `kb-chat-sidebar.tsx:71-74`, `chat-surface.tsx:109-110`, `agent-runner.ts:486` |  |
| 3 | Text input taller than buttons | Textarea `min-h-[44px]` + `py-3` (24px padding) + text line-height computes to >44px visual height while buttons are fixed at 44x44. | `chat-input.tsx:499` |  |
| 4 | CPO stuck on "Reading file..." | Each `tool_use` event resets the 30s timeout. Agent doing sequential Read/Grep calls never times out — stays in tool_use state indefinitely. | `chat-state-machine.ts:100,119,137,155` |  |
| 5 | Internal paths exposed | System prompt includes `workspacePath` verbatim: `"The user's workspace is at ${workspacePath}."` Agents reference this path in responses. | `agent-runner.ts:481` |  |
| 6 | Missing cost estimate | Cost display is gated by `isFull` (true only for full-route variant). Sidebar variant never shows cost. | `chat-surface.tsx:425,479` |  |

## Implementation Phases

### Phase 1: Backend — System prompt fixes (Bugs #2 and #5)

Both bugs are in `agent-runner.ts`, same system prompt construction block.

#### Bug #5: Remove workspace path from system prompt

**Problem:** `workspacePath` is injected verbatim into the system prompt. Agents reference it in responses, exposing internal server paths.

**Fix:** Remove the workspace path. The agent already runs with `cwd: workspacePath` (line 797), `filesystem.allowWrite: [workspacePath]` (line 836), and the sandbox hook enforces path containment. The agent does not need the absolute path in its prompt.

**File:** `apps/web-platform/server/agent-runner.ts:479-483`

```typescript
// Current:
Use the tools available to you to read and write to the knowledge-base directory. The user's workspace is at ${workspacePath}.

// Fixed:
Use the tools available to you to read and write to the knowledge-base directory. Files are relative to the current working directory.

Never mention file system paths, workspace paths, or internal directory structures in your responses — refer to files by their knowledge-base-relative path (e.g. "overview/vision.md" not "/workspaces/.../knowledge-base/overview/vision.md").
```

#### Bug #2: Add context.path fallback for sidebar

**Problem:** Sidebar creates `initialContext = { path, type }` without `content`. ChatSurface skips content fetch. Agent system prompt gets no artifact content, falls back to tool-based searching.

**Fix:** Add an `else if` branch when `context.path` is present but `context.content` is absent.

**File:** `apps/web-platform/server/agent-runner.ts:485-488`

```typescript
// Current:
if (context?.content) {
  systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nArtifact content:\n${context.content}\n\nAnswer in the context of this artifact.`;
}

// Fixed:
if (context?.content) {
  systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nArtifact content:\n${context.content}\n\nAnswer in the context of this artifact.`;
} else if (context?.path) {
  systemPrompt += `\n\nThe user is currently viewing the file at: ${context.path}\n\nRead this file first using the Read tool, then answer questions in the context of this document. Focus on the document content — do not search the knowledge-base directory for other files unless the user specifically asks.`;
}
```

Handles both markdown (Read returns text) and PDFs (Read tool supports PDF reading) without a client-side content fetch.

### Phase 2: Frontend — Timeout logic (Bugs #1 and #4)

**Problem #4:** Every `tool_use` event resets the 30s timeout. Agent doing sequential tool calls never times out.

**Problem #1:** 30s initial timeout is too aggressive for Claude API cold-start + Haiku routing.

**Fix:** One timer, 45s, that resets on `stream` events but NOT on `tool_use` events. No new timer types, no dual-handle management.

**File:** `apps/web-platform/lib/chat-state-machine.ts`

Change the `tool_use` case to emit `timerAction: null` (no-op) instead of `timerAction: { type: "reset" }`. Only `stream` and `stream_start` events reset the timer. Increase the timeout constant from 30s to 45s.

```typescript
// Lines 100, 119, 137, 155 — tool_use cases:
// Current:
timerAction: { type: "reset", leaderId: event.leaderId },

// Fixed:
timerAction: null,
```

```typescript
// Timeout constant:
// Current:
const TIMEOUT_MS = 30_000;

// Fixed:
const TIMEOUT_MS = 45_000;
```

This directly solves both bugs:

- Bug #1: 45s instead of 30s accommodates cold starts
- Bug #4: tool_use events no longer reset the timer, so an agent churning through Read/Grep calls times out after 45s of no streaming output

### Phase 3: Frontend — Input alignment and cost display (Bugs #3 and #6)

#### Bug #3: Chat input height alignment

**Problem:** Textarea computed height exceeds 44px button height.

**Fix:** Use explicit `h-[44px]` and reduce vertical padding. Verify the exact values in the browser — the math needs empirical confirmation since browser textarea rendering varies.

**File:** `apps/web-platform/components/chat/chat-input.tsx:499`

```typescript
// Current:
"... py-3 ... min-h-[44px] ..."

// Fixed:
"... py-2.5 ... h-[44px] ..."
```

Change `py-3` to `py-2.5` and `min-h-[44px]` to `h-[44px]`. Verify in browser that textarea, paperclip, and send button align at the same height.

**Note:** An existing plan exists at `knowledge-base/project/plans/2026-04-12-fix-chat-input-alignment-plan.md`. Verify whether that fix was already applied before implementing.

#### Bug #6: Cost estimate in sidebar

**Problem:** Cost display gated by `isFull` — sidebar never shows it.

**Fix:** Move cost display outside the `isFull` gate with variant-appropriate styling.

**File:** `apps/web-platform/components/chat/chat-surface.tsx`

Replace the `isFull &&` gated cost blocks with a unified cost display visible in both variants:

```tsx
{usageData && usageData.totalCostUsd > 0 && (
  <div className={`mt-1 text-xs text-neutral-500 ${isFull ? "mx-auto max-w-3xl" : "px-1"}`}>
    ~${usageData.totalCostUsd.toFixed(4)} estimated
  </div>
)}
```

Place after the ChatInput component, inside the input container div.

## Files to Modify

| File | Changes |
|------|---------|
| `apps/web-platform/server/agent-runner.ts` | Remove workspace path from system prompt, add context.path fallback (Phase 1) |
| `apps/web-platform/lib/chat-state-machine.ts` | Stop resetting timer on tool_use, increase timeout to 45s (Phase 2) |
| `apps/web-platform/components/chat/chat-input.tsx` | Fix textarea height to match buttons (Phase 3) |
| `apps/web-platform/components/chat/chat-surface.tsx` | Show cost estimate in sidebar variant (Phase 3) |

## Acceptance Criteria

- [x] **AC1 (Bug #2):** When asking about a document in the KB sidebar, agents read the specific document file rather than searching the knowledge-base directory
- [x] **AC2 (Bug #5):** Agent responses never contain absolute workspace paths like `/workspaces/52af49c2-...`
- [x] **AC3 (Bug #1):** CMO agent does not show "Agent stopped responding" within 45s of starting
- [x] **AC4 (Bug #4):** An agent doing sequential tool_use calls for >45s without streaming output transitions to error state
- [x] **AC5 (Bug #3):** The chat input textarea, paperclip button, and send button all render at the same height with vertical center alignment
- [x] **AC6 (Bug #6):** The sidebar variant displays the cost estimate (`~$X.XXXX estimated`) below the input area

## Test Scenarios

### Unit tests

1. **agent-runner system prompt (Phase 1):**
   - When context has both `path` and `content`, system prompt includes artifact content (existing behavior)
   - When context has `path` but no `content`, system prompt includes "Read this file first" instruction
   - System prompt never contains absolute workspace paths (no `/workspaces/` substring)
   - System prompt includes "Never mention file system paths" instruction

2. **chat-state-machine timeout (Phase 2):**
   - `applyTimeout` transitions thinking/tool_use bubbles to error (existing)
   - `tool_use` event does NOT reset the timer (timerAction is null)
   - `stream` event resets the timer
   - Timeout constant is 45000ms

3. **chat-input height (Phase 3):**
   - Textarea element has `h-[44px]` class (snapshot or class assertion)

4. **chat-surface cost display (Phase 3):**
   - Cost element renders when `variant="sidebar"` and `usageData.totalCostUsd > 0`
   - Cost element renders when `variant="full"` and `usageData.totalCostUsd > 0`

### Manual QA

1. Upload a PDF to KB, open sidebar chat, ask a question about the document content — agent should read the PDF, not search the directory
2. Check agent responses for any mention of `/workspaces/` paths
3. Open sidebar chat, wait for agent response — verify no premature "Agent stopped responding"
4. Check input alignment visually — all three elements same height

## Domain Review

**Domains relevant:** none

No cross-domain implications — bug fixes on existing feature, no new surfaces or capabilities.
