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

**Existing headless registration: Node floor and key name.** A headless registration made before the migration can carry a Node older than 22.19.0 (the adapter then exits at startup) or the deprecated key name `PENCIL_CLI_KEY`. Compare both with the preferred ones. Read the key NAME only: the registered environment holds the key value, so the filter below prints names and nothing else.

```bash
needs_rereg=false; node_status=n/a; registered_key_names=""
if [[ "$existing_mode" == "headless_cli" ]]; then
  # Only a headless registration's command is a Node binary; never run an IDE or Desktop binary with -e.
  registered_node=$(printf '%s\n' "$existing" | sed -E 's/^pencil: *([^ ]+) .*/\1/')
  registered_key_names=$(claude mcp get pencil 2>&1 | grep -oE 'PENCIL_CLI_KEY|PEN_CLI_KEY' | sort -u | tr '\n' ' ')
  node_status=$("$registered_node" -e 'const [a,b]=process.versions.node.split(".").map(Number);console.log(a>22||(a===22&&b>=19)?"ok":"old")' 2>/dev/null || echo missing)
  [[ "$node_status" != "ok" || "$registered_node" != "$PREFERRED_NODE" ]] && needs_rereg=true
  [[ "$registered_key_names" != *PEN_CLI_KEY* ]] && needs_rereg=true   # only the deprecated name (or none) is registered
fi
```

**Auto-upgrade rule (when `--auto` is set):** if `existing_mode` is `ide` or `desktop` AND Phase 0 set `PREFERRED_MODE=headless_cli`, the existing registration is unsuitable for agent-driven flows (no programmatic save — see Sharp Edges §"No programmatic save"). The same applies to a headless registration with `needs_rereg=true` (registered Node differs from `PREFERRED_NODE` or is below 22.19.0, or the registered key name is not `PEN_CLI_KEY`). Remove and re-register as headless instead of stopping:

```bash
if [[ "$AUTO_INSTALL" == "true" && "$PREFERRED_MODE" == "headless_cli" && ( "$existing_mode" != "headless_cli" || "$needs_rereg" == "true" ) ]]; then
  echo "Re-registering Pencil MCP as headless_cli (was $existing_mode; node=$node_status; key names: ${registered_key_names:-none})"
  claude mcp remove pencil -s user 2>/dev/null || true
  # Fall through to Step 2 to register fresh
else
  # Verify the registered binary path still exists on disk before declaring "ready".
  # Extract the path from `claude mcp list` output, then `test -f <path>`.
  case "$existing_mode" in
    headless_cli) echo "Pencil MCP is already configured via headless CLI adapter. Restart Claude Code for tools to become available."
                  [[ "$needs_rereg" == "true" ]] && echo "NOTE: the registered Node or key name is outdated; re-run with --auto to re-register." ;;
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

The adapter requires `PEN_CLI_KEY` in the MCP environment (the name the `@pen.dev/cli` engine reads) and refuses to start without it; there is no interactive-login path. The deprecated name `PENCIL_CLI_KEY` is still accepted as a fallback (an empty or whitespace value counts as unset, `PEN_CLI_KEY` wins when both are set) and prints one value-free deprecation line, so registrations made before the migration keep working. The child process always receives `PEN_CLI_KEY` only, and only the resolved key value is redacted from its output (the other name is never forwarded). The Doppler secret is still named `PENCIL_CLI_KEY`; only the registration name changes. Load the key, then register with `-e` **before** the `--` separator:

```bash
export PEN_CLI_KEY="$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain)"

