---
name: pencil-setup
description: "This skill should be used when Pencil MCP tools are unavailable. Detects Pencil Desktop or a Pencil-extension IDE and registers the MCP server with Claude Code CLI."
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# Pencil Setup

Auto-detect, install, and register the Pencil MCP server with Claude Code CLI.

**Prerequisite:** One of: (1) the headless CLI (no GUI required, recommended for agents), (2) Pencil Desktop, or (3) an IDE (Cursor/VS Code) with the Pencil extension.

**Known limitation:** macOS detection uses unverified bundle ID `dev.pencil.desktop` -- falls back to PATH-based detection if incorrect.

## Phase 0: Dependency Check

Run [check_deps.sh](./scripts/check_deps.sh) before proceeding. When invoked
from a pipeline (e.g., one-shot), pass `--auto` to skip interactive prompts,
auto-install the IDE extension, and auto-launch Pencil Desktop.

For interactive use:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/check_deps.sh"
```

For pipeline/automated use:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/check_deps.sh" --auto
```

If the script exits non-zero, no Pencil MCP source is available. Stop and
inform the user with the printed instructions (both Desktop and IDE options).

If all checks pass, capture these values from the script output:

- `PREFERRED_MODE` -- `headless_cli`, `cli`, `desktop_binary`, or `ide`
- `PREFERRED_BINARY` -- path to binary (adapter for headless, `pencil` for CLI mode)
- `PREFERRED_APP` -- `--app` flag value (empty for CLI and headless modes)
- `PREFERRED_NODE` -- (headless_cli only) path to Node >= 22.19.0 binary (the `@pen.dev/cli` engine floor)

Proceed to Step 1.

## Step 1: Check if Already Registered

<!-- verified: 2026-04-19 source: claude mcp list --help (the `-s` flag was dropped from `list`; plain `claude mcp list` now includes user-scoped entries) -->

```bash
claude mcp list 2>&1 | grep -q "pencil" && echo "REGISTERED" || echo "NOT_REGISTERED"
```

If REGISTERED, classify the existing registration mode by inspecting the binary path printed by `claude mcp list`:

```bash
existing=$(claude mcp list 2>&1 | grep pencil)
case "$existing" in
  *pencil-mcp-adapter*|*@pen.dev/cli*|*pencil-cli*) existing_mode=headless_cli ;;
  *visual_studio_code*|*cursor*)                       existing_mode=ide ;;
  *--app\ pencil*|*mcp-server-*-x64*)                   existing_mode=desktop ;;
  *)                                                   existing_mode=unknown ;;
esac
```

**Auto-upgrade rule (when `--auto` is set):** if `existing_mode` is `ide` or `desktop` AND Phase 0 set `PREFERRED_MODE=headless_cli`, the existing registration is unsuitable for agent-driven flows (no programmatic save — see Sharp Edges §"No programmatic save"). Remove and re-register as headless instead of stopping:

```bash
if [[ "$AUTO_INSTALL" == "true" && "$existing_mode" != "headless_cli" && "$PREFERRED_MODE" == "headless_cli" ]]; then
  echo "Upgrading Pencil MCP from $existing_mode → headless_cli (agent-driven flows require programmatic save)"
  claude mcp remove pencil -s user 2>/dev/null || true
  # Fall through to Step 2 to register fresh
else
  # Verify the registered binary path still exists on disk before declaring "ready".
  # Extract the path from `claude mcp list` output, then `test -f <path>`.
  case "$existing_mode" in
    headless_cli) echo "Pencil MCP is already configured via headless CLI adapter. Restart Claude Code for tools to become available." ;;
    desktop)      echo "Pencil MCP is already configured. Make sure Pencil Desktop is running, then restart Claude Code." ;;
    ide)          echo "Pencil MCP is already configured. Make sure your IDE is running with Pencil active, then restart Claude Code. NOTE: IDE mode does not auto-save .pen edits — use --auto to upgrade to headless if running agent-driven flows." ;;
    *)            echo "Pencil MCP is registered but mode could not be classified. Re-run with --auto to refresh registration." ;;
  esac
  # Stop here unless --auto-upgrading.
fi
```

