# Tasks: fix(kb-chat) — agents stuck, no interim messages, PDF context not used

## Phase 1: Fix multi-leader timeout interference (Bug 1)

### 1.1 Server-side: Defer `session_ended` for multi-leader dispatch

- [x] 1.1.1 Add optional `onLeaderDone` callback parameter to `startAgentSession` in `agent-runner.ts`
- [x] 1.1.2 When `onLeaderDone` is provided, call it instead of sending `session_ended` directly after `stream_end`
- [x] 1.1.3 When `onLeaderDone` is NOT provided (single-leader flow), send `session_ended` as before (backward compatible)
- [x] 1.1.4 In `dispatchToLeaders`, track active leader count with an atomic counter
- [x] 1.1.5 Pass each `startAgentSession` a callback that decrements the counter
- [x] 1.1.6 When counter reaches 0, send `session_ended` with `reason: "turn_complete"`

### 1.2 Client-side: Scope error handler stream cleanup

- [x] 1.2.1 In `ws-client.ts` error handler, do NOT call `activeStreamsRef.current.clear()` unconditionally
- [x] 1.2.2 If error has a `gateId`, route to review gate (existing behavior)
- [x] 1.2.3 For non-gate errors, only add an error message — do not clear active streams or timeouts for other leaders
- [x] 1.2.4 Conversation-level errors (key_invalid, rate_limited) continue clearing all state

### 1.3 Tests for Phase 1

- [x] 1.3.1 Unit test: `session_ended` does NOT clear other leaders' active streams when multiple leaders are active
- [x] 1.3.2 Unit test: Error event does not clear non-errored leaders' timeout timers
- [x] 1.3.3 Unit test: Last leader finishing sends `session_ended` and clears all state
- [x] 1.3.4 Unit test: Single-leader flow unchanged (session_ended sent immediately)

## Phase 2: Add substantive interim messages (Bug 2)

### 2.1 Build tool label helper

- [x] 2.1.1 Create `buildToolLabel(toolName, toolInput, workspacePath)` function in `agent-runner.ts`
- [x] 2.1.2 For Read: extract `file_path`, strip workspace prefix, show last 2 path segments
- [x] 2.1.3 For Bash: extract `command`, show first 60 chars, replace newlines with spaces
- [x] 2.1.4 For Grep: extract `pattern`, show in quotes
- [x] 2.1.5 For Glob: extract `pattern`, show pattern string
- [x] 2.1.6 For unknown tools: fall back to existing TOOL_LABELS map or "Working..."
- [x] 2.1.7 Verify no absolute workspace paths leak through labels (strip workspacePath prefix)

### 2.2 Wire buildToolLabel into stream handler

- [x] 2.2.1 Modify tool_use block handler to extract `input` from the tool_use content block
- [x] 2.2.2 Call `buildToolLabel(toolName, toolInput, workspacePath)` instead of `TOOL_LABELS[toolName]`
- [x] 2.2.3 Pass `workspacePath` through closure (already available in `startAgentSession` scope)

### 2.3 Tests for Phase 2

- [x] 2.3.1 Unit test: `buildToolLabel("Read", { file_path: "/workspaces/abc/kb/vision.md" }, "/workspaces/abc")` → "Reading kb/vision.md..."
- [x] 2.3.2 Unit test: `buildToolLabel("Bash", { command: "git log --oneline" })` → "Running: git log --oneline"
- [x] 2.3.3 Unit test: `buildToolLabel("Bash", { command: "a".repeat(100) })` → truncated with "..."
- [x] 2.3.4 Unit test: `buildToolLabel("Read", undefined)` → "Reading file..." (fallback)
- [x] 2.3.5 Unit test: Labels never contain workspace path prefix

## Phase 3: Server-side document content injection (Bug 3)

### 3.1 Read file content in startAgentSession

- [x] 3.1.1 When `context.path` is set and `context.content` is absent, resolve the full path via `path.join(workspacePath, context.path)`
- [x] 3.1.2 Validate path is within workspace using existing `isPathInWorkspace`
- [x] 3.1.3 For `.pdf` files: inject assertive Read instruction with document name, prohibit "which document?" questions
- [x] 3.1.4 For text files under 100KB: read content via `fs.readFile`, inject into system prompt as artifact content
- [x] 3.1.5 For text files over 100KB: inject assertive Read instruction with file size info
- [x] 3.1.6 On any read error: fall back to assertive Read instruction (not the passive one from PR #2422)
- [x] 3.1.7 All branches must include "Do not ask which document the user is referring to" language

### 3.2 Tests for Phase 3

- [x] 3.2.1 Unit test: Text file under 100KB → system prompt contains file content
- [x] 3.2.2 Unit test: Text file over 100KB → system prompt contains assertive Read instruction with size
- [x] 3.2.3 Unit test: PDF file → system prompt contains PDF-specific instruction with filename
- [x] 3.2.4 Unit test: All context injection branches include "do not ask which document" language
- [x] 3.2.5 Unit test: System prompt never contains absolute workspace paths
- [x] 3.2.6 Unit test: Path traversal attempt (context.path with "..") → rejected by isPathInWorkspace
