# Knowledge-Base Project Directory Migration

**Date:** 2026-03-20
**Status:** Decided

## What We're Building

Complete the partially-started migration of workflow artifact directories (`brainstorms/`, `specs/`, `learnings/`, `plans/`) from `knowledge-base/` top-level into `knowledge-base/project/`. Add guardrails to prevent path drift in the future.

## Why This Approach

The migration to `knowledge-base/project/` was started (worktree-manager.sh updated to use new paths) but never completed. This left:

- 13+ skills writing to old top-level paths
- `worktree-manager.sh` targeting empty `project/` subdirectories
- AGENTS.md referencing a non-existent `knowledge-base/project/constitution.md`
- 868+ files in old locations, ~0 in new locations

The split creates confusion about canonical paths and causes worktree-manager archival logic to silently fail.

## Key Decisions

1. **Move only the 4 workflow dirs** — `brainstorms/`, `specs/`, `learnings/`, `plans/` go into `project/`. Domain dirs (`audits/`, `community/`, `design/`, `marketing/`, `ops/`, `sales/`) and `overview/` stay at top level.
2. **Scripted bulk migration** — Single idempotent script: `git mv` + `sed` path updates + verification grep. Atomic, one PR.
3. **Add CI guardrail** — grep-based check that fails if any skill/agent/script references `knowledge-base/(brainstorms|specs|learnings|plans)/` without the `project/` prefix.
4. **Fix AGENTS.md** — Update broken `knowledge-base/project/constitution.md` reference to `knowledge-base/overview/constitution.md`.

## Target Structure

```
knowledge-base/
  project/
    brainstorms/   (moved from knowledge-base/project/brainstorms/)
    specs/         (moved from knowledge-base/project/specs/)
    learnings/     (moved from knowledge-base/project/learnings/)
    plans/         (moved from knowledge-base/project/plans/)
  audits/          (stays)
  community/       (stays)
  design/          (stays)
  marketing/       (stays)
  ops/             (stays)
  overview/        (stays)
  sales/           (stays)
```

## Blast Radius

- ~870 files to move via `git mv`
- ~1,181 path references to update across ~60 files
- Key files: 13 SKILL.md files, worktree-manager.sh, archive-kb.sh, learnings-researcher.md, sync.md, constitution.md, README.md, settings.local.json, AGENTS.md
- Content files (plans, brainstorms, specs) that reference their own paths internally

## Open Questions

- Should the migration script update self-referencing paths inside archived content files, or only update skill/agent/script/config references?

## Prevention

- CI lint check grepping for old-path patterns in `plugins/`, `scripts/`, `AGENTS.md`, `CLAUDE.md`
- Update constitution.md with canonical path convention
