# Compound learnings — batch-2 MUT_SKIP port (#11720)

Sharable, non-obvious mechanics discovered during this port:

1. **Phantom heredoc spans hide floors.** A literal `<<-TAG` anywhere in a test file's
   *scanned* text — inside awk patterns, grep counts, python strings in single-quoted
   mutation programs, even comments — opens a heredoc span in
   `guard-vacuity-floor.test.sh`'s `heredoc_lines_of` that swallows every later line
   until a bare `TAG` line. A floor `if` inside the span is invisible to
   `floor_lines_of`: the file is simply "not floor-bearing". Four batch-2 files were
   never floor-bearing for exactly this reason. Evasion: `<<[-]SQL` in awk/grep/comments
   (a char class can't match the scanner's `<<-?[[:space:]]*['"]?[A-Za-z_]` pattern),
   `<<\x2dSQL` inside python strings (renders `<<-SQL` at runtime). Real `<<PY` heredocs
   are fine — they close at their `PY` line.

2. **`build_mutant` needs a standalone `fi`.** One-line `if …; fi` floor/ledger blocks
   can't be sliced — always write floor `if`s multi-line with `fi` at the same indent.

3. **The donor's `[ -n "${MUT_SKIP:-}" ] && _floor=$PRESENCE_ROWS` rebind is
   unconstructible** — the backward slice stops at the non-assignment. The constructible
   form is the pure-assignment window: `_eff=${MUT_SKIP:+0}` / `_eff=${_eff:-$MUT_ROWS}` /
   `_floor=$((PRESENCE_ROWS + _eff))` / `_ran=$((pass + fail))`, then the `if`.

4. **Backticks inside mutation labels execute.** `mutate_red "... `count = 0` ..."` runs
   `count = 0` as a command (shellcheck SC2283 + stray "paused: command not found" noise).

5. **PRESENCE_ROWS/MUT_ROWS are the suite's own `ok()`/`no()` call-site counts** — count
   them after edits (`grep -cE '^\s+mutate_(red|green|floor_red) "'` for MUT_ROWS); a
   stale PRESENCE_ROWS makes `mutate_floor_red` SURVIVE (the real signal that a constant
   drifted).

6. **param() counts value-matching lines, not attr occurrences** — a same-attr/
   different-value decoy doesn't move the count, and attr-name cardinality can't apply
   where blocks legitimately nest `name` (e.g. `variable { name = ... }`). Documented
   in the helper; `paused`-occurrence rows cover the highest-risk attr.

7. **Emitter-rename mutations can't grade RED** — derivation is FATAL-on-empty (rc 2,
   instrument class). That IS the enforcement; don't write mutation rows expecting rc 1
   against emitter literals.