If the path does not exist, NOT_REGISTERED, or the auto-upgrade path was taken, continue to Step 2.

## Step 2: Register MCP Server

Registration varies by `PREFERRED_MODE` from Phase 0:

Remove any existing registration first:

```bash
claude mcp remove pencil -s user 2>/dev/null
```

### Headless CLI mode (`PREFERRED_MODE=headless_cli`)

**First**, sync the repo adapter into the user's install location so stale installed copies don't mask repo-level fixes (see #2630):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/copy_adapter.sh"
```

The adapter requires `PEN_CLI_KEY` in the MCP environment (the name the `@pen.dev/cli` engine reads). The deprecated name `PENCIL_CLI_KEY` is still accepted as a fallback (an empty or whitespace value counts as unset, `PEN_CLI_KEY` wins when both are set) and prints one value-free deprecation line, so registrations made before the migration keep working. The child process always receives `PEN_CLI_KEY` only. The Doppler secret is still named `PENCIL_CLI_KEY`; only the registration name changes. Retrieve the key, then register with `-e` **before** the `--` separator:

```bash
# Retrieve the key (Doppler, or log in once with `pen login`)
PEN_KEY=$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain 2>/dev/null)

claude mcp add pencil -s user -e PEN_CLI_KEY="$PEN_KEY" -- <PREFERRED_NODE> <PREFERRED_BINARY>
```

Replace `<PREFERRED_NODE>` with the Node 22.19+ binary path and `<PREFERRED_BINARY>` with the adapter path from Phase 0. A key passed with `-e` is visible in the process arguments of the registered command to other local users; the adapter prints a stderr line saying so. Re-register with `PEN_CLI_KEY` to silence the deprecation line.

**Critical:** The `-e` flag must appear before `--`. Placing it after `--` passes it as a CLI arg to the adapter instead of setting an environment variable, causing silent auth failures.

**Drift check.** If the adapter ever appears to "silently drop" operations, verify the installed copy is in sync with the repo:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/check_deps.sh" --check-adapter-drift
# On DRIFT, re-sync: add --auto, or re-run copy_adapter.sh
```

### CLI mode (`PREFERRED_MODE=cli`)

```bash
claude mcp add -s user pencil -- pencil mcp-server
```

No `--app` flag needed -- the CLI handles connection internally.

### Desktop binary mode (`PREFERRED_MODE=desktop_binary`)

```bash
claude mcp add -s user pencil -- <PREFERRED_BINARY> --app <PREFERRED_APP>
```

Replace `<PREFERRED_BINARY>` and `<PREFERRED_APP>` with values from Phase 0.

### IDE mode (`PREFERRED_MODE=ide`)

```bash
claude mcp add -s user pencil -- <PREFERRED_BINARY> --app <PREFERRED_APP>
```

Replace `<PREFERRED_BINARY>` with the extension binary path and `<PREFERRED_APP>` with `cursor` or `visual_studio_code`.

## Step 3: Verify

```bash
claude mcp list 2>&1 | grep pencil
```

If the `pencil` entry appears, tell the user:

- **Headless CLI mode:** "Pencil MCP registered via headless adapter. Restart Claude Code for tools to become available. No GUI required."
- **CLI/Desktop mode:** "Pencil MCP registered. Restart Claude Code for tools to become available. Make sure Pencil Desktop is running."
- **IDE mode:** "Pencil MCP registered. Restart Claude Code for tools to become available. Make sure your IDE is open with Pencil active."

If it does not appear, tell the user the registration failed and suggest running the commands manually.

## Untracked .pen safety

Rule `cq-before-calling-mcp-pencil-open-document` is canonical in `.claude/hooks/pencil-open-guard.sh` header (see that file for the full body and rationale). The hook is a PreToolUse deny on untracked `.pen` files; pre-flight to avoid the deny:

```bash
git -C <repo> ls-files --error-unmatch <path>   # exit 0 = tracked, exit 1 = untracked
```

