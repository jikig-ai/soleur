---
date: 2026-10-13
area: workflow-patterns
issue: 10095
pr: 10226
---

# Content-drift repair: recorded commands must be replayable, and bare `git worktree add` skips dep-install

## What happened

Issue #10095 was the first live execution of the learning's §Content-drift
class-C procedure (targeted FK drop/re-add + comment replay + ledger CAS on
dev). The repair succeeded in one `--single-transaction` unit; the findings
were all in the *recorded* artifacts, not the write.

## Session errors (each with Prevention)

1. **`test-all --affected` refused with `apps/web-platform/node_modules`
   absent.** The worktree was created with a bare `git worktree add` (the
   one-shot Step 0b path normally routes through the worktree-manager, which
   installs deps; a manually-created worktree does not).
   **Prevention:** after any manual `git worktree add`, run `npm ci
   --ignore-scripts --prefix apps/web-platform` + root `npm ci`/`bun install`
   *before* queuing the affected gate — the refusal costs a full lock-queue
   cycle (60+ min under contention) to discover.

2. **The plan's recorded Phase-1 fenced block was not replayable** — `\copy`
   line had an unbalanced `'"'"'` sequence and `$BK` was never exported into
   the inner `bash -c` (which runs `set -u` → `BK: unbound variable`). The
   executed command inlined the literal path, so the work succeeded while the
   record was wrong.
   **Prevention:** when a plan embeds a nested-quoting snippet, stub-verify the
   bytes actually produced (a 20-line `bash` stub with `psql() { echo "$@"; }`
   catches this class for free), or record the as-executed form. For
   `bash -c '…'` inner scripts: exported vars expand at *inner* level; the
   `'\''$VAR/path'\''` idiom emits literal `'` bytes inside the inner `-c "…"`
   double-quoted arg and lets the inner shell expand — verified empirically.

3. **PL/pgSQL `END` without `;` executed fine** (the DO block committed — sha
   updated) but repo convention is `END;` and the recorded form should be
   canonical.
   **Prevention:** record the canonical form even when Postgres tolerates the
   loose one — reviewers will (correctly) flag the non-idiomatic record.

4. **UTC conversion slip**: `2026-05-19 17:20:36 +0200` recorded as `17:20Z`
   (should be `15:20Z`) in a table labeled "all timestamps UTC".
   **Prevention:** always emit `--date-iso`/`%ci` and convert before writing;
   a `git show -s --format=%cI` (strict ISO, always `+00:00`-normalized via
   `TZ=UTC0`) avoids the mental-arithmetic class entirely.

5. **Fix-round seat consolidation under-counted the tally** — mapped 4 seats
   but spawned 1 consolidated check, then corrected. 
   **Prevention:** spawn the mapped seats (or don't tally them); a
   consolidated seat is a coverage reduction, not a rename.

6. **Third occurrence of the `test-all-weight-drift` C8 sibling-refusal flake**
   (`rc=4` under contended full-gate, green in isolation) — filed as #10209;
   now demonstrably systematic, not anomalous.

## Deeper notes for the next class-C repair

- The mutex's `STATE_DIR` keys on `local-$PPID` → acquire+release must be in
  ONE `doppler run` invocation; wrap with `trap release EXIT`.
- `pg_depend` always shows 4 `deptype='i'` internal RI-trigger dependents on a
  FK — they auto-cascade on `DROP CONSTRAINT`; the gate is on *non-internal*
  dependents, and the census query must say so.
- The `SET LOCAL lock_timeout=30s` bound matters: the re-ADD takes SHARE ROW
  EXCLUSIVE on `public.users` (hot table) to create/drop RI triggers.
- `'\''` nested quoting inside `doppler run … bash -c '…'`: test with a stub;
  the visually-plausible `'"'"'"$BK/x'"'"'` form yields an unbalanced inner
  arg (literal `"$BK/…"` + dangling `"`).
