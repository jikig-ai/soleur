---
title: "fix(kb-chat): agents stuck working, no interim messages, PDF context not used"
type: fix
date: 2026-04-16
issue: TBD
---

# fix(kb-chat): 3 bugs — agents stuck, no interim messages, PDF context not used

## Overview

Three bugs in the KB chat sidebar remain after PR #2422 (which fixed 6 other bugs). These span the multi-leader lifecycle management, the tool_use status display, and the document context injection pipeline. Each has a distinct root cause but all manifest in the same user flow: opening a PDF in KB, asking a question, and watching auto-routed agents (CPO/COO/CMO) fail to respond meaningfully.

## Research Reconciliation — Spec vs. Codebase

PR #2422 addressed the 30s→45s timeout increase and stopped `tool_use` from resetting the timer. The current bugs are different from those fixed:

| PR #2422 Claim | Codebase Reality | Plan Response |
|---|---|---|
| Timeout increased to 45s and tool_use no longer resets timer | Confirmed applied in `chat-state-machine.ts` | New bug: multi-leader `session_ended` clears ALL timeouts, not just the finishing leader's |
| `context.path` fallback added for sidebar | Confirmed applied in `agent-runner.ts:490-491` | New bug: for PDFs, "Read this file first" instruction is unreliable — agents ignore it or ask clarifying questions instead |
| Cost display shown in sidebar | Confirmed applied in `chat-surface.tsx:479` | Not re-broken |

## Root Cause Analysis

### Bug 1: Agents never stop working (multi-leader timeout interference)

**Root cause:** When the server sends `session_ended` (reason: `turn_complete`) after any leader finishes, the client handler (ws-client.ts:296-310) calls `activeStreamsRef.current.clear()` and `clearAllTimeouts()`. This kills timeout protection for ALL other leaders still running.

**Reproduction flow:**
1. User asks a question in KB sidebar
2. Router dispatches to CPO, COO, CMO (3 leaders)
3. CPO finishes first → server sends `stream_end` for CPO, then `session_ended`
4. Client processes `session_ended` → clears ALL active streams and ALL timeouts
5. COO and CMO are still running but now have no timeout protection
6. If COO or CMO hangs (slow API, complex tool chain), they stay in "Working" state forever

**Secondary issue:** The `error` event handler (ws-client.ts:253) also clears ALL active streams and ALL timeouts. One leader's error removes all other leaders' timeout protection.

**File:** `apps/web-platform/lib/ws-client.ts` (lines 296-310, 252-254), `apps/web-platform/lib/chat-state-machine.ts`

### Bug 2: No interim messages (generic tool labels)

**Root cause:** The `TOOL_LABELS` map in agent-runner.ts maps tool names to generic strings:
- `Read` → "Reading file..."
- `Bash` → "Running command..."
- `Grep` → "Searching code..."

These give zero insight into what the agent is actually doing. Users see "Working..." or "Reading file..." for minutes with no understanding of progress.

**File:** `apps/web-platform/server/agent-runner.ts` (lines 64-72, 1117-1128)

### Bug 3: PDF context not used (instruction-based fallback unreliable)

**Root cause:** When the sidebar opens on a PDF, `initialContext = { path, type: "kb-viewer" }` is passed without `content`. The server's system prompt tells the agent "Read this file first using the Read tool" (PR #2422 fix). However:

1. Domain leader agents (CPO, COO, CMO) receive this as a suggestion, not a hard constraint. They frequently ask clarifying questions ("which PDF?") or start searching the KB directory instead.
2. Each of the 3 auto-routed leaders makes independent Read calls to the same PDF, tripling API cost.
3. For PDF files with special characters (e.g., "Au Chat Pôtan - Pitch Projet.pdf"), the Read tool path may fail.

The server has direct filesystem access to the user's workspace. It can read the document content at session start and inject it into the system prompt, eliminating the need for agents to read it themselves.

**Files:** `apps/web-platform/server/agent-runner.ts` (lines 487-492), `apps/web-platform/components/chat/kb-chat-sidebar.tsx` (lines 71-74)

## Implementation Phases

### Phase 1: Fix multi-leader timeout interference (Bug 1)

