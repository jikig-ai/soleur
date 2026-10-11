# Learning: a presence assertion does not pin the slot, and a validator glob was narrower than the header describing it

## Problem
PR #9979 (#7258 step A) extended the web-host zot consumer probe to a comma-separated repository list. Two rounds of seats and two self-run mutation batteries (23 + 17 rows, all killed) still left six gaps that only the targeted fix-round seats found:

- The repository-name glob refused leading `.`/`-` but not a dot segment (`a/./b`, `a/.`) or a component edged with `_`/`-`. An HTTP client normalises `a/./b` to `a/b`, so the probe would check a different repository than the list names. The header said "no leading or trailing separator", which was false for those inputs.
- T7 asserted the joined list was PRESENT on the SSH printf line, not that it sat in the right argument slot. Swapping `'${local.registry_endpoint}' '${local.zot_probe_repo}'` (or the two format names) left the suite green and would have written `ZOT_ENDPOINT=<list>`.
- The pin extractor matched only `[A-Z]*REF=`; a third pin named `ZOT_REF2`, `ZIREF2` or `ZOT_REF`, or a literal-path `docker pull`, passed. `ALLOWED_IMAGES` was checked by line count only, so a commented, duplicated or lookalike entry passed.
- The "garbage marker" row used a 12-character fixture, so the length guard returned before the non-numeric arm; deleting that arm stayed green.
- The T15 default-path check took `head -1` over the whole file, so a comment could satisfy it.
- The runbook's fault query (`--grep 'repo=<path>'`) also matches the healthy marker row.

## Solution
- Refuse any path component that starts or ends with `. _ -` (`*/[._-]*|[._-]*|*[._-]|*[._-]/*`), add rows for each edge, and require the invalid-name FATAL message so an unrelated early exit cannot satisfy the row.
- Pin the whole printf format (names in order) plus the argument slots as one fragment, in both the SSH writer and the envwrite script.
- Widen the pin extractor to any `*REF*` name and a literal `docker pull "$VAR/path`, assert the pin COUNT, and require `ALLOWED_IMAGES` (comments stripped) to equal exactly {the `var.image_name` repo, the probed bootstrap repo}.
- Use short garbage (`abc`, `12ab`, `1e5`, `-5`) that reaches the arm under test; anchor `def_of` on the real `local m=` assignment.
- Query faults by their own tokens (`SUPPRESS ping`, `HARD FAILURE`), never by a substring a healthy row also carries.

## Key Insight
A guard is only as strong as the weakest word in the sentence that describes it. Each gap here was a predicate narrower than its prose: "present" for "in the right slot", "no leading or trailing separator" for "no leading dot", "every pin" for `[A-Z]*REF=`. A self-run mutation battery's axes are the lines of the SUT, so it cannot find a row whose fixture short-circuits before the arm it names, or a presence check that a swap leaves intact. Cheap tests: for any wire, name the edit that swaps two adjacent slots; for any fixture, delete the arm it claims to test and see if the suite notices; for any extractor, add a pin with a differently shaped name. A mutation survivor can also be the harness itself: the first-round survivor D6 was the extractor's name class, fixed and re-driven in the same session.

## Session Errors
- **`\\${...}` in an assert string -> "bad substitution", row silently never ran** — Recovery: helper functions and `printf`-built literals — Prevention: build assert fragments with `printf` into variables and call helper functions from `assert`; surface by mutating the asserted line (M1).
- **`${zot_probe_repo}` expanded under `set -u` in a T7 row** — Recovery: `printf '%s'` into `CI_LINE` — Prevention: never inline a template `${...}` literal in a double-quoted assert string.
- **`def_of` sed quoting; SC2034 on a moved variable; `grep -q` pipe guard hit** — Recovery: `[$]{...}` class, variable moved into a function, `grep -cF >/dev/null` — Prevention: shellcheck and `grep-q-pipe-guard.test.sh` before commit (both fired as designed).
- **`guard-vacuity-floor` ledger 47 -> 48** — Recovery: promote the suite in the effective `PROMOTED_FILES` (line ~867), never raise `MAX_DEFERRED` — Prevention: run `scripts/guard-vacuity-floor.test.sh` whenever a suite is added.
- **`git stash list` and `pgrep -f` blocked by hooks** — Recovery: avoided both — Prevention: already hook-enforced.
- **Battery rows N8a, N8c, M1 and D6 survived** — Recovery: added the 2^64-wrap and date-stub rows, fixed the non-running assert, widened the pin-name class — Prevention: re-drive every survivor against the current tree and treat a survivor as a possible harness defect first.
- **Shell cwd reset to the main checkout between calls** — Recovery: absolute worktree paths — Prevention: use absolute paths in worktrees.

## Tags
category: test-failures
module: apps/web-platform/infra (web-zot-consumer-probe)
