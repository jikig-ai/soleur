# Learning: a new `.pen` needs a committed skeleton before `open_document`

## Problem

Phase 3.55 wireframe for #9545 PR2 (egress audit log read path). `mcp__pencil__open_document` on a path that did not exist yet was refused by the PreToolUse hook: "`.pen` file is untracked in git". The `ux-design-lead` definition says a brand-new document is exempt from the snapshot/collapse gate, which reads as "just open it" and is silent on the hook.

## Solution

`Write` `{"version":"2.18","variables":{<tokens copied from agent-web-access.pen>},"children":[]}`, `git add` + commit it, then `open_document`. The headless adapter loads 0 nodes, applies each `batch_design`, and rewrites the file on disk (version 2.14, a `fileToken`, ~800 KB for 21 frames). Verified before authoring: `get_editor_state` listed the inserted node, and the reference `agent-web-access.pen` stayed at 88861 bytes and git-clean (it was never opened; tokens were read from the JSON file instead).

## Key Insight

Authoring-tool preconditions (hook gates, collapse gates) are written for iteration on existing files; the new-file path has its own gate. Also: `get_screenshot` auto-saves `<nodeId>-<timestamp>.png` into the `screenshots/` dir (delete before commit), `export_nodes` named files after the frame name rather than the node id, lucide has no `clock` icon (`hourglass` works), empty `fit_content` spacer frames collapse (give `fill_container` + fixed height), and a screen frame shorter than its column reports "partially clipped" in `snapshot_layout`.

## Session Errors

1. **`open_document` refused on an untracked new `.pen`** — Recovery: committed an empty skeleton first — Prevention: routed into `ux-design-lead.md` Step 2 item 3 (new-file bullet).
2. **Read exported PNGs by `{nodeId}.png`; adapter wrote frame-name files** — Recovery: `ls` the export dir — Prevention: routed into `ux-design-lead.md` Step 3 item 4.
3. **Stray `get_screenshot` captures written into `screenshots/`** — Recovery: deleted before commit — Prevention: same new-file bullet.
4. **Pencil warnings: missing `clock` icon, collapsed empty spacers, clipped screens** — Recovery: `hourglass`, `fill_container` + height, taller screen frames — Prevention: one-off authoring detail, recorded here only.
5. **Created the worktree with `git worktree add` instead of `worktree-manager.sh`** — Recovery: none needed (branch already existed and was pushed; no install required) — Prevention: one-off; the manager's `feature` command creates a new branch, so it does not fit resuming an existing one.

## Tags

category: workflow-issues
module: product/design (ux-design-lead, Pencil MCP)
