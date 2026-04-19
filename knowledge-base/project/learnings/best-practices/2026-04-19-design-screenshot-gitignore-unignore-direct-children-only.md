---
date: 2026-04-19
category: best-practices
tags: [gitignore, design, ux-design-lead, pencil-mcp, screenshots]
related_pr: 2645
related_issue: 2636
---

# Design screenshot `.gitignore` unignore covers direct children only

## Problem

When recreating `knowledge-base/product/design/billing/upgrade-modal-at-capacity.pen` (PR #2645, issue #2636), the plan and the agent prompt prescribed exporting high-res PNG screenshots to a nested subfolder:

```text
knowledge-base/product/design/billing/screenshots/upgrade-modal-at-capacity/
  01-at-capacity-solo-plan.png
  02-isolated-modal-component.png
  03-at-capacity-startup-plan.png
```

After `ux-design-lead` produced the files and `git status` ran, the screenshots were silently `.gitignore`d. They never appeared in `git status` until I checked `git check-ignore -v` explicitly.

## Root Cause

`.gitignore` line 57 unignores PNGs under design directories with a glob that does NOT recurse into nested subfolders:

```gitignore
!knowledge-base/product/design/**/screenshots/*.png
```

`**` matches the parent path freely, but `*.png` matches direct children only. Files at:

- `knowledge-base/product/design/billing/screenshots/05-foo.png` — unignored ✓
- `knowledge-base/product/design/billing/screenshots/upgrade-modal-at-capacity/05-foo.png` — still ignored ✗

The `*.png` does not traverse the additional `upgrade-modal-at-capacity/` segment.

## Solution

Place screenshots as direct children of `screenshots/` with a feature-prefixed kebab-case name continuing whatever numbering already exists in that folder:

```text
knowledge-base/product/design/billing/screenshots/
  01-settings-billing-active-subscriber.png    (existing)
  02-settings-billing-cancelling-state.png     (existing)
  03-settings-billing-no-subscription.png      (existing)
  04-retention-modal.png                       (existing)
  05-upgrade-modal-at-capacity-solo.png        (new)
  06-upgrade-modal-at-capacity-isolated.png    (new)
  07-upgrade-modal-at-capacity-startup.png     (new)
```

This matches every existing pattern under `knowledge-base/product/design/*/screenshots/` (verified across `byok-cost-tracking`, `command-center`, `inbox`, `kb-viewer`, `notifications`, `onboarding`, `settings`, etc. — all flat).

## Prevention

When the plan or agent prompt prescribes screenshot output paths for design work:

1. The path MUST be `knowledge-base/product/design/<domain>/screenshots/NN-feature-name.png` — direct child of `screenshots/`.
2. Numbering continues from existing `NN-` prefixes in that folder; do NOT restart at `01-` if siblings exist.
3. If a feature warrants grouping, prefix the filename (e.g. `05-upgrade-modal-at-capacity-solo.png`) — do NOT create a subfolder.

This rule does not need an AGENTS.md entry — `ux-design-lead.md` already owns screenshot path conventions and was updated in the same PR. The cost of widening `.gitignore` to `**/screenshots/**/*.png` is low but unnecessary as long as the convention holds.

## Detection

Quick check after any screenshot creation under `knowledge-base/product/design/`:

```bash
git check-ignore -v <path-to-screenshot.png>
# Empty output = trackable. Non-empty = ignored.
```

## Related

- `.gitignore` line 57
- `plugins/soleur/agents/product/design/ux-design-lead.md` — screenshot export instructions
- PR #2645 — caught and fixed inline before commit
- Issue #2636 — the recreation work that surfaced this

## Session Errors (PR #2645)

- **Plan file written to bare repo path instead of worktree** — Recovery: subagent moved file. Prevention: soleur:plan worktree-path detection (existing).
- **Adapter drift detected during planning** — Recovery: refresh via `--auto`. Prevention: covered by `cq-pencil-mcp-silent-drop-diagnosis-checklist`.
- **Plan prescribed nested screenshot subfolder** — Recovery: flattened to feature-prefixed siblings. Prevention: this learning + ux-design-lead route-to-definition edit.
- **Plan factual claims went stale by Phase 1** (`#2636 state CLOSED`, "canonical path DOES NOT EXIST") — Recovery: corrected plan inline after code-quality reviewer flag. Prevention: `hr-before-asserting-github-issue-status` (existing).
- **Stray nodeID-named PNG exports left at top of `screenshots/`** by `ux-design-lead`'s `export_nodes` call. Recovery: `rm` before `git add`. Prevention: minor — agent could sweep raw nodeID files post-rename.