**Problem:** `session_ended` and `error` handlers clear ALL active streams and ALL timeouts.

**Fix:** Make `session_ended` per-leader aware. The `session_ended` message currently has no `leaderId` field — it is a conversation-level signal. For multi-leader conversations, it should NOT clear other leaders' state.

**Approach A (server-side, preferred):** Don't send `session_ended` from individual leader sessions when other leaders are still running. Only send it when ALL leaders have finished. This requires tracking active leader count in `dispatchToLeaders`.

**Approach B (client-side):** Make the `session_ended` handler idempotent per-leader. If `activeStreamsRef.current.size > 0` when `session_ended` fires, do NOT clear all streams — only decrement a counter.

**Recommended: Approach A (server-side).**

In `agent-runner.ts`, the `startAgentSession` function sends `stream_end` (per-leader) and then `session_ended` (conversation-level). For multi-leader dispatch, `session_ended` should only be sent after ALL leaders complete.

**Changes:**

1. **`agent-runner.ts` — `startAgentSession`:** Add an optional callback parameter `onLeaderDone` that `dispatchToLeaders` passes. When the result message is processed, call `onLeaderDone()` instead of sending `session_ended` directly. If no callback is provided (single-leader flow), send `session_ended` as before.

2. **`agent-runner.ts` — `dispatchToLeaders`:** Track active leader count. Pass each `startAgentSession` a callback that decrements the count. When count reaches 0, send `session_ended` to the client.

3. **`ws-client.ts` — `error` handler:** Don't clear ALL active streams on a non-gate error. Instead, only clear the specific leader's stream if the error contains a `leaderId`. For errors without `leaderId` (conversation-level errors), continue clearing all.

4. **`chat-state-machine.ts` — No changes needed.** The `stream_end` event already handles per-leader cleanup correctly (removes only that leader from activeStreams).

**Files to modify:**
- `apps/web-platform/server/agent-runner.ts` — `startAgentSession`, `dispatchToLeaders`
- `apps/web-platform/lib/ws-client.ts` — `error` and `session_ended` handlers

### Phase 2: Add substantive interim messages (Bug 2)

**Problem:** Tool labels are generic ("Reading file...", "Working...").

**Fix:** Include the tool's target in the label. The `tool_use` content block from the SDK contains structured input with the tool's arguments. Extract the most relevant argument (file path for Read, command preview for Bash, pattern for Grep).

**Changes:**

1. **`agent-runner.ts` — tool_use event handler (line 1117-1128):** Extract the tool input from the `tool_use` block and build a richer label.

```typescript
// Current:
const toolName = (block as { name?: string }).name ?? "unknown";
sendToClient(userId, {
  type: "tool_use",
  leaderId: streamLeaderId,
  label: TOOL_LABELS[toolName] ?? "Working...",
});

// Fixed: extract target from tool input for richer labels
const toolBlock = block as { name?: string; input?: Record<string, unknown> };
const toolName = toolBlock.name ?? "unknown";
const label = buildToolLabel(toolName, toolBlock.input);
sendToClient(userId, {
  type: "tool_use",
  leaderId: streamLeaderId,
  label,
});
```

2. **New helper `buildToolLabel`:** Builds human-readable labels from tool name and input:

```typescript
function buildToolLabel(toolName: string, input?: Record<string, unknown>): string {
  if (!input) return TOOL_LABELS[toolName] ?? "Working...";

  switch (toolName) {
    case "Read": {
      const file = input.file_path ?? input.path;
      if (typeof file === "string") {
        // Strip workspace prefix, show just the relative path
        const short = file.split("/").slice(-2).join("/");
        return `Reading ${short}...`;
      }
      return "Reading file...";
    }
    case "Bash": {
      const cmd = input.command;
      if (typeof cmd === "string") {
        // Show first 60 chars of command, sanitized
        const preview = cmd.slice(0, 60).replace(/\n/g, " ");
        return `Running: ${preview}${cmd.length > 60 ? "..." : ""}`;
      }
      return "Running command...";
    }
    case "Grep": {
      const pattern = input.pattern;
      if (typeof pattern === "string") {
        return `Searching for "${pattern.slice(0, 40)}"...`;
      }
      return "Searching code...";
    }
    case "Glob": {
      const pat = input.pattern;
      if (typeof pat === "string") {
        return `Finding ${pat.slice(0, 40)}...`;
      }
      return "Finding files...";
    }
    case "Edit":
      return "Editing file...";
    case "Write":
      return "Writing file...";
    default:
      return TOOL_LABELS[toolName] ?? "Working...";
  }
}
```