claude mcp add pencil -s user -e PEN_CLI_KEY="$PEN_CLI_KEY" -- <PREFERRED_NODE> <PREFERRED_BINARY>
```

Replace `<PREFERRED_NODE>` with the Node 22.19+ binary path and `<PREFERRED_BINARY>` with the adapter path from Phase 0. The key passed with `-e` before `--` is stored in the server's environment, not in the adapter's argv; the only argv exposure is the transient `claude mcp add` process, visible to other local users in `ps` while it runs. Re-register with `PEN_CLI_KEY` to silence the deprecation line.

**Engine binary override (rare).** The adapter resolves `pen` only inside the pinned prefix (see "pencil CLI collision" below). To use a different `pen`, add the flag to the adapter arguments at registration: `-- <PREFERRED_NODE> <PREFERRED_BINARY> --pencil-binary=<absolute path to pen>`. The `PENCIL_BINARY` environment variable alone is ignored (the adapter prints a value-free WARN naming it): an env block can be set by a project settings file, argv is only set by the user-approved registration.

**Critical:** The `-e` flag must appear before `--`. Placing it after `--` passes it as a CLI arg to the adapter instead of setting an environment variable, causing silent auth failures.

**Drift check.** If the adapter ever appears to "silently drop" operations, verify the installed copy is in sync with the repo:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/check_deps.sh" --check-adapter-drift
# On DRIFT, re-sync: add --auto (copies the adapter AND installs the engine from the lockfile), or re-run copy_adapter.sh
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
- **Reads through `batch_design` also auto-save**: every `batch_design` call, including a read-only `Get`/`Print` one, ends with the guarded save, so under an unpersisted state it is marked `REFUSED save:` or `NOT PERSISTED:` too. To look at the document in that state use `get_editor_state` (top-level node list) or `open_document`. `export_nodes` and `get_screenshot` render from memory: while any edit is unpersisted their reply is prefixed `WARNING: rendered from unsaved memory, not the file on disk`.
- **pencil CLI collision**: The `pencil` binary name collides with evolus/pencil, and `@pen.dev/cli` ships a `pencil` alias of `pen`. The adapter and check_deps.sh resolve only `pen` inside the pinned prefix `.local/share/pen-cli` (realpath must equal the package's declared `bin.pen`, a regular file; package name `@pen.dev/cli`) and never `pencil` or a PATH lookup. The prefix home is the passwd home, then `$HOME` when different (a container may differ); a candidate is used only when the package directory is outside the working directory and `CLAUDE_PROJECT_DIR`, owned by the current user, and not group- or world-writable, so a redirected `$HOME` or a project-supplied path cannot supply the binary. A leftover install of the deprecated `pencil.dev` package only prints a warning and is never used.
- **Headless CLI interactive mode is not MCP**: `pen interactive` speaks a custom REPL (`tool_name({ key: value })` after a `pen >` prompt), not the MCP protocol. The adapter bridges it to Claude Code's MCP framework and is the only supported way to drive it headless.
- **Headless CLI has programmatic save**: Unlike Desktop/IDE modes, `pen interactive --out` supports a `save()` command that writes to disk without manual Ctrl+S, and it is the only thing that writes the `.pen` (startup, `exit()` and SIGTERM leave the file untouched).
- **Headless engine contract (#11143, #11156)**: the adapter targets `@pen.dev/cli` **0.3.13** (exact pin, installed from the committed lockfile into `~/.local/share/pen-cli` by `check_deps.sh`; Node >= 22.19.0, an older Node makes the adapter exit with a message naming the installed and required versions). The agent-facing `mcp__pencil__*` names are unchanged; the adapter translates them onto the engine REPL (`execute`, `get_app_state`, `read_skill`, `save`) through `formatReplCommand` in `pencil-repl-surface.mjs`, which throws on a tool or key not in its table. Live tools (8): `open_document`, `save`, `batch_design`, `get_screenshot`, `export_nodes`, `get_editor_state`, `get_variables`, `read_skill`. `batch_design` takes `operations` (forwarded as `execute({ input })` behind a per-call preamble that makes the short aliases `I()`/`U()`/`C()`/`R()`/`M()`/`D()`/`G()` work; the reply ends with a `Document: <path>` line, and an `## issues detected:` block, which is how layout problems arrive, is passed through and does not skip the save). `read_skill({ path })` returns design guidance and the DSL grammar read-only (`guide/<name>.md`, or no path for the index; guides: components, code, design-system, landing-page, mobile-app, slides, table, tailwind, web-app). `get_editor_state` returns the top-level node list (`include_schema` is accepted and ignored). `export_nodes` needs an absolute `outputDir` inside the working directory or the `.pen` directory, lists any file it overwrote, and does NOT rename: png, jpeg and webp exports are named `{nodeId}.{format}`, and a pdf export combines the nodes into one `export.pdf`. Nine Desktop/IDE-only tools do not exist headless and answer `Unknown tool:` with a replacement hint, never saving: `batch_get`, `snapshot_layout`, `get_guidelines`, `get_style_guide`, `get_style_guide_tags`, `find_empty_space_on_canvas`, `search_all_unique_properties`, `replace_all_matching_properties`, `set_variables`. An unknown key is dropped by the engine and answered `OK`, hence the strict table. A save counts only when the reply is exactly `Saved <path>`; a definite `Save failed: <reason>` is a `NOT PERSISTED: [reason=save-failed]` result (see the reason tables).
- **One writer per file**: there is no lock. Two sessions, git, an editor, or Pencil Desktop with the same `.pen` open are all writers; the stale-file guard refuses a save after another writer changed the file, it does not stop the other writer. Keep one writer per file, and close Pencil Desktop's tab for a file an agent is editing headless (Desktop keeps its own in-memory copy and rewrites the file on its own save, which makes the next agent save refuse).
- **`open_document` loads the existing file**: the adapter passes `--in <file>` when the target exists and is non-empty, so reopening resumes the design; a respawn after a crash reloads the saved file, never a template `inputPath`. It reports `N top-level node(s) loaded` (plus a warning line when the file's baseline could not be captured) and fails (refusing every tool until the next successful `open_document`) when fewer top-level nodes loaded than the file holds on disk (any drop, not only an empty load; the same check runs on the load after a crash respawn), or is not a recognizable `.pen` document at all (an unparseable `--in` file makes the engine exit; a parseable one with no usable nodes loads EMPTY without an error; a count cannot see dropped nested nodes). To work from a file the engine cannot load faithfully, open a new path: the original is never modified. Targets must be plain `.pen` files: a wrong extension or a symlink is refused, and `inputPath` (a template) is refused when `filePath` already holds a document, because the first save would replace it.
- **Save sentinel**: every save (auto-save and the explicit `save` tool) is one exclusive job that reads the file, probes the in-memory document, and refuses (`REFUSED save:`, first line of the tool result) three things: an empty document over a file that still holds nodes, anything over a file that exists but is not a recognizable `.pen` document, and (stale rule, #11168) any save over a file that **changed on disk** since this session loaded or last saved it. The adapter keeps one SHA-256 baseline of the document (canonical JSON, so line-ending changes and reformatting do not count) captured before each load and re-set after each confirmed save; an identical rewrite behind the session is allowed, a changed node value is refused even when the new document is smaller or the same size (the hash covers the whole document, and a read error other than "not found" gives an unknown baseline, never a pass; documents over 64 MiB are not read). The in-memory node count comes from a read-only `execute` probe whose count line carries a per-call nonce (anything else is unreadable and refuses). To start a design over, open a new file path; do not delete or recreate the file to bypass it (there is no override flag). A file REMOVED behind a live session (a branch switch, a move, a delete) does not refuse: the engine's copy is the only one left, so the save recreates the file (stderr `[reason=recreated]`) and the result is prefixed `NOTE: <file> had been removed from disk ...`; tell the user and check the file belongs at that path (after a crash respawn the engine's copy is gone, so that case refuses as `refusal-pending`, `cause=file-missing`). Recovery from a stale refusal: stop editing, call `open_document` on the same file (this discards in-memory edits since the last save), then replay the refused operations in order; a `batch_design` refusal echoes them (up to 64 KiB, key redacted) so the replay does not depend on agent context (re-bind any variables from earlier calls; an explicit `save` refusal echoes nothing). The repo's open guard denies an untracked file: commit an empty placeholder first if the path is untracked. If `open_document` fails on the changed file, stop, do not retry or recreate it, and tell the user another tool changed the file. After a crash respawn a stale refusal stays armed until `open_document` succeeds, and a respawn that finds the file changed or missing since the last save arms one too. In this repo the collapse hook asks for a snapshot before a re-open: copy the `.pen` aside first (`cp <file> <file>.bak`, outside git), then follow the refusal's re-open advice; on a customer machine no hook exists and the copy is advisable anyway. Windows it cannot close: a second writer landing between the guard's fresh read and the engine's write is not caught, and whatever lands between the engine's write and the post-save read becomes the new baseline. A change to the file during engine startup makes the first save refuse (fails safe). Keep one writer per file (see "One writer per file"). This is the only protection on a customer machine, where this repo's open/collapse hooks do not exist.
- **REFUSED save: reasons**: the first line of a refusal tool result (every one) is `REFUSED save: [reason=<code>] <file> was not modified.`, and the adapter writes the same marker to its stderr (`[pencil-adapter] REFUSED save: [reason=<code>] <file> ...`; hashes appear as 8-hex-char prefixes only). The file is never modified by a refusal. Recovery by code:

  | Code | Meaning | Recovery |
  |---|---|---|
  | `reason=stale` | The file changed on disk since this session loaded or last saved it | Stop editing, `open_document` the same file, replay the echoed operations in order; keep one writer |
  | `reason=unknown-baseline` | The last save was not confirmed, the post-save read failed, or the baseline capture failed (`cause=` says which) | `open_document` the file, compare the node count it reports with what the design should hold, then replay |
  | `reason=refusal-pending` | A refusal is armed with a `cause=`: `restart` (the session restarted after an earlier refusal), `external-change` (a crash respawn found the file changed; the engine reloaded the new content and nothing on disk was overwritten), or `file-missing` (a crash respawn found the file gone; the earlier edits were in the engine and are lost) | `open_document` the file, then replay the edits from your own record (for `file-missing` recreate them: the file was removed, so restore it with `git checkout -- <file>` when tracked or `open_document` a new path) |
  | `reason=empty` | The in-memory document is empty over a file that holds nodes, or its node count could not be read (unreadable memory fails closed) | Re-open the file with `open_document` and continue; to start over, open a new path |
  | `reason=unrecognized` | The file exists but is not a recognizable `.pen` document | Do not overwrite it; restore it from git or choose a new path |

  A save that did not become a confirmed save but is not a refusal begins `NOT PERSISTED: [reason=<code>] <file> ...` (stderr carries the same marker). Treat it as unpersisted exactly like a refusal:

  | Code | Meaning | Recovery |
  |---|---|---|
  | `reason=save-failed` | The engine answered a definite `Save failed: <reason>`; the edit is in memory only and the previous baseline is kept | Fix the cause (permissions, disk space, path) and call `save` again; do NOT call `open_document` (it discards the only copy of the edit) |
  | `reason=unconfirmed` | The save reply was ambiguous, empty, timed out or named another path, so the file state is unknown | `open_document` the file, compare the node count with what the design should hold, then replay |
  | `reason=save-incomplete` | The edit was applied but the save step threw or did not complete | Call `save` and follow what it returns (a refusal names its own recovery); do not assume the edit is on disk |

  The engine `Saved <path>` reply is the only confirmation; anything else is one of the codes above. An unpersisted state clears only on a confirmed save or a successful `open_document`. The post-save gate in `soleur:product:design:ux-design-lead` treats both markers as unpersisted.

- **Bumping the CLI pin**: run `doppler run -p soleur -c dev -- bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/engine-contract-probe.sh"` first. It diffs the CLI's `--help` signatures against the adapter's table and does a real round trip (it prints `PROBE SKIPPED (no key)` and exits 3 without `PEN_CLI_KEY`). Re-capture the redacted transcript fixture and update the lockfile in the same change; the probe is the oracle for engine drift and is deliberately not a required CI job.
- **Adapter child process Node version**: The adapter spawns the CLI with its own Node (`process.execPath`), so the engine runs on the Node that launched the adapter. That Node must be 22.19.0 or newer; `check_deps.sh` finds one (`PREFERRED_NODE`) and the adapter's startup gate names the installed and required versions.
- **Text nodes do not support `padding`**: Passing `padding` to a `batch_design` operation on a text node produces "Invalid properties: /padding unexpected property". The adapter enriches this error with a hint, but the fix is to wrap the text in a frame and apply padding to the frame instead (see #1107 workaround).
- **Silent-drop diagnosis**: When a Pencil MCP op appears to "silently drop" or produces a 0-byte `.pen`, verify in order: (a) read the tool result and the adapter stderr marker first (a `REFUSED save:` or `NOT PERSISTED:` first line with `[reason=<code>]`, or `isError` text, names the cause; see the reason tables above; adapter stderr lines start `[pencil-adapter]` and land in Claude Code's MCP server log, and `claude mcp list` shows whether the server connected), (b) the registered key NAME is right, checked without printing the environment: `claude mcp get pencil 2>&1 | grep -oE 'PENCIL_CLI_KEY|PEN_CLI_KEY' | sort -u` should print `PEN_CLI_KEY`; the value must match Doppler `soleur/dev` (compare by re-running the registration, never by printing it), (c) `bash "${CLAUDE_PLUGIN_ROOT}/skills/pencil-setup/scripts/check_deps.sh" --check-adapter-drift` prints `OK`, (d) the saved file is larger than the 96-byte empty document (a bare `> 0` accepts an empty document; the wireframe agent's post-save gate checks this with `node -e`), (e) when the server fails to start, the stderr line `[pencil-adapter] ERROR:` names the cause: Node below the floor (installed and required versions), a missing or empty key, or a failed module import (re-run `check_deps.sh --auto` to repair the engine and adapter). "Headless stub" is NOT a known failure mode — the adapter has no stub code path. (`ex-cq-pencil-mcp-silent-drop-diagnosis-checklist`; #2630; `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md`)