For freshly-created `.pen` files, commit an empty or scaffold placeholder before the first `open_document` call.

## Tracked .pen collapse recovery

Rule `cq-pencil-collapse-auto-recover` is canonical in the `.claude/hooks/pencil-collapse-guard.sh` header `[hook-enforced: pencil-collapse-guard.sh]`. It is the deterministic backstop for the `open_document` truncation bug (#3274 / upstream #4859): the PreToolUse `pencil-open-guard.sh` only denies *untracked* `.pen`, and the soleur:product:design:ux-design-lead / brand-workshop prose HARD-GATEs (PR #4855) rely on agent discipline.

The hook fires **PostToolUse** on `mcp__pencil__open_document`. When the on-disk `.pen` has collapsed to the unambiguous empty-document shape (`{"version":"...","children":[]}` or a 0-byte/whitespace truncation) while its committed `HEAD` blob is non-empty, it restores the file byte-identical from `git show HEAD:<path>` (written via a temp file + atomic `mv`) and emits a loud `additionalContext` system message. It is fail-open and non-destructive on every error path (`set -uo pipefail`, no `-e`; conservative collapse detection limited to the exact empty shape; symlinks are refused) — a guard that clobbers good work is strictly worse than the bug. It cannot *prevent* the truncation (PostToolUse runs after the write); the root-cause fix is upstream (#4859 Part B).

**Caveat:** because PostToolUse cannot see the pre-call state, an *intentional* empty (you cleared all frames then reopened without committing) is indistinguishable from a truncation and will be reverted to `HEAD`. Commit the deliberate empty state first if you want it preserved.

## Sharp Edges

- **IDE mode -- WebSocket requires visible editor**: In IDE mode (`PREFERRED_MODE=ide`), the MCP server connects via WebSocket to the IDE's editor webview. `batch_design`/`batch_get`/`open_document` calls fail with `WebSocket not connected to app` unless the .pen file tab is open and visible in the IDE. Opening via `cursor <path>` CLI is not sufficient -- the user must click the tab to activate the webview.
- **Desktop mode -- app must be running**: In CLI or Desktop binary mode, Pencil Desktop must be running. The MCP server connects to the Desktop app directly. If Desktop is not running, tools fail silently. Use `--auto` to auto-launch Desktop before registration.
- **No programmatic save (Desktop/IDE only)**: In Desktop or IDE mode, after `batch_design` operations, changes exist in editor memory only. The user must Ctrl+S (IDE) or Cmd+S/Ctrl+S (Desktop) to flush to disk. In headless CLI mode, the adapter auto-calls `save()` after mutating operations — no manual save needed.
- **Read before write**: Mockup property values (padding, colors, fonts) may diverge from live CSS. Always read the current value before updating it: headless, with `Get`/`Print` inside a `batch_design` call (see the next edit); Desktop/IDE, with `batch_get`.
- **Reads through `batch_design` also auto-save**: every `batch_design` call, including a read-only `Get`/`Print` one, ends with the guarded save, so under a `REFUSED save:` it is refused too. To look at the document in that state use `get_editor_state` (top-level node list) or `open_document`.
- **pencil CLI collision**: The `pencil` binary name collides with evolus/pencil, and `@pen.dev/cli` ships a `pencil` alias of `pen`. The adapter and check_deps.sh resolve only `pen` inside the pinned prefix `~/.local/share/pen-cli` (realpath must equal the package's declared `bin.pen`, package name `@pen.dev/cli`) and never `pencil` or a PATH lookup. A leftover install of the deprecated `pencil.dev` package only prints a warning and is never used.
- **Headless CLI interactive mode is not MCP**: `pen interactive` speaks a custom REPL (`tool_name({ key: value })` after a `pen >` prompt), not the MCP protocol. The adapter bridges it to Claude Code's MCP framework and is the only supported way to drive it headless.
- **Headless CLI has programmatic save**: Unlike Desktop/IDE modes, `pen interactive --out` supports a `save()` command that writes to disk without manual Ctrl+S, and it is the only thing that writes the `.pen` (startup, `exit()` and SIGTERM leave the file untouched).
- **Headless engine contract (#11143, #11156)**: the adapter targets `@pen.dev/cli` **0.3.13** (exact pin, installed from the committed lockfile into `~/.local/share/pen-cli` by `check_deps.sh`; Node >= 22.19.0, an older Node makes the adapter exit with a message naming the installed and required versions). The agent-facing `mcp__pencil__*` names are unchanged; the adapter translates them onto the engine REPL (`execute`, `get_app_state`, `read_skill`, `save`) through `formatReplCommand` in `pencil-repl-surface.mjs`, which throws on a tool or key not in its table. Live tools (8): `open_document`, `save`, `batch_design`, `get_screenshot`, `export_nodes`, `get_editor_state`, `get_variables`, `read_skill`. `batch_design` takes `operations` (forwarded as `execute({ input })` behind a per-call preamble that makes the short aliases `I()`/`U()`/`C()`/`R()`/`M()`/`D()`/`G()` work; the reply ends with a `Document: <path>` line, and an `## issues detected:` block, which is how layout problems arrive, is passed through and does not skip the save). `read_skill({ path })` returns design guidance and the DSL grammar read-only (`guide/<name>.md`, or no path for the index; guides: components, code, design-system, landing-page, mobile-app, slides, table, tailwind, web-app). `get_editor_state` returns the top-level node list (`include_schema` is accepted and ignored). `export_nodes` needs an absolute `outputDir` inside the working directory or the `.pen` directory, lists any file it overwrote, and does NOT rename: the engine names files `{nodeId}.{format}`. Nine Desktop/IDE-only tools do not exist headless and answer `Unknown tool:` with a replacement hint, never saving: `batch_get`, `snapshot_layout`, `get_guidelines`, `get_style_guide`, `get_style_guide_tags`, `find_empty_space_on_canvas`, `search_all_unique_properties`, `replace_all_matching_properties`, `set_variables`. An unknown key is dropped by the engine and answered `OK`, hence the strict table. A save counts only when the reply is exactly `Saved <path>`; `Save failed: <reason>` is an error.
- **One writer per file**: there is no lock. Two sessions, git, an editor, or Pencil Desktop with the same `.pen` open are all writers; the stale-file guard refuses a save after another writer changed the file, it does not stop the other writer. Keep one writer per file, and close Pencil Desktop's tab for a file an agent is editing headless (Desktop keeps its own in-memory copy and rewrites the file on its own save, which makes the next agent save refuse).
- **`open_document` loads the existing file**: the adapter passes `--in <file>` when the target exists and is non-empty, so reopening resumes the design; a respawn after a crash reloads the saved file, never a template `inputPath`. It reports `N top-level node(s) loaded` and fails (refusing every tool until the next successful `open_document`) when the file it loaded from holds nodes that did not load, or is not a recognizable `.pen` document at all (an unparseable `--in` file makes the engine exit; a parseable one with no usable nodes loads EMPTY without an error). Targets must be plain `.pen` files: a wrong extension or a symlink is refused, and `inputPath` (a template) is refused when `filePath` already holds a document, because the first save would replace it.
- **Save sentinel**: every save (auto-save and the explicit `save` tool) is one exclusive job that reads the file, probes the in-memory document, and refuses (`REFUSED save:`) three things: an empty document over a file that still holds nodes, anything over a file that exists but is not a recognizable `.pen` document, and (stale rule, #11168) any save over a file that **changed on disk** since this session loaded or last saved it. The adapter keeps one SHA-256 baseline of the document (canonical JSON, so line-ending changes and reformatting do not count) captured before each load and re-set after each confirmed save; an identical rewrite behind the session is allowed, a changed node value is refused even when the new document is smaller or the same size. The in-memory node count comes from a read-only `execute` probe whose count line carries a per-call nonce (anything else is unreadable and refuses). To start a design over, open a new file path; do not delete or recreate the file to bypass it (there is no override flag). Recovery from a stale refusal: stop editing, call `open_document` on the same file (this discards in-memory edits since the last save), then replay the refused operations in order; the refusal text echoes them (up to 64 KiB) so the replay does not depend on agent context. If `open_document` fails on the changed file, stop, do not retry or recreate it, and tell the user another tool changed the file. After a crash respawn a stale refusal stays armed until `open_document` succeeds. In this repo the collapse hook asks for a snapshot before a re-open: copy the `.pen` aside first (`cp <file> <file>.bak`, outside git), then follow the refusal's re-open advice; on a customer machine no hook exists and the copy is advisable anyway. Windows it cannot close: a second writer landing between the guard's fresh read and the engine's write is not caught, and whatever lands between the engine's write and the post-save read becomes the new baseline. A change to the file during engine startup makes the first save refuse (fails safe). Keep one writer per file (see "One writer per file"). This is the only protection on a customer machine, where this repo's open/collapse hooks do not exist.
- **REFUSED save: reasons**: the first line of a refusal carries `[reason=<code>]`, and the adapter writes the same marker to stderr (`[pencil-adapter] REFUSED save: [reason=<code>] <file> ...`; hashes appear as 8-hex-char prefixes only). The file is never modified by a refusal. Recovery by code:

  | Code | Meaning | Recovery |
  |---|---|---|
  | `reason=stale` | The file changed on disk since this session loaded or last saved it | Stop editing, `open_document` the same file, replay the echoed operations in order; keep one writer |
  | `reason=missing` | The file was removed behind the session | Do not recreate it by hand; restore it (`git checkout -- <file>` when tracked) then `open_document` and replay, or `open_document` a new path and replay there |
  | `reason=unknown-baseline` | The last save was not confirmed, the post-save read failed, or the baseline capture failed (`cause=` says which) | `open_document` the file, compare the node count it reports with what the design should hold, then replay |
  | `reason=refusal-pending` | The session restarted after an earlier refusal and the edits before the restart were discarded | `open_document` the file, then replay the edits |
  | `reason=empty` | The in-memory document is empty over a file that holds nodes | Re-open the file and continue; to start over, open a new path |
  | `reason=unrecognized` | The file exists but is not a recognizable `.pen` document | Do not overwrite it; restore it from git or choose a new path |

- **Bumping the CLI pin**: run `doppler run -p soleur -c dev -- bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/engine-contract-probe.sh"` first. It diffs the CLI's `--help` signatures against the adapter's table and does a real round trip (it prints `PROBE SKIPPED (no key)` and exits 3 without `PEN_CLI_KEY`). Re-capture the redacted transcript fixture and update the lockfile in the same change; the probe is the oracle for engine drift and is deliberately not a required CI job.
- **Adapter child process Node version**: The adapter spawns the CLI with its own Node (`process.execPath`), so the engine runs on the Node that launched the adapter. That Node must be 22.19.0 or newer; `check_deps.sh` finds one (`PREFERRED_NODE`) and the adapter's startup gate names the installed and required versions.
- **Text nodes do not support `padding`**: Passing `padding` to a `batch_design` operation on a text node produces "Invalid properties: /padding unexpected property". The adapter enriches this error with a hint, but the fix is to wrap the text in a frame and apply padding to the frame instead (see #1107 workaround).
- **Silent-drop diagnosis**: When a Pencil MCP op appears to "silently drop" or produces a 0-byte `.pen`, verify in order: (a) read the tool result and the adapter stderr marker first (a `REFUSED save: [reason=<code>]` or `isError` text names the cause; see the reason table above), (b) `claude mcp get pencil` env has `PEN_CLI_KEY` (or the deprecated `PENCIL_CLI_KEY`) matching Doppler `soleur/dev`, (c) `bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/check_deps.sh" --check-adapter-drift` prints `OK`, (d) the saved file is larger than the 96-byte empty document (a bare `> 0` accepts an empty document; the ux-design-lead post-save gate checks this with `node -e`). "Headless stub" is NOT a known failure mode — the adapter has no stub code path. (`ex-cq-pencil-mcp-silent-drop-diagnosis-checklist`; #2630; `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md`)
