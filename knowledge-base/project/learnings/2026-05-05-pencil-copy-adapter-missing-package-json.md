# Learning: copy_adapter.sh skipped npm-ci because it never copies package.json

## Problem

`plugins/soleur/skills/pencil-setup/scripts/copy_adapter.sh` had an npm-ci branch (lines 67-72) gated on `$INSTALL_DIR/package.json` existing, but the script never copied `package.json` or `package-lock.json` into the install dir — only the five `.mjs` adapter files. Result on a fresh install:

1. `copy_adapter.sh` reports `OK: copied 5 file(s)` and exits 0.
2. The npm-ci conditional silently skips because `package.json` isn't present in `$INSTALL_DIR`.
3. At MCP registration time, `claude mcp list` reports `Failed to connect`.
4. Running the adapter directly errors with `Cannot find package '@modelcontextprotocol/sdk' imported from .../pencil-mcp-adapter.mjs`.

The error message itself was helpful and pointed at the right install dir, but blamed `copy_adapter.sh` drift ("may be missing node_modules or out of sync with repo") rather than the actual gap (the script can't ever install deps on a fresh dir because it doesn't copy the manifest first).

## Solution

Add `package.json` and `package-lock.json` to the `ADAPTER_FILES` array in `copy_adapter.sh`. The existing npm-ci branch then fires correctly on first install and on every subsequent sync.

```diff
 ADAPTER_FILES=(
   "pencil-mcp-adapter.mjs"
   "pencil-error-enrichment.mjs"
   "sanitize-filename.mjs"
   "pencil-response-classify.mjs"
   "pencil-save-gate.mjs"
+  "package.json"
+  "package-lock.json"
 )
```

End-to-end verification: removed `~/.local/share/pencil-adapter`, ran `copy_adapter.sh` → reported `copied 7 file(s)`, npm-ci ran, `node_modules/@modelcontextprotocol/sdk` exists, adapter responds to `initialize` JSON-RPC.

## Key Insight

Conditional install branches that depend on files the same script doesn't copy will silently no-op on every fresh install. The failure surfaces only at runtime, far from the script that was supposed to set things up. When writing a `cp + maybe install` script, the manifest files are part of the install surface — treat them like any other adapter file.

## Session Errors

- **MCP registration pointed at worktree path with no node_modules** — Recovery: re-pointed at `~/.local/share/pencil-adapter` after `copy_adapter.sh` runs. Prevention: SKILL.md Step 2 already documents the install-path registration pattern; the underlying gap was the missing manifest copy, fixed in this commit.
- **Install dir lacked node_modules after copy_adapter.sh** — Recovery: discovered package.json wasn't copied, fixed the script. Prevention: the `ADAPTER_FILES` change.
- **Edit landed in worktree but verification grep used main-checkout relative path** — Recovery: re-grepped using worktree absolute path. Prevention: when iterating across worktree + main checkout in the same session, always pass absolute paths to verification commands too, not just to mutating tools (Edit / Write).
- **Skipped session-start `cleanup-merged` + `.mcp.json` refresh** — Recovery: not load-bearing here (in main checkout, worktree pre-existed, MCP refresh handled manually as part of the headless upgrade). Prevention: worth noting that `/soleur:go` continuation prompts bypass the bare-root session-start rituals; if the user is on the bare root, those steps still need to run before resuming.

## Tags

category: integration-issues
module: plugins/soleur/skills/pencil-setup
