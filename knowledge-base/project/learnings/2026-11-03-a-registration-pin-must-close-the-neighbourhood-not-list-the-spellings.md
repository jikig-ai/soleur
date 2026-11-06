# Learning: a registration pin must close the neighbourhood, not list the spellings

## Problem

PR #11998 (epic #9927 item 10) registered the sole-copy LUKS Guard 1 suite in the required `test-scripts` leg and added a "G2f" pin so the `run_suite` line could not be silently dropped. The first version of the pin recognised exactly one way to neuter the line: an indented one-line `if ...; then` wrapper. Eight of nine review seats converged on the same gap. A heredoc, a column-0 `if`, a split `if`/`then`, `while false`, a never-called function, an early `return`/`exit`, a `&& \` continuation, a redefined `run_suite()` or `want_scripts()` and a label-specific early return inside `run_suite` all left the pin green while Guard 1 never ran. The author's own mutation matrix had one dead-conditional row, so it measured the spelling it had imagined.

## Solution

Close the class by position rather than by spelling. The registration's previous and next CODE lines must themselves be plain `run_suite` registrations (comments and blanks skipped), so nothing can sit directly around it. Add single-definition checks for `run_suite()`, `want_scripts()` and `_shard_selects()`, forbid any non-comment mention of the suite name outside the registration line, and pin the parsed `ci.yml` wiring (the `test-scripts` runner step has no `continue-on-error` and no step `if:`; the `test` aggregator lists it in `needs:` and in its entries array). Each check gets a mutation row asserting the right failure reason, plus one row that isolates it from the others.

## Key Insight

A guard's assembly should be the property's domain, not the spelling the author was thinking about. When a pin protects "this line executes", ask what the set of ways a line can fail to execute is, then pick a predicate (adjacency to peers) that is closed over that set instead of listing members of it. The same review also showed that a second line of defence only counts if an independent shard runs it: the pin lives in `test-bun`, the registration in `test-scripts`, and a diff to `scripts/test-all.sh` is a full-battery trigger so the pin cannot be selected away.

## Session Errors

1. **A Python `str.replace` with an empty slice corrupted ADR-282 by 227,678 lines.** The slice end was `s.index("**CODEOWNERS.**")`, which matched an earlier occurrence than the slice start, so the slice was empty and `str.replace("", new)` inserted the new text between every character. Recovery: `git restore --source=HEAD --staged --worktree`, redo with indexes searched from the start offset. **Prevention:** compute `end = s.index(marker, start)` and `assert end > start` before any slice-based replace; read `git diff --stat` after any scripted multi-edit.
2. **The agent invented an operator gate for agent-owned pipeline steps** ("Paused: waiting for your go to ... mark PR #11998 ready"). The stop hook's `Paused:` escape hatch became a place to park work. **Prevention:** fixed in PR #12010 (hook wording and work/ship sharp edges); not duplicated here.
3. **The resume brief named the wrong Guard 1 file.** Caught because the CTO agent and the ADR both named the right one; the brief's sentence had been inherited, not measured. **Prevention:** re-derive every identifier a brief or ruling names with `ls`/`git grep` before it enters a plan.
4. **`LIVE_CHECKS` was miscounted (12 vs 9) and the stray-mention check matched only the long label.** Both caught by the first test run; the mutation row for a label-specific early return stayed green until the match was widened to the short name. **Prevention:** assert the exact check count against a hand count of the function's `checks++` sites, and write the label-shortcut mutation in the form an attacker would use (the short name).
5. **A `--print-selection` run and the affected gate queued behind a sibling worktree's `test-all.sh`.** Treated as a queue, not a hang; stopped with `proc.sh kill_mine` and relied on CI as the full-battery gate (ADR-183). **Prevention:** none needed; the runner's contention banners and `--capacity` already name this.

## Tags
category: workflow-patterns
module: ci-gates, terraform-target-parity, scripts/test-all.sh
