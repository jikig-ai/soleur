# Decision Challenges — feat-one-shot-9091-archive-stamp-format

## 2026-09-28 — plan widened the fix to a second stamp site (scope extension)

- **Operator's stated direction (issue #9091):** "~1 line fix" — align the spec-archive stamp
  (`worktree-manager.sh:3333`) to `%Y%m%d-%H%M%S`, plus a stamp-format test assertion.
- **Plan's decision:** also align `archive_kb_files`'s `ts=` (`worktree-manager.sh:2484`),
  which mints the same dashed names into `plans/archive` and `brainstorms/archive` on every
  reap — the identical property violation, one more one-line edit.
- **Why not silently scope-only:** the issue's stated property (prefix uniformity, C-locale
  sort order vs. compact siblings) holds in all three archive namespaces; a spec-only fix
  leaves two namespaces still producing dashed names.
- **Class:** user-challenge (scope beyond literal ask, recorded for ship's PR-body render).
