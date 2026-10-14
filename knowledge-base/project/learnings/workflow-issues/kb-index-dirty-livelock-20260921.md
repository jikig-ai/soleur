---
title: INDEX.md is a mandatory-diff file that GitHub cannot merge — KB PRs livelock under main churn
date: 2026-09-21
category: engineering
tags: [kb-index, merge-driver, github-merge, ci, ship, admin-merge]
symptoms: [KB-touching PR repeatedly reports CONFLICTING/DIRTY despite clean local merge-tree, each origin/main sync restarts ~70min of CI and races the next main KB landing, dropping INDEX.md from the diff turns test-scripts red on AC17]
module: Ship workflow
synced_to: []
component: tooling
problem_type: workflow_issue
resolution_type: workaround
root_cause: platform limitation + mandatory generated file
severity: medium
---

# INDEX.md DIRTY livelock on knowledge-base PRs

## Problem

A PR that adds or renames a `knowledge-base/` file must carry a regenerated
`knowledge-base/INDEX.md` — AC17 in
`plugins/soleur/test/kb-index-merge-driver.test.sh` fails CI when the
committed index does not match a fresh generation. But `INDEX.md` merges
cleanly only via the repo's custom merge driver
(`scripts/merge-kb-index.sh`), which is configured in local `.git/config` and
**GitHub never runs server-side**. GitHub therefore does a plain textual
three-way merge on `INDEX.md`; any main-side KB landing during the PR's CI
window that touches the same regions — including the `Total files:` counter
line, when the deltas differ — recomputes the PR as `CONFLICTING/DIRTY`.
Syncing `origin/main` fixes it locally (the driver resolves the merge) but
the push restarts CI, which races the next KB landing. On a busy evening this
livelocked a docs-only PR through three DIRTY cycles (#8432).

## What does NOT work

- **Dropping `INDEX.md` from the diff.** AC17 compares committed index
  against fresh generation and fails (`test-scripts` shard goes red). The
  entry is mandatory whenever the diff adds/removes a KB file.
- **`--admin` merging a DIRTY PR.** GitHub's merge endpoint refuses outright
  ("the merge commit cannot be cleanly created") — admin bypasses required
  checks and the up-to-date rule, never an unmergeable computation.
- **Auto-merge alone.** It never fires while `BEHIND` (up-to-date
  requirement) or `DIRTY`; nothing updates the branch for you.

## What works

> **Superseded 2026-09-22 (#8500):** the admin-merge step below must go through `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` steps 2-5 (`plugins/soleur/scripts/admin-merge-ready.sh`, then `--match-head-commit`), never a bare `gh pr merge --admin` after an eyeballed "all green".

1. Keep the regenerated `INDEX.md` in the diff.
2. Sync `origin/main` (the local merge driver resolves `INDEX.md`), push.
3. Watch checks on the new head. When all required checks settle green:
   - `MERGEABLE` → auto-merge fires on its own.
   - `MERGEABLE` + `BEHIND` → `gh pr merge <n> --admin --squash` (the
     documented hatch: admin tolerates behind, and a BEHIND-only state means
     no conflict was computed).
   - `CONFLICTING/DIRTY` → back to step 2; each cycle's success probability
     is P(no KB-touching main landing during the CI window).

## Root cause

Two facts combine: (a) a generated, high-churn file is a required part of the
diff surface, and (b) its only conflict-free merge path exists in local git
config, invisible to GitHub's merge computation. Non-KB landings only produce
`BEHIND`, which `--admin` tolerates; KB landings produce `DIRTY`, which
nothing tolerates.

## Longer-term candidates (not done)

- Teach `INDEX.md` a `.gitattributes` merge mode GitHub *does* honor
  (`union` corrupts the `Total files` line — emits both values — so this
  needs a real design, not a one-line change).
- A merge queue would serialize PRs but still ejects on conflict — does not
  fix this.
- Route the counter line out of the conflicting region (e.g. drop
  `Total files:` or move stats to a separate generated file) so textual
  merges converge on the common case of disjoint entry additions.

## Evidence

- PR #8432 (Convergence CCLA docs): three DIRTY cycles 2026-09-20, each after
  a main-side KB merge (`#8375`, `#8428`, `#8405` era commits); AC17 failure
  on `test-scripts (1/3)` when `INDEX.md` was dropped; merged via
  `--admin --squash` once a green `MERGEABLE` window appeared.
