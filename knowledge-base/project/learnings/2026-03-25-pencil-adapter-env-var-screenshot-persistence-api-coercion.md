---
module: pencil-mcp-adapter
date: 2026-03-25
problem_type: integration-debugging
component:
  - plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs
  - plugins/soleur/skills/pencil-setup/SKILL.md
symptoms:
  - "MCP adapter times out with: [pencil-adapter] Timed out waiting for prompt after 30000ms"
  - "PENCIL_CLI_KEY missing from adapter process.env despite -e flag in claude mcp add"
  - "get_screenshot returns inline base64 but no file saved to disk"
  - "set_variables rejects bare hex strings with unclear error message"
root_cause: wrong_flag_ordering
resolution_type: code_fix
severity: high
tags: [pencil, mcp, adapter, env-var, screenshot, auto-coercion, dogfooding, defense-in-depth]
---

# Pencil MCP Adapter: Env Var Misregistration, Screenshot Persistence, and Variable Auto-Coercion

## Problem

Three issues discovered during pencil headless CLI dogfooding (#656):

1. **MCP adapter couldn't authenticate** — `PENCIL_CLI_KEY` was passed as CLI args instead of env var, so pencil's auth check hung and the adapter timed out after 30s.
2. **Screenshots not persisted** — `get_screenshot` returned base64 image data inline but never saved to disk. Users couldn't review wireframes outside the conversation.
3. **Variable format rejection** — `set_variables` required `{type: "color", value: "#hex"}` objects but bare hex strings like `"#0A0A0A"` were rejected with `Variable 'bg' does not have a valid definition`.

## Environment

- Module: pencil-mcp-adapter
- Node Version: 22.9.0+
- Pencil CLI: 0.2.3 (headless)
- Date: 2026-03-25

## Root Cause

### Env var misregistration

The `claude mcp add` command was called with `-e` flag **after** the `--` separator:

```bash
# WRONG — -e becomes a CLI arg to the adapter, not an MCP env var
claude mcp add -s user pencil -- /path/to/node /path/to/adapter.mjs -e PENCIL_CLI_KEY=xxx
```

Verified by inspecting `/proc/<pid>/environ` — `PENCIL_CLI_KEY` was absent. The adapter's `buildPencilEnv()` reads from `process.env`, so the child pencil process got no auth key.

### Screenshots not persisted

The `get_screenshot` handler was registered via the `registerReadOnlyTool` factory, which only receives `(text, isError)` — no access to the `nodeId` parameter. Without the nodeId, there was no meaningful filename to save to disk.

### Variable format

Pencil's `set_variables` API requires typed objects `{type: "color"|"string"|"number", value: <v>}`. The error message doesn't show the expected format. Also, `type: "font"` is not valid — fonts use `type: "string"`.

## Solution

### Fix 1: Correct MCP registration (root cause)

Place `-e` **before** `--`:

```bash
claude mcp add pencil -s user -e PENCIL_CLI_KEY="$KEY" -- /path/to/node /path/to/adapter.mjs
```

Updated SKILL.md with correct flag ordering and bold warning.

### Fix 2: Defense-in-depth `-e` argv parsing

Added to adapter startup — parses `-e KEY=VALUE` from `process.argv` and injects into `process.env` if the key isn't already set:

```javascript
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "-e" && i + 1 < process.argv.length) {
    const eqIdx = process.argv[i + 1].indexOf("=");
    if (eqIdx > 0) {
      const key = process.argv[i + 1].slice(0, eqIdx);
      const val = process.argv[i + 1].slice(eqIdx + 1);
      if (!process.env[key]) {
        process.env[key] = val;
      }
    }
    i++;
  }
}
```

### Fix 3: Screenshot auto-save

Refactored `get_screenshot` from factory registration to direct `server.tool()` to access the `nodeId` parameter. Added `saveScreenshot()` helper:

```javascript
function saveScreenshot(base64Data, nodeId) {
  const penFile = pencilProcess.outputFile;
  if (!penFile) return null;
  const screenshotDir = join(dirname(penFile), "screenshots");
  mkdirSync(screenshotDir, { recursive: true });
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const filename = `${nodeId}-${timestamp}.png`;
  const filePath = join(screenshotDir, filename);
  writeFileSync(filePath, Buffer.from(base64Data, "base64"));
  return filePath;
}
```

Screenshots are now saved to `screenshots/<nodeId>-<timestamp>.png` next to the .pen file, and the file path is included in the MCP response.

### Fix 4: Variable auto-coercion

Refactored `set_variables` from factory registration to direct `server.tool()`. Added auto-coercion before forwarding to pencil:

- `"#0A0A0A"` (hex pattern) → `{type: "color", value: "#0A0A0A"}`
- `0` (number) → `{type: "number", value: 0}`
- `"Inter"` (string) → `{type: "string", value: "Inter"}`
- `{type: "color", value: "#hex"}` → passed through as-is

## Session Errors

1. **Pencil MCP timeout (x2)** — `get_editor_state` timed out because adapter couldn't auth. Recovery: Inspected `/proc/<pid>/environ`, found missing key, re-registered MCP. Prevention: Defense-in-depth argv parsing + SKILL.md docs fix.

2. **MCP tools disconnected after mid-session re-registration** — `claude mcp remove` + `claude mcp add` caused all pencil tools to become unavailable until next turn. Recovery: Tools reconnected automatically. Prevention: Document as known limitation — MCP re-registration mid-session causes temporary tool loss.

3. **`set_variables` rejected bare hex strings** — Error: `Variable 'bg' does not have a valid definition: "#0A0A0A"`. Recovery: Discovered typed object format through trial and error. Prevention: Auto-coercion in adapter.

4. **`set_variables` rejected `type: "font"`** — Error: `invalid 'type' property: "font"`. Recovery: Used `type: "string"` instead. Prevention: Auto-coercion handles this — all non-hex strings become `type: "string"`.

5. **`batch_design` rejected `alignSelf`** — Error: `unexpected property`. Recovery: Removed property, used parent alignment. Prevention: Filed #1106.

6. **`batch_design` rejected `padding` on text nodes** — Error: `unexpected property`. Recovery: Wrapped text in frames. Prevention: Filed #1107.

## Key Insight

`claude mcp add` flag ordering matters — `-e` must appear before `--`. The `--` separator means "everything after this is the command and its args." Flags after `--` become literal arguments to the spawned process, not `claude mcp add` options. This is standard POSIX convention but easy to get wrong when constructing commands programmatically.

Defense-in-depth matters for MCP adapters — the adapter should work even if its env vars arrive through the wrong channel, since the registration command is written by LLMs that may not respect flag ordering.

## Prevention

- When writing `claude mcp add` commands in skills/docs, always place `-e` flags before `--` and add a warning about ordering
- MCP adapters that depend on env vars should include argv parsing as fallback
- MCP tools that return binary data (images, exports) should always persist to disk in addition to returning inline — users need to review artifacts outside the conversation
- When an external API rejects input format, add auto-coercion in the adapter layer rather than waiting for upstream fixes

## Related

- [pencil-headless-cli-interactive-mode-not-mcp](./2026-03-24-pencil-headless-cli-interactive-mode-not-mcp.md) — the adapter architecture
- [pencil-batch-design-text-node-gotchas](./2026-03-10-pencil-batch-design-text-node-gotchas.md) — related API gotchas
- [pencil-adapter-path-node-version-mismatch](./integration-issues/pencil-adapter-path-node-version-mismatch-20260325.md) — related PATH/env fix
- [token-env-var-not-cli-arg](./2026-02-18-token-env-var-not-cli-arg.md) — secrets via env var pattern
- GitHub: #1106 (alignSelf), #1107 (padding on text), #1108 (variable format)