**Security note:** The tool input may contain absolute workspace paths. The `buildToolLabel` function must strip any workspace path prefix before sending to the client. The existing "never mention file system paths" rule in the system prompt only covers agent text output — tool labels are constructed server-side and need their own sanitization.

**Files to modify:**
- `apps/web-platform/server/agent-runner.ts` — new `buildToolLabel` function, modify tool_use event handler

### Phase 3: Server-side document content injection for PDFs (Bug 3)

**Problem:** Agents are told "Read this file first" but don't reliably follow the instruction for PDFs.

**Fix:** When `context.path` is present but `context.content` is absent, and the file exists on disk, read it server-side and inject the content into the system prompt. This eliminates the need for each agent to independently Read the file.

**Changes:**

1. **`agent-runner.ts` — `startAgentSession` context injection block (lines 487-492):** Add a server-side content read when `context.path` is set but `context.content` is not.

```typescript
// After the existing context injection block:
if (context?.content) {
  systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nArtifact content:\n${context.content}\n\nAnswer in the context of this artifact.`;
} else if (context?.path) {
  // Try to read the file content server-side
  const fullPath = path.join(workspacePath, context.path);
  if (isPathInWorkspace(fullPath, workspacePath)) {
    try {
      const stat = await fs.promises.stat(fullPath);
      // Cap at 100KB to avoid blowing up the system prompt
      if (stat.size <= 100_000) {
        const fileContent = await fs.promises.readFile(fullPath, "utf-8");
        systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nDocument content:\n${fileContent}\n\nAnswer questions in the context of this document. Do not ask which document the user is referring to — they are discussing the document shown above.`;
      } else {
        // File too large for system prompt — fall back to Read instruction
        systemPrompt += `\n\nThe user is currently viewing: ${context.path}\n\nThis is a large file (${Math.round(stat.size / 1024)}KB). Read it using the Read tool before answering. Focus on the document content — do not ask which file the user is referring to.`;
      }
    } catch {
      // File doesn't exist or can't be read (e.g., binary PDF)
      // For PDFs, try reading as text first, fall back to instruction
      systemPrompt += `\n\nThe user is currently viewing the file at: ${context.path}\n\nRead this file first using the Read tool, then answer questions in the context of this document. Do not ask which document the user is referring to — they are viewing it right now.`;
    }
  }
}
```

**PDF handling note:** The `fs.readFile` with "utf-8" encoding will produce garbled output for binary PDFs. For `.pdf` files, the approach should be different: the agent should still use the Read tool (which supports PDF natively in Claude's SDK), but the system prompt should be more assertive:

```typescript
const isPdf = context.path.toLowerCase().endsWith(".pdf");
if (isPdf) {
  systemPrompt += `\n\nThe user is currently viewing the PDF document: ${context.path}\n\nIMPORTANT: Use the Read tool to read this PDF file BEFORE responding. The user's question is about this specific document. Do NOT ask which document they mean — they are viewing "${context.path.split("/").pop()}" right now.`;
} else {
  // ... text file handling above
}
```

2. **Strengthen the instruction for all file types:** The previous instruction "Read this file first using the Read tool" is passive. Change to imperative with explicit prohibition on clarifying questions.

**Files to modify:**
- `apps/web-platform/server/agent-runner.ts` — context injection block in `startAgentSession`

## Files to Modify

| File | Changes |
|------|---------|
| `apps/web-platform/server/agent-runner.ts` | Phase 1: Add `onLeaderDone` callback to `startAgentSession`, refactor `dispatchToLeaders` to track active leaders. Phase 2: New `buildToolLabel` function, modify tool_use event handler. Phase 3: Server-side file content read for context injection. |
| `apps/web-platform/lib/ws-client.ts` | Phase 1: Make `session_ended` handler multi-leader aware, scope `error` handler stream cleanup. |
| `apps/web-platform/lib/chat-state-machine.ts` | No changes needed — `stream_end` already handles per-leader cleanup correctly. |

## Acceptance Criteria

- [ ] **AC1 (Bug 1):** When 3 leaders are auto-routed and the first leader finishes, the other leaders' timeout timers continue running and fire after 45s of no streaming output
- [ ] **AC2 (Bug 1):** When one leader errors, the other leaders' bubbles are not affected — they continue streaming or time out independently
- [ ] **AC3 (Bug 2):** Tool_use status shows the target file path for Read (e.g., "Reading overview/vision.md...") instead of generic "Reading file..."
- [ ] **AC4 (Bug 2):** Tool_use status shows a command preview for Bash (e.g., "Running: git log --oneline...") instead of generic "Running command..."
- [ ] **AC5 (Bug 2):** Tool_use labels never contain absolute workspace paths
- [ ] **AC6 (Bug 3):** When a PDF is open in KB and the user asks about it, agents read the PDF content before responding and do not ask "which PDF?"
- [ ] **AC7 (Bug 3):** For text files under 100KB, the document content is injected into the system prompt directly (no agent-side Read needed)
- [ ] **AC8 (Bug 3):** For PDFs and files over 100KB, the system prompt contains an assertive instruction to Read the file with explicit "do not ask which document" language

## Test Scenarios

### Unit Tests

1. **chat-state-machine / ws-client (Phase 1):**
   - Given multi-leader streams active (CPO, COO), when `session_ended` arrives, then COO's active stream and timeout are NOT cleared
   - Given leader CPO errored, when error event with no leaderId arrives, then COO's timeout continues running (streams cleared but timeout preserved — or: error event with leaderId only clears that leader)
   - Given 3 leaders dispatched and all finish, when last `stream_end` processed, then `session_ended` fires and clears all state

2. **buildToolLabel (Phase 2):**
   - `buildToolLabel("Read", { file_path: "/workspaces/abc/knowledge-base/overview/vision.md" })` returns `"Reading overview/vision.md..."` (stripped workspace prefix)
   - `buildToolLabel("Bash", { command: "git log --oneline -5" })` returns `"Running: git log --oneline -5"`
   - `buildToolLabel("Bash", { command: "a".repeat(100) })` returns truncated with `"..."`
   - `buildToolLabel("Grep", { pattern: "TODO" })` returns `"Searching for \"TODO\"..."`
   - `buildToolLabel("Read", undefined)` returns `"Reading file..."` (fallback)
   - `buildToolLabel("Agent", {})` returns `"Working..."` (unknown tool fallback)

3. **Context injection (Phase 3):**
   - Given context `{ path: "knowledge-base/doc.md", type: "kb-viewer" }` and file exists (50KB), system prompt contains the file content
   - Given context `{ path: "knowledge-base/doc.md", type: "kb-viewer" }` and file exists (200KB), system prompt contains "large file" instruction with Read directive
   - Given context `{ path: "knowledge-base/pitch.pdf", type: "kb-viewer" }`, system prompt contains PDF-specific Read instruction with "do not ask which document" language
   - Given context `{ path: "knowledge-base/doc.md", type: "kb-viewer" }` and file does not exist, system prompt contains fallback Read instruction
   - System prompt never contains absolute workspace paths in any context injection branch

### Integration Tests (manual QA)

1. Open "Au Chat Pôtan - Pitch Projet.pdf" in KB viewer, open sidebar, ask "Shall we bundle coworking and fablab in a single activity?" — all 3 auto-routed agents should read the PDF and answer about the document content
2. Open a markdown document, open sidebar, ask a question — verify the agent answers using the document content (injected in system prompt), not from a separate Read call
3. Send a message that routes to 3 leaders. Verify all 3 eventually reach "done" state, even if one finishes much earlier than the others
4. During agent work, verify tool status shows specific targets ("Reading overview/vision.md..." not "Reading file...")
5. Verify no absolute workspace paths appear in tool status labels

## Domain Review

**Domains relevant:** none

No cross-domain implications — bug fixes on existing infrastructure, no new surfaces or capabilities.
