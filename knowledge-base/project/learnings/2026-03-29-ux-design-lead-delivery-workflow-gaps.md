# Learning: UX Design Lead Delivery Workflow Gaps

## Problem

The UX design lead agent produced wireframes in Pencil but the delivery step had three compounding workflow gaps that made the output unusable without manual intervention: (1) `get_screenshot` produces 512x320px images that are unreadable for design review, (2) exported files are named with Pencil node IDs (e.g., `bBxvQ-2026-03-29T18-08-45.png`) which are meaningless to humans, and (3) the screenshots folder was not auto-opened so the founder had to explicitly ask to see the deliverables.

## Solution

Fixed the ux-design-lead agent Step 3 (Deliver) with three changes:

1. **High-resolution export** -- Use `export_nodes` with `scale: 3` instead of `get_screenshot` for final deliverables. This produces 4096x2560px images vs 512x320px.
2. **Human-readable naming** -- Rename exported files from node IDs to kebab-case names with zero-padded sequential numbers (e.g., `01-dashboard-empty-state.png`).
3. **Auto-open for review** -- Run `xdg-open` on the screenshots folder as the final delivery step. This is mandatory, not optional.

Additionally: updated the brainstorm skill Phase 4 to note that the UX design lead auto-opens screenshots, and added a `.gitignore` exception (`!knowledge-base/product/design/**/screenshots/*.png`) so design screenshots are tracked in version control.

## Key Insight

Delivery is not done when artifacts exist on disk -- delivery is done when artifacts are reviewable by the recipient. Three properties must hold for any agent-produced visual deliverable: sufficient resolution for the review context, human-meaningful filenames, and automatic presentation to the reviewer.

## Session Errors

1. **Low-resolution screenshots** -- `get_screenshot` produces 512x320px thumbnails, unusable for design review. Recovery: discovered `export_nodes` with `scale: 3`. Prevention: fixed in agent instructions.

2. **Node ID screenshot names** -- Files named with Pencil internal node IDs. Recovery: manual rename. Prevention: fixed in agent instructions.

3. **Screenshots folder not auto-opened** -- Founder had to explicitly ask. Recovery: manual `xdg-open`. Prevention: fixed in agent instructions and brainstorm skill.

4. **Design files saved to repo root, not worktree** -- MCP tools resolve from repo root. Recovery: copied files manually. Prevention: already in AGENTS.md.

5. **PNGs gitignored** -- Blanket `*.png` rule blocked design screenshots. Recovery: added `.gitignore` exception. Prevention: exception now committed.

6. **Wrong milestone name** -- Used "Phase 2 -- Command Center" vs actual "Phase 2: Secure for Beta". Recovery: listed milestones via API and retried. Prevention: always list milestones first with `gh api repos/{owner}/{repo}/milestones --jq '.[].title'`.

7. **web-platform bun install failed in worktree** -- Frozen lockfile mismatch. Recovery: continued without install (not needed for design task). Prevention: run `bun install` without `--frozen-lockfile` in worktrees.

## Tags

category: workflow-gap
module: plugins/soleur/agents/ux-design-lead, plugins/soleur/skills/brainstorm
