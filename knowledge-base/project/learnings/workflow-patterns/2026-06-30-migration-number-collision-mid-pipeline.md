# Learning: migration-number collisions can land MID-PIPELINE, not just at work-start

## Problem

`/work`'s "Pre-apply collision check" greps `origin/main` for a colliding
migration prefix at **work-start**. That is necessary but not sufficient: the
collision window stays open through the entire `/ship` phase (often 30–90 min,
longer under runner contention). During that window a sibling PR can merge a
migration sharing your prefix, and `/ship` Phase 7's `OPEN BEHIND` auto-sync
loop will `git merge origin/main` it into your branch **silently** (no textual
conflict — the two migrations have different filenames) and push it straight to
CI, where the migration drift/shape gate fails ~16 min later.

Concretely (PR #5760, this session): work-start confirmed `114` was free. During
ship, a #5739-sibling merged `114_disk_io_top_wal_statements.sql` to main while
my branch carried `114_prune_cron_job_run_details.sql`. Six `OPEN BEHIND`
auto-syncs pulled it in; the collision surfaced only when a required check failed
on the merged SHA. Recovery cost a renumber + re-verify + extra CI cycles.

This is the same class as PR #4225 (sibling landed 10h after apply) but the
trigger is different: #4225 was apply-then-sibling; this is
sibling-during-ship-sync. A fast-moving-main burst (a fleet of parallel
one-shot sessions) makes it much more likely — main moved every ~3–5 min while
my CI took ~16 min.

## Solution

- Treat the pre-apply collision check as covering a **window**, not a moment.
  After ANY ship-time `git merge origin/main` whose output lists
  `apps/web-platform/supabase/migrations/`, re-run the prefix check
  (`git ls-tree origin/main -- <migrations-dir> | grep -oE '^[0-9]{3}'`) and
  assert no DIFFERENT filename shares your migration's prefix.
- On collision, **renumber-during-ship**: `git mv` both the up and `.down.sql`
  to the next free prefix, then update EVERY in-repo reference in one edit cycle
  — migration file headers (up + down), code comments (`migration 114` →
  `115`), and the plan / tasks / session-state / learning. A `git grep -nE
  '114_<slug>|migration[ -]114'` over your changed files catches them; do NOT
  touch the sibling's `114_*` references.
- `git mv` stages the rename with **zero content delta**, so a follow-up
  `git add` of the renamed files is required to capture the header/body edits —
  and a `git add` that lists the now-deleted old `114_*` pathspec aborts and
  silently stages nothing. Stage only existing paths.
- Admin-merge is NOT an escape here: a migration needs the release pipeline's
  `migrate` + `deploy` to run, and `gh pr merge --admin` skips the deploy via
  the `await-ci` gate (see `2026-06-29-admin-merge-skips-deploy-via-await-ci-gate`).
  A real CI-green auto-merge on a synced SHA during a main lull is the only path.

## Key Insight

A collision check at one point in time is a snapshot of a moving target. Any
gate that asserts "my number is unique on main" must be re-evaluated at every
point the branch re-merges main — most importantly the ship-time BEHIND
auto-sync, which is invisible operator-wise and pushes the collision to CI by
default. Routed into `work/SKILL.md`'s Pre-apply collision check.

## Tags
category: workflow-patterns
module: ship-work-migration-collision
issue: 5760
related: 4225, 5739
