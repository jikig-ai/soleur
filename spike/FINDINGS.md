# Agent SDK Spike Findings

**Date:** 2026-03-16
**SDK Version:** @anthropic-ai/claude-agent-sdk 0.2.76
**Result:** PASS — Agent SDK works for the web platform use case

## What Works

| Feature | Status | Details |
|---------|--------|---------|
| SDK initialization | PASS | Hooks fire (hook_started, hook_response), init message received |
| Streaming | PASS | 265 messages received, 250 partial (streaming text deltas) |
| File tools (Read, Glob) | PASS | Agent read KB files and listed directory contents |
| Bash tool | PASS | Agent used Bash to find files when initial path was wrong |
| `canUseTool` callback | PASS | Fires before tool execution, receives tool name + input with file_path |
| Session ID | PASS | Generated unique session ID (UUID format) for resume |
| `persistSession: false` | PASS | Ephemeral sessions work — no disk persistence |
| `maxTurns` / `maxBudgetUsd` | PASS | Budget/turn limits respected |
| Plugin loading | PASS | Soleur plugin loaded via `plugins: [{ type: 'local', path: '...' }]` — hooks fired |

## Key API Patterns

### query() signature
```typescript
const q = query({
  prompt: "...",
  options: {
    cwd: workspacePath,           // Workspace directory
    model: "claude-sonnet-4-6",   // Model selection
    permissionMode: "default",    // Use canUseTool for permissions
    includePartialMessages: true, // Stream partial text
    persistSession: false,        // No disk persistence
    maxTurns: 5,
    maxBudgetUsd: 0.50,
    canUseTool: async (toolName, input, options) => {
      // Workspace sandbox: check file paths
      // Review gates: intercept AskUserQuestion
      return { allow: true };
    },
    plugins: [{ type: 'local', path: './plugins/soleur' }],
  },
});
```

### Message types observed
- `system` (subtypes: `hook_started`, `hook_response`, `init`)
- `assistant` (content blocks: `text`, `tool_use`)
- `result` (subtype: `success`, includes `session_id`)
- Partial messages (streaming text deltas, ~250 per query)

### canUseTool behavior
- **Only fires when tools are NOT pre-approved** via `allowedTools` or `.claude/settings.json`
- Receives: `toolName` (string), `input` (full tool input including `file_path`), `options` (signal, suggestions, toolUseID)
- Returns: `{ behavior: "allow" }` or `{ behavior: "deny", message: "..." }`
- Does NOT cache permissions per tool name (#876 verified empirically). The "1 call vs 5 tool uses" observation was caused by two independent factors: (a) pre-approved tools in `.claude/settings.json` bypass `canUseTool` at permission chain step 4, and (b) Claude Code's bridge auth handles permissions internally without consulting `canUseTool`. Under BYOK keys (production), the callback fires per-invocation.
- For workspace sandbox: validate `input.file_path` starts with user workspace path

### BYOK key injection
- Use `env: { ANTHROPIC_API_KEY: decryptedKey }` in options
- When omitted, SDK uses Claude Code's built-in authentication
- Confirmed in SDK types: `env?: { [envVar: string]: string | undefined }`

### Plugin loading
- `plugins: [{ type: 'local', path: '/absolute/path/to/plugin' }]` loads Soleur agents/skills/hooks
- Plugin hooks fired (hook_started, hook_response) — confirms plugin was loaded
- Agents defined in plugin are available via the Agent tool

## Concerns and Mitigations

### 1. License
- License field says "SEE LICENSE IN README.md" → points to https://code.claude.com/docs/en/legal-and-compliance
- Not an explicit open-source license (Apache/MIT). Subject to Anthropic's usage terms.
- **Action needed:** Review the legal agreements page to confirm hosted multi-tenant use is permitted.

### 2. canUseTool "caching" (DISPROVEN — #876)
- The callback was only called once for 5 tool uses. This was NOT SDK caching — two independent factors caused the observation:
  1. The spike workspace had `.claude/settings.json` with `permissions.allow: ["Read", "Glob", "Grep"]`, causing those tools to be resolved at permission chain step 4 (allow rules) before reaching step 5 (`canUseTool`).
  2. Running under Claude Code's bridge auth bypasses `canUseTool` entirely — the bridge handles permissions internally.
- **Resolution:** The SDK does NOT cache `canUseTool` results. Each invocation receives a unique `toolUseID`. The `suggestions` field is the SDK's intended mechanism for externalizing permission caching to the host. See `apps/web-platform/test/canusertool-caching.test.ts` for the empirical verification.
- **For the web platform (BYOK keys):** `canUseTool` fires on every tool invocation as expected. Workspace sandbox via `canUseTool` is safe.

### 3. Path resolution
- First Read attempted `/root/knowledge-base/...` instead of workspace-relative path
- Agent self-corrected using Bash to find the correct location
- **Mitigation:** Set `cwd` correctly. The agent's `Read` tool resolves relative to CWD.

## Recommendations for Phase 1

1. Use `permissionMode: "default"` with `canUseTool` for workspace sandbox
2. Pre-approve safe tools via `allowedTools: ["Read", "Glob", "Grep"]` — use `canUseTool` only for dangerous tools (Bash, Write, Edit)
3. Pass BYOK key via `env: { ANTHROPIC_API_KEY: key }`
4. Load Soleur plugin via `plugins: [{ type: 'local', path: '...' }]`
5. Use `persistSession: false` for web sessions (no disk state)
6. Stream `SDKMessage` events directly to WebSocket
7. Test AskUserQuestion interception specifically before building review gate UI
