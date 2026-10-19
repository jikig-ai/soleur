# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-10-12-fix-plugin-version-checkout-identity-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=1 (batched ruling 2026-10-13 on ten plan-author rows; overturned two: the anchor drops the marketplace.json check, a NUL-spliced HEAD is unknown). Technical-ruling gate: PASS (26 rows).

### Errors

None (the test-design reviewer arrived late and was folded into the plan).

### Decisions

- Layout-anchored lookup (`/plugins/soleur`, `<top>/.git`, `plugin.json`), not a free walk-up.
- A `stat` size gate runs before every plain-file read; a NUL-spliced HEAD is unknown.
- The compare treats a checkout like a commit install; one stable `latest-release.checkout` cache; legal wording is clarification-only.
- Update guidance is split: bare root (fetch then sync), normal clone (git pull), `--plugin-dir`.
- Phase 0.0 premise probe: the hook root is the folder copy (confirmed 2026-10-13, see measurements.md).

### Components Invoked

soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto (three spawns incl. the batched ruling), soleur:legal:clo, review agents.

## Work Phase

- Side finding fixed in this PR: `worktree-manager.sh sync-bare-files` ran `comm` without `LC_ALL=C`, which deleted tracked dotfiles (including `.claude-plugin/marketplace.json`) from the bare root under en_US.UTF-8 and made the in-place plugin fail to load. One-line fix plus a locale regression row.
- Commits: sync fix and measurements; resolver, hook and both suites; commands, docs, C4, ADR addendum, legal clarifications.
