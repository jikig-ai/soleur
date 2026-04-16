# Tasks: fix(kb-chat) — agents stuck, no interim messages, PDF context not used

## Phase 1: Fix multi-leader timeout interference (Bug 1)

### 1.1 Server-side: Defer `session_ended` for multi-leader dispatch

- [ ] 1.1.1 Add optional `onLeaderDone` callback parameter to `startAgentSession` in `agent-runner.ts`
- [ ] 1.1.2 When `onLeaderDone` is provided, call it instead of sending `session_ended` directly after `stream_end`
- [ ] 1.1.3 When `onLeaderDone` is NOT provided (single-leader flow), send `session_ended` as before (backward compatible)
- [ ] 1.1.4 In `dispatchToLeaders`, track active leader count with an atomic counter
- [ ] 1.1.5 Pass each `startAgentSession` a callback that decrements the counter
- [ ] 1.1.6 When counter reaches 0, send `session_ended` with `reason: "turn_complete"`

### 1.2 Client-side: Scope error handler stream cleanup

- [ ] 1.2.1 In `ws-client.ts` error handler, do NOT call `activeStreamsRef.current.clear()` unconditionally
- [ ] 1.2.2 If error has a `gateId`, route to review gate (existing behavior)
- [ ] 1.2.3 For non-gate errors, only add an error message — do not clear active streams or timeouts for other leaders
- [ ] 1.2.4 Conversation-level errors (key_invalid, rate_limited) continue clearing all state

### 1.3 Tests for Phase 1

- [ ] 1.3.1 Unit test: `session_ended` does NOT clear other leaders' active streams when multiple leaders are active
- [ ] 1.3.2 Unit test: Error event does not clear non-errored leaders' timeout timers
- [ ] 1.3.3 Unit test: Last leader finishing sends `session_ended` and clears all state
- [ ] 1.3.4 Unit test: Single-leader flow unchanged (session_ended sent immediately)

## Phase 2: Add substantive interim messages (Bug 2)

### 2.1 Build tool label helper

- [ ] 2.1.1 Create `buildToolLabel(toolName, toolInput, workspacePath)` function in `agent-runner.ts`
- [ ] 2.1.2 For Read: extract `file_path`, strip workspace prefix, show last 2 path segments
- [ ] 2.1.3 For Bash: extract `command`, show first 60 chars, replace newlines with spaces
- [ ] 2.1.4 For Grep: extract `pattern`, show in quotes
- [ ] 2.1.5 For Glob: extract `pattern`, show pattern string
- [ ] 2.1.6 For unknown tools: fall back to existing TOOL_LABELS map or "Working..."
- [ ] 2.1.7 Verify no absolute workspace paths leak through labels (strip workspacePath prefix)

### 2.2 Wire buildToolLabel into stream handler

- [ ] 2.2.1 Modify tool_use block handler to extract `input` from the tool_use content block
- [ ] 2.2.2 Call `buildToolLabel(toolName, toolInput, workspacePath)` instead of `TOOL_LABELS[toolName]`
- [ ] 2.2.3 Pass `workspacePath` through closure (already available in `startAgentSession` scope)

### 2.3 Tests for Phase 2

- [ ] 2.3.1 Unit test: `buildToolLabel("Read", { file_path: "/workspaces/abc/kb/vision.md" }, "/workspaces/abc")` → "Reading kb/vision.md..."
- [ ] 2.3.2 Unit test: `buildToolLabel("Bash", { command: "git log --oneline" })` → "Running: git log --oneline"
- [ ] 2.3.3 Unit test: `buildToolLabel("Bash", { command: "a".repeat(100) })` → truncated with "..."
- [ ] 2.3.4 Unit test: `buildToolLabel("Read", undefined)` → "Reading file..." (fallback)
- [ ] 2.3.5 Unit test: Labels never contain workspace path prefix

## Phase 3: Server-side document content injection (Bug 3)

### 3.1 Read file content in startAgentSession

- [ ] 3.1.1 When `context.path` is set and `context.content` is absent, resolve the full path via `path.join(workspacePath, context.path)`
- [ ] 3.1.2 Validate path is within workspace using existing `isPathInWorkspace`
- [ ] 3.1.3 For `.pdf` files: inject assertive Read instruction with document name, prohibit "which document?" questions
- [ ] 3.1.4 For text files under 100KB: read content via `fs.readFile`, inject into system prompt as artifact content
- [ ] 3.1.5 For text files over 100KB: inject assertive Read instruction with file size info
- [ ] 3.1.6 On any read error: fall back to assertive Read instruction (not the passive one from PR #2422)
- [ ] 3.1.7 All branches must include "Do not ask which document the user is referring to" language

### 3.2 Tests for Phase 3

- [ ] 3.2.1 Unit test: Text file under 100KB → system prompt contains file content
- [ ] 3.2.2 Unit test: Text file over 100KB → system prompt contains assertive Read instruction with size
- [ ] 3.2.3 Unit test: PDF file → system prompt contains PDF-specific instruction with filename
- [ ] 3.2.4 Unit test: All context injection branches include "do not ask which document" language
- [ ] 3.2.5 Unit test: System prompt never contains absolute workspace paths
- [ ] 3.2.6 Unit test: Path traversal attempt (context.path with "..") → rejected by isPathInWorkspace
