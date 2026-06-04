# Learning: Pencil headless — load PENCIL_CLI_KEY from Doppler before declaring a Phase 3.55 hard-block

## Problem

During the #4916 workspace-logo-upload brainstorm (a UI feature, so the
`wg-ui-feature-requires-pen-wireframe` gate fired), Phase 3.55 needed a Pencil
`.pen` wireframe. Two things looked like a hard-block but weren't:

1. `check_deps.sh --auto` tried to launch Pencil Desktop; the AppImage
   **core-dumped** (`Trace/breakpoint trap (core dumped)`) — expected in a headless
   environment with no display.
2. `check_deps.sh` then reported `[skip] Headless CLI found but auth failed`, which
   reads exactly like the skill's "auth genuinely unsatisfiable" hard-block condition.

Taken at face value, this would have produced a false Phase 3.55 hard-block on a
feature that could in fact be wireframed.

## Solution

The key **existed in Doppler `soleur/dev`** the whole time — it just wasn't in the
shell environment, and `check_deps.sh` does not source Doppler itself. Loading it
flipped headless CLI to available:

```bash
export PENCIL_CLI_KEY="$(doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain)"
bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
# => [ok] Headless CLI (Tier 0)   PREFERRED_MODE=headless_cli
```

Separately, `claude mcp list` already showed
`pencil: ...pencil-mcp-adapter.mjs - ✓ Connected`, and
`mcp__pencil__get_editor_state` returned a live active editor — so the in-session
MCP tools worked, and the ux-design-lead agent authored the `.pen` + 4 screenshots
normally. The "auth failed" line was about the bare-CLI invocation, not the
connected MCP adapter.

## Key Insight

`check_deps.sh` reporting "auth failed" is **not** sufficient evidence that Pencil
auth is unsatisfiable. Before declaring the Phase 3.55 hard-block, (a) export
`PENCIL_CLI_KEY` from Doppler `soleur/dev` and re-run the check, and (b) confirm the
in-session MCP adapter state with `claude mcp list | grep pencil` +
`mcp__pencil__get_editor_state` — a `✓ Connected` adapter can author `.pen` files
even when the standalone CLI auth-check fails. The hard-block is genuinely warranted
only when the key is absent from Doppler AND there is no interactive login AND no
connected MCP adapter.

The Desktop AppImage core-dump in a headless environment is expected and benign — it
is the trigger to fall through to the headless-CLI path, not a blocker.

## Session Errors

1. **Pencil Desktop AppImage core-dumped on `--auto` in headless env.**
   Recovery: ignored (expected) and used the headless-CLI path.
   Prevention: headless sessions should skip the Desktop-launch attempt; the
   `--auto` fallback to headless CLI already handles this — treat the core-dump as
   the fall-through signal, not an error.
2. **`check_deps.sh` "auth failed" with the key sitting unused in Doppler.**
   Recovery: `export PENCIL_CLI_KEY=$(doppler secrets get ... )` then re-check.
   Prevention: brainstorm Phase 3.55 must load the key from Doppler before declaring
   a hard-block (route-to-definition edit applied to the brainstorm SKILL.md).

## Tags
category: integration-issues
module: pencil-setup, brainstorm
