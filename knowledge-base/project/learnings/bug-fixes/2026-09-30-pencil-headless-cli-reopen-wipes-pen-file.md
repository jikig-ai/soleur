---
title: 'headless Pencil CLI reopens an existing .pen as empty — save() then wipes it'
date: 2026-09-30
category: agent-workflow, mcp-integration
tags: [pencil, headless, pen, wireframe, ux-design-lead, destructive-wipe]
type: bug-fix
---

# headless Pencil CLI reopens an existing `.pen` as empty — `save()` then wipes it

## Problem

On a host where Pencil MCP tools (`mcp__pencil__*`) are unavailable and the
`ux-design-lead` agent drives the headless CLI (`pencil interactive --out
<file.pen>`) directly, **a second `interactive` session against an existing
`.pen` loads an EMPTY document** — `Get`/`execute` find no nodes and report
`Can't find node` — and `save()` in that state truncates the file on disk. The
design agent watched its own 150 KB save collapse to 96 bytes. This is the
headless-CLI analogue of the adapter's `open_document` collapse bug (#3274 /
upstream #4859), but it lives one layer down: `pencil-collapse-guard.sh` is a
PostToolUse hook on the MCP `open_document` call, which never fires when the
REPL is driven through Bash.

## Solution

Never run a second `--out` session against an existing `.pen`. For a revision
loop, build the new document in ONE session writing to a fresh path
(`<name>-vN.pen`), `stat -c %s` to verify it is non-empty, then `mv` it over
the canonical filename. Exported PNGs overwrite safely in place.

## Key Insight

The collapse-guard chain (PreToolUse `pencil-open-guard.sh` + PostToolUse
`pencil-collapse-guard.sh` + the ux-design-lead prose HARD GATEs) only exists
on the MCP tool surface. Driving `pencil interactive` via Bash bypasses all of
it, so the guard must move into the orchestrator's spawn prompt: new output
path per session + size check + atomic rename.

## Session Errors

1. Design subagent died mid-run (dirs created, no output, no completion
   notification) — respawned with a verified command surface.
   **Prevention:** probe `pencil interactive --help` in the orchestrator before
   spawning, so the prompt carries the real REPL commands.
2. `xdg-open` failed on this Hyprland host (nautilus/GNOME display-proxy
   error); `imv` works.
   **Prevention:** on Omarchy/Hyprland hosts prefer `imv`/`swayimg` for
   screenshot review; `xdg-open` → nautilus is not reliable.
3. `gitleaks` flagged the `.pen` `fileToken` (generic-api-key false positive);
   `.gitleaksignore` already carries the convention
   (`<path>:generic-api-key:<line>`).
   **Prevention:** none needed — the waiver convention exists; just check the
   file for siblings first.
4. `ask_user_question` blocked by the technical-fork gate when the question was
   a routing decision (brainstorm vs one-shot).
   **Prevention:** routing/methodology choices are the agent's; reserve
   operator questions for scope, priority, authorization.
5. Issue-filing gate rejected a relative `--body-file` path and a `Fix-Size:`
   written as `<files> / <lines>` — it requires an absolute path and the exact
   `<N> lines / <M> files` order.
   **Prevention:** read the gate's error text literally; it names the format.
6. Headless `.pen` reopen wipe (this file's subject).
   **Prevention:** the v2-path + size-check + mv pattern above.
