# Learning: a test that scans the live migrations dir + assumes "only the synthetic file is unmerged" breaks on every migration-adding PR

## Problem

`apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts` (the #4241
unmerged-apply gate test) staged its fixture by `cpSync`-ing the **entire real**
`supabase/migrations/` dir into a temp dir, then dropping one synthetic
`zzz_unmerged_gate_<hex>.sql` (absent from origin/main) into the copy. Every
assertion relied on the invariant "the synthetic file is the ONLY unmerged
migration in the staging dir."

That invariant is false the moment the branch under test adds its own migration.
On the #4906 branch, the new (unmerged) `100_append_kb_sync_row_for_user_rpc.sql`
was copied into the staging dir alongside the synthetic. The SUT's gate
(`run-migrations.sh:208`) `exit 1`s on the **first** unmerged `*.sql` in glob
(sort) order — and `100_*` sorts before `zzz_*`. So:

- `ALLOW_UNMERGED_DEV_APPLY unset` test failed: the gate fired on `100_*` and
  exited before reaching the synthetic, so `expect(stdout).toMatch(SYNTHETIC_FILE)`
  never matched.
- After a first fix attempt (prune unmerged files so the synthetic sorts last),
  the test then **timed out** at the 16s `testTimeout`: the SUT spawns one
  `git ls-tree origin/main` subprocess per `*.sql`, so a ~130-file staging dir =
  ~130 sequential subprocess spawns per `runScript` × 3 runs — right at the
  timeout boundary, flaky under parallel-suite load on a throttled machine.

This is a **recurring** fragility: any feature branch that adds a migration would
trip it, and the timeout would flake intermittently regardless.

## Solution

Build a **minimal** staging dir — exactly the files the assertions reference —
instead of copying the whole live tree:

```ts
// one known-merged file (positive control) + the synthetic unmerged fixture
cpSync(join(REAL_MIGRATIONS_DIR, KNOWN_MERGED_FILE), join(tempMigrationsDir, KNOWN_MERGED_FILE));
writeFileSync(join(tempMigrationsDir, SYNTHETIC_FILE), "-- synthetic …\nSELECT 1;\n");
```

This reproduces the gate behavior exactly because the gate (`run-migrations.sh:208`)
runs **before** the already-applied skip (`:258`), so the psql stub cannot shadow
it, and a 2-file dir exercises the same code path with ~2 git spawns instead of
~130. It is also robust to any in-PR migration: the staging set no longer mirrors
the working tree's unmerged set, so it can't false-fire on the branch's own
migration. (#4957 isolation — temp dir, never the real tree — is preserved.)

A named `SLOW_SUBPROCESS_TIMEOUT_MS = 45_000` const on the three tests is
belt-and-braces for the remaining bash+psql+git subprocess cost under contention;
the minimal fixture is the real fix.

## Key Insight

When a test stages a fixture by copying a **live, growing directory** and then
asserts on a property that holds only when that directory contains exactly the
test's own synthetic entry ("the only X is mine"), the assertion is coupled to
the working tree's evolving contents and will break the next time the real
directory legitimately grows. Stage a **minimal, explicit** fixture set
(known-good + synthetic) so the test owns 100% of what it scans. Bonus: if the
SUT spawns a subprocess per file in that dir, a whole-dir copy also makes the
test O(files) slow — another reason to stage only what you assert on.

Generalizes beyond migrations: any gate/linter/scanner test that `cpSync`s a real
source tree (workflows dir, rules dir, fixtures dir) and asserts "exactly one
flagged item" inherits the same fragility.

## Session Errors

1. **Whole-dir-copy migration-gate test broke on the new migration.** Recovery:
   rewrote to a minimal `{known-merged, synthetic}` fixture. Prevention: stage
   minimal explicit fixtures for tests that scan a live, growing directory; never
   assume "the only unmerged/flagged file is my synthetic one" against a real-tree
   copy.
2. **Same test timed out (16s) under parallel load** — ~130 `git ls-tree` spawns
   per run. Recovery: minimal fixture (2 spawns) + `SLOW_SUBPROCESS_TIMEOUT_MS`
   const. Prevention: when a SUT spawns a subprocess per file in the scanned dir,
   minimize the fixture dir; don't rely on a raised timeout to paper over O(files)
   subprocess cost.
3. **Bash CWD non-persistence** — a relative `cd apps/web-platform/supabase/migrations`
   failed once because the Bash tool does not persist CWD across calls. Recovery:
   absolute paths / single `cd … && cmd`. Prevention: already covered by AGENTS +
   existing learnings; use absolute paths or chain `cd` in one call.
4. **Env-only full-suite flakes unrelated to the diff** — `signature-verify.test.ts`
   timeout (run-varying) and `plugins/soleur/changelog-data.test.ts` live-GitHub-API
   "operation was aborted". Both pass in CI-equivalent isolation; green on main.
   Prevention: per the work-skill env-false-positive caveat, re-run a full-suite
   failure file in isolation before treating it as a regression.
5. **`perl -0pi` syntax error** trying to delete a `//`-comment line in the timeout
   refactor (the `//` parsed as a regex). Recovery: simpler global perl + manual
   Edit. Prevention: prefer the Edit tool for comment-bearing multi-line deletions.

## Tags
category: best-practices
module: apps/web-platform/test/scripts
issue: 4906
