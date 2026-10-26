---
title: Headless Pencil adapter runs on @pen.dev/cli behind a stable tool surface, with a stale-file save guard
status: active
date: 2026-10-26
issue: 11156
supersedes: null
related: [11168, 11143, 8964, 9310]
---

# ADR-304: Headless Pencil adapter runs on @pen.dev/cli behind a stable tool surface, with a stale-file save guard

## Context

The headless Pencil MCP adapter (`plugins/soleur/skills/pencil-setup/scripts/pencil-mcp-adapter.mjs`) drove `@pencil.dev/cli` 0.2.9, which npm marks deprecated ("no longer maintained"). The maintained successor is `@pen.dev/cli` (0.3.13 when measured on 2026-10-26; `engines.node >=22.19.0`; bins `pen` and `pencil`). Its `pen interactive` REPL exposes only `execute`, `get_app_state`, `get_style`, `read_skill` and `browser`, plus the shell commands `save()` and `exit()`. The tools the adapter used to forward (`batch_design`, `batch_get`, `get_editor_state`, `get_screenshot`, `export_nodes`, `snapshot_layout`, `get_variables`, `get_guidelines`) answer `Unknown tool:`; their jobs moved inside the `execute` DSL (`TakeScreenshot`, `Export`, `Get`, `GetVariables`, `## issues detected:`).

Agents, hooks (`.claude/hooks/pencil-open-guard.sh`, `pencil-collapse-guard.sh`, keyed on `mcp__pencil__open_document`) and prose all name the `mcp__pencil__*` tools. On a customer machine the adapter's save sentinel is the only protection a design file has, since this repository's hooks do not exist there. The earlier sentinel refused an EMPTY in-memory document over a non-empty file but allowed any save when memory held at least one node, so a session holding 5 nodes could overwrite 8 nodes that landed on disk behind it (`git pull`, a second session, Pencil Desktop).

## Decision

**Engine.** Pin `@pen.dev/cli@0.3.13`, installed from a committed lockfile (`plugins/soleur/skills/pencil-setup/scripts/pen-cli/`) with `npm ci` into its own prefix `~/.local/share/pen-cli`. The adapter resolves only that prefix's `.bin/pen`, whose realpath must equal the package's declared `bin.pen` target and whose package name must be `@pen.dev/cli`. There is no PATH fallback, so a leftover `@pencil.dev/cli` can never be reached through a shared bin name and is only a warning. Node floor is 22.19.0.

**Tool surface.** The `mcp__pencil__*` names stay, so no hook or `.claude/settings.json` change is needed. The adapter translates eight live tools onto the REPL (`open_document`, `save`, `batch_design`, `get_screenshot`, `export_nodes`, `get_editor_state`, `get_variables`, `read_skill`). Nine tools the engine cannot honour (`batch_get`, `snapshot_layout`, `get_guidelines`, `get_style_guide`, `get_style_guide_tags`, `find_empty_space_on_canvas`, `search_all_unique_properties`, `replace_all_matching_properties`, `set_variables`) are registered as stubs that never reach the engine and answer with a replacement hint from one table. Raw `execute` is not exposed, so no second mutation path bypasses the open and save guards.

**Authentication.** The key resolves from `PEN_CLI_KEY`, else `PENCIL_CLI_KEY` (empty or whitespace counts as unset). The child always receives `PEN_CLI_KEY` only; both names are redacted in several encodings. The existing Doppler value authenticates as `PEN_CLI_KEY`, so the secret is not renamed. An invalid key does not stop the engine (its usage check fails open), so the key-gated probe asserts `pen status` is Active first.

**Still needed from the old design.** `planSpawn` stays, because `pen interactive --out existing.pen` without `--in` still loads an empty document. The `I`/`U` alias preamble stays, because only the long DSL names exist.

**Save sentinel (#11168).** `decideSave` keeps its predicate and refusal text. After it, a separate pure function `decideStale` compares a SHA-256 fingerprint of the document's canonical JSON (raw bytes only when the text does not parse) against a per-process baseline that is captured from the file immediately before every spawn and re-set only after a confirmed `Saved <path>` reply. Baseline states are tagged (`none`, `missing`, `hash`, `unknown`); only an exact `missing` or `hash` match may save. A stale refusal sets `refusalPending`, which survives a crash respawn until `open_document` succeeds, and echoes the refused operations (capped, redacted) so replay does not depend on agent context. Every refusal writes one `[pencil-adapter] REFUSED save: [reason=<code>]` stderr line from one `logRefusal` helper. Exactly one `save()` emission site exists. Deleting every top-level node stays refused with no escape hatch (a flag is itself the bypass).

**REPL framing.** The prompt must be at the end of the buffer after a 50 ms quiet period; bytes after it mean desync (kill and restart from the saved file). The save confirmation is string equality after realpath of both sides. The memory probe uses a per-call random nonce and counts only a line that matches it exactly. Engine errors arrive on stderr and ANSI codes are present on piped output, so the adapter strips ANSI and drains stderr after each prompt.

## Consequences

- **Accepted residual:** `batch_design` forwards raw DSL, so host functions that take paths (`Export`, image-fill URLs) are reachable without `export_nodes` validation. The DSL runs in a QuickJS sandbox with no `process`, `require`, `fetch` or `XMLHttpRequest` (measured). The key-gated probe records what `Export` and local-file image fills do and pins it; if it ever overwrites arbitrary files or reads local files the adapter switches to a shadowing prelude.
- **Window the stale guard cannot close:** a second writer between the fresh read and the engine's write, and whatever lands between the engine's write and the post-save read. There is no lock; one writer per file is a documented rule. A change during engine startup refuses the first save.
- **Not measured:** whether the engine's write is atomic, and how it handles a file written by a newer Desktop. The design depends on neither; a truncated file is caught by the existing unrecognizable-file refusal on the next save.
- **Lockfile wiring:** a fifth lockfile directory is registered under ADR-191's lockfile-sync and Dependabot wiring.
- **Alternatives rejected:** renaming the tools to the native names (forces hook and prose churn for no capability); size+mtime as the fingerprint (misses same-size rewrites and a checkout that restores identical bytes); a `batch_get`/`snapshot_layout` shim (invents a node-dump format the engine does not offer); a PATH fallback or auto-uninstall of the deprecated package; renaming the Doppler secret (a production mutation with no benefit).
- **Open items outside this change:** `sharp` install failures on hosts with a global libvips (#8964) and the unbounded install in `copy_adapter.sh` (#9310) are unchanged.
