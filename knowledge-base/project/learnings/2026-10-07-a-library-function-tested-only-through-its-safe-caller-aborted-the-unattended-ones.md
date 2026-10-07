# Learning: a shared library function tested only through its one safe caller aborted the unattended callers (#9677)

## Problem

Review of the #9677 drain found one P1 and a cluster of P2s that every green suite had missed:

- `tc_drain_quarantine` gained `kb="$(du -sk -- "$e" | cut -f1)"`. The session sweep calls the function with `|| true`, which turns errexit off for the whole call, so every sweep-driven test passed. `tmpfs-guard.sh` and `soleur-tmp-purge.sh` call it bare under `set -euo pipefail`: `du` exits 1 on an unreadable subtree, pipefail fails the assignment, and the guard died on every 5-minute run (heartbeat never written, later entries never drained).
- Env numbers feeding `$(( ))` were used raw. `08`/`09` are octal arithmetic errors, so `if (( sttl < qfloor ))` silently read false and the 1440-minute floor was skipped (TTL became 8 minutes); `5s` aborted the sweep; `BASH_SOURCE[$(cmd)]` ran a command.
- The deadline rebase made a previously unreachable path reachable by default: a tmpfs direct delete runs a per-process liveness walk, measured at 138 s for one candidate on a loaded host, inside the flock.
- My own review fix for that (rebuild the map every 5 s) could overrun the timebox by a whole build per window; the simplicity pass caught it.
- The tests pinned content and helpers, not wiring: deleting the wrapper's `space_begin`, the dispatch arm, the removal-count assignment, or the action-time liveness check left the suites green.

## Solution

`|| true` on the capture; one `_sweep_uint` normaliser (digits only, `10#`) for every sweep env number; the tmpfs action-time check consults the map `tc_reap_decide` just refreshed (the unattended guard keeps the full walk); tests added for each: a bare-under-`set -euo pipefail` call with a failing `du` shim, an argument-logging seam that pins the values the callee RECEIVES (floor, cap, TTL, box), source assertions on the comment-stripped wrapper, and a fixture where a handle appears between the two liveness checks. A 22-row sandbox mutation battery then reddened every new guard.

## Key Insight

A library function has as many contracts as it has caller contexts. Errexit state, stdin, env and working directory differ per caller, and a new line that is safe in the context the author tests is a crash in the one nobody drives. When a PR edits a shared function, `git grep` its callers and give each distinct context one case. For env-fed arithmetic, normalise with a digit check plus `10#` and pin the value the callee receives, not the variable the caller read.

## Session Errors

- **Ended turns with "I will ..." while review seats were still running, then stopped after the review marker in pipeline mode.** Recovery: named a BLOCKED stop while seats ran; continued to compound when asked "why did you stop?". Prevention: review's pipeline-mode text already says the marker is not a turn boundary; after emitting it, invoke the next skill in the same response.
- **`ps -eo args | awk '... lead-mut-battery'` was blocked by the self-match guard, and `sleep N; cat` was blocked.** Recovery: relied on the background-task completion notification. Prevention: already hook-enforced (pkill-self-match-guard, sleep block); wait with `run_in_background` or an `until` loop on an rc file.
- **A new test helper's `grep ... | head` aborted the whole suite silently under the suite's own `set -euo pipefail`** when a mutation produced no match (M13: rc 1, no FAIL line). Recovery: `|| true` so a missing line is a named T4 failure. Prevention: in a `set -e` suite, any helper whose pipeline can legitimately match nothing needs `|| true`, and a mutation row that exits non-zero without naming its assertion is UNRESOLVED, not killed.
- **T9's first run was a false FAIL: the call counter lived in a `$(...)` subshell (`tc_reap_decide` runs inside one).** Recovery: count in a file. Prevention: a seam that counts calls must not keep state in a shell variable when the SUT calls it inside command substitution.
- **Mutation scorer expected the wrong token for M20 (`LIVE` instead of `T9`) and reported a kill as "not named".** Recovery: read the named FAIL by hand. Prevention: derive the expected assertion id from the test added for that row, not from the mutant's name.
- **The sandbox copy (`git ls-files | cp --parents`) skipped a directory (`.grok/plugins/soleur`) and had no `.git`, which reddens any guard that derives its corpus from git.** Recovery: `git init && git add -A` inside the sandbox before the control run. Prevention: already covered by the review skill's "SUBTREE sandbox" bullet.
- **`core.hooksPath` is `/dev/null` and `lefthook` is not installed here, so the `c4-model-regenerate` pre-commit step never ran and `model.likec4.json` was missing from the commit that edited `model.c4`.** Recovery: ran `scripts/regenerate-c4-model.sh` and committed the artifact; the CI freshness test backstops a skipped hook. Prevention: after editing any `.c4` file, run the regenerate script by hand when git hooks are disabled.
- **My own fix for a latency finding introduced a new overrun (`tc_inuse_map_refresh 5`).** Recovery: dropped it for the map `tc_reap_decide` already refreshed. Prevention: grade a fix commit as its own change (review skill's first bullet); ask "what does this cost per candidate" before adding a rebuild inside a loop.

- **Routed the insight as a bullet into `review/SKILL.md`, which `lint-skill-body-budget.py --base <merge-base>` rejected (the file sat 3 bytes under its 477,000-byte ceiling).** Recovery: reverted the bullet; this learning is the record, findable by `kb-search`. Prevention: before routing a bullet into a skill body, run `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` and read the headroom; a skill at its ceiling needs a `references/` extraction in a dedicated PR, not a side edit.

## Tags

category: logic-errors
module: git-worktree, tmp-classify
