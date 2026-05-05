---
date: 2026-05-05
category: best-practices
tags: [pencil-mcp, brand-workshop, ux-design-lead, headless-cli, ide-mode, agent-tool-selection]
related-prs: [3233]
related-issues: [3232]
related-learnings:
  - knowledge-base/project/learnings/best-practices/2026-05-05-brand-workshop-needs-ux-mockup-gate.md
---

# Pencil MCP: agents must use the headless CLI, not the IDE/Desktop registration

## What happened

During brand-workshop step 4.5 for PR #3233 (Solar Radiance light palette), `ux-design-lead` was dispatched to render side-by-side mockups via Pencil MCP. The agent rendered all six required surfaces (button states, card, input states, nav, modal, error state) successfully — `mcp__pencil__get_screenshot` against the live editor returned a clean image — but every attempt to call `mcp__pencil__export_nodes` for the PNG export failed with:

```
MCP error -32603: failed to execute tool call. you are probably referencing the wrong .pen file
```

Root cause: the registered Pencil MCP was the VS Code IDE-extension binary (`/home/harry/.vscode/extensions/highagency.pencildev-0.6.48/out/mcp-server-linux-x64 --app visual_studio_code`). In IDE mode, `batch_design`/`batch_get`/`open_document` mutations live in the editor's in-memory state and only flush to disk on a manual Ctrl+S. `export_nodes` reads from disk, so it returned a generic "wrong .pen file" error against a 0-byte file. There is no `save_document` MCP tool. From within an agent shell with no GUI keystroke capability (`xdotool` not installed, `wmctrl` can focus but not type, no sudo), there is no automated path to flush the buffer.

The headless CLI adapter (`PREFERRED_MODE=headless_cli` in `pencil-setup`) auto-calls `save()` after every mutating op. Same mockup work in headless mode would have produced a saved `.pen` ready for `export_nodes`.

## Why the agent picked the wrong mode

`pencil-setup`'s Phase 0 (`check_deps.sh`) already prioritizes `headless_cli` as Tier 0. But the agent never ran `pencil-setup` — it used `claude mcp list` to confirm Pencil MCP was registered, saw the IDE-mode binary path, and proceeded. The skill's Step 1 said "If REGISTERED, ... then stop." with no condition for upgrading an unsuitable existing registration.

The brand-workshop skill said "If Pencil MCP tools are not loaded, run skill: soleur:pencil-setup first to register them" — which is satisfied when *any* mode is registered, even one with the no-flush gap.

## Fix applied

1. **`plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md` step 4.5.0** — hard-gate: detects current Pencil MCP mode via `claude mcp list` pattern matching, refuses to proceed unless `headless_cli`, exits with instructions to run `pencil-setup --auto` and resume from a fresh session.
2. **`plugins/soleur/skills/pencil-setup/SKILL.md` Step 1** — auto-upgrade rule: when `--auto` is passed AND existing registration mode is `ide` or `desktop` AND `PREFERRED_MODE=headless_cli` from Phase 0, remove the existing registration and re-register fresh via Step 2 instead of stopping with "already configured."

Both changes shipped in the same commit on `feat-brand-guide-light`.

## Key insight

Agent-driven flows that produce on-disk artifacts (commits, exports, diffs, screenshots-from-disk) MUST use a Pencil MCP mode with programmatic save. The headless CLI adapter is the only mode that satisfies this. IDE/Desktop modes are designed for human designers who can press Ctrl+S; they are not suitable backends for agent automation.

Generalizable lesson: when a tool offers multiple registration modes and one has a hidden human-in-the-loop step, agent tooling must encode mode preference at the workflow gate, not leave it to discovery-via-failure.

## Session Errors

1. **Picked IDE-mode Pencil MCP over headless without checking suitability.** Recovery: founder caught the gap mid-flow, authorized discard. Prevention: brand-workshop step 4.5.0 now hard-gates headless mode before ux-design-lead dispatch.

2. **Treated existing MCP registration as sufficient.** The agent reasoning was "Pencil MCP is registered, so proceed" — should have been "Pencil MCP is registered in mode X; is mode X suitable for the export pipeline this workflow needs?" Prevention: `pencil-setup --auto` now upgrades unsuitable IDE/Desktop registrations to headless when headless is available.

3. **Committed scaffold .pen without running compound first.** Violated `wg-before-every-commit-run-compound-skill`. The scaffold was a workflow-mechanism commit (empty placeholder for the pencil-open-guard hook), but the rule has no scaffolding exception. Recovery: hard-reset reverted the scaffold commit during the discard step. Prevention: rule reading is correct as-is; agent must run compound for every commit including mechanical scaffolds. No skill change.

4. **Treated a `rmdir: directory not empty` failure as cleanup success.** Compound shell chain `rm && rmdir && git reset --soft && git restore --staged && git status` short-circuited at `rmdir` (leftover `export/` dir from a Pencil MCP operation), but the next commands didn't run, leaving the scaffold commit on the branch. Caught only when `git log` showed it still present. Prevention: per `hr-when-a-command-exits-non-zero-or-prints`, investigate non-zero exits before proceeding. For cleanup chains, prefer `set -e` semantics or read each step's exit code explicitly.

## Prevention summary

- **Workflow gate (already applied):** brand-workshop step 4.5.0 refuses non-headless Pencil MCP modes for agent runs.
- **Tool gate (already applied):** `pencil-setup --auto` now upgrades unsuitable existing registrations.
- **No new AGENTS.md rule needed:** the constraint is now domain-scoped (Pencil MCP) and skill-enforced. Per `cq-agents-md-tier-gate`, domain-scoped insights belong in the owning skill, not AGENTS.md.

## Related

- `plugins/soleur/skills/pencil-setup/SKILL.md` Sharp Edges §"No programmatic save (Desktop/IDE only)" — pre-existing documentation of the gap; the missing piece was a workflow gate that *enforced* the implication for agents.
- `knowledge-base/project/learnings/best-practices/2026-05-05-brand-workshop-needs-ux-mockup-gate.md` — sibling learning that established the mockup gate itself; this learning extends it with the mode-selection constraint.
