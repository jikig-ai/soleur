# Learning: converting the remaining changed-path readers — every defect the review found was in a proof, not in a conversion

## Problem

PR #12494 converted ~25 groups of fail-open changed-path readers (plain `git diff --name-only`) to the NUL-delimited, rename-free,
submodule-honest form and extended the sentinel suite with a code and prose census. The conversions were mechanical and green. The 13-seat
review (risk tier `aggregate pattern`) then found five P1s, and none was in a converted reader:

1. **A byte-locale hole in the ALLOW-class classifier.** `settle-then-admin-merge.md` pipes the changed list through two `grep -vE`. In a UTF-8
   locale GNU grep treats a line holding an invalid-UTF-8 byte as binary, prints `Binary file matches` to stderr and nothing to stdout, so the
   second filter received empty input and the pipeline read "no path outside the allowlist": `hatch-eligible` for `src/\xff.sh`. Before the
   PR git C-quoted that name, which failed the allowlist, so the conversion itself created the regression. The same class sat in the ship PIR
   conjunct and the stray-worktree step.
2. **A spelling pin standing in for behaviour.** The only guard on that classifier was a `PINNED_Z` regex over its `tr '\n\0' '?\n'` line. Replacing the
   allowlist with `grep -vE '^()'` left the suite green.
3. **Registry parity for a new suite.** `scripts/allowlist-diff` was registered always-on, but the always-on justification ledger had no row and the
   floor band (`count - floor <= 5`) read 6.
4. **A premise written into a comment without being measured.** The FK-lint fix claimed `actions/checkout` configures only the pull merge ref, so a
   bare `fetch origin main` leaves `origin/main` absent. The verifier seat reproduced a stock checkout and found it keeps the all-heads refspec.
   The explicit refspec is still correct for single-branch clones, but the comment was false.
5. **A portability regression introduced by a fix.** `xargs -d '\n'` is GNU-only; on BSD it fails before grep runs and the pipeline prints
   nothing, which the close-defer check reads as "no hit".

## Solution

- Run every allowlist grep over a changed-path list under `LC_ALL=C`, and **execute** the classifier: the sentinel suite now extracts the
  fenced block from the reference and runs it in a fixture repo (docs-only eligible; newline name, invalid-UTF-8 byte, rename-out, empty
  diff and failed fetch refused), plus a mutant control (`sed` removing `LC_ALL=C`) that must flip the verdict, proving the row is load-bearing.
- Register a new suite everywhere it is counted (test-all.sh, affected-paths, durations, shard legs, always-on array, justification ledger,
  floor band, kb-consumers baseline) and run the guards that derive from those files.
- Reproduce a CI-environment claim on a scratch clone before writing it into a comment; use a portable `tr '\n' '\0' | xargs -0`.
- Name the census window honestly in the suite header: it is a regression ratchet on the readers it can see (extension-less hooks, lefthook,
  composite actions, templates, `tests/scripts/lib` gates, server runtime readers, other verbs and `-C`-first argv are outside it).

## Key Insight

A guard that pins the SPELLING of a fix cannot distinguish a working fix from a stray copy of its words, and a conversion that removes a
failure (git C-quoting a hostile name) also removes the safe side effect that failure had. For an ALLOW-class reader, the regression direction is
always "fewer lines reach the filter", so test the filter with inputs the old behaviour refused for a reason you never named (quoting, encoding,
newlines, renames), and run the extracted command, not a regex over it. Registering a suite is a multi-file transaction; the guards that check
the transaction only run when you run them.

## Session Errors

1. **Merge-queue-era drift: the branch was 19 commits behind a main that retired the accept-row ratchet (#9729).** The first verification pass
   used a stale `origin/main`; the ratchet then failed `accept-bad-kind` on rows nobody touched, and merging conflicted on the deleted accept file
   and the `PJ_TRIPLES` line. — Recovery: merged, deleted the accept file, reconciled the count. — **Prevention:** `git fetch origin main && git
   merge-tree --write-tree origin/main HEAD` and `git rev-list --count HEAD..origin/main` before any whole-repo ratchet run, not only before the panel.
2. **Floors and baselines moved after the merge.** The census floors (85→83, 139→137) and two baselines (`ci-oracle-review` rows from main) were
   stale. — Recovery: removed two stale exempt rows, lowered the floors, regenerated the baselines with the guards' own `--write-baseline`. —
   **Prevention:** after a merge, re-run the suite and the baselines generators before reading any red as a regression of the branch.
3. **A long guard run was killed by memory pressure and its watcher read the wrong file.** `Run registry and meta-guards` was reaped; a second
   Monitor tailed a task output file that held earlier output and ended at once. — Recovery: read the real log and exit codes. — **Prevention:**
   wait on a log line that only the finished run can write (`^RC <name>=`), never on a file another command already filled; after a reap, report
   it and do not restart without being asked.
4. **`timeout` under load read as a verdict.** `test-affected-kb-consumers.test.sh` exited 124 at host load ~50 and printed `3 passed, 28
   failed`. — Recovery: re-ran alone with the 590 s foreground maximum, 31/31. — **Prevention:** treat rc 124 as unresolved, never as a result;
   check `uptime` before budgeting a timeout for a guard that forks hundreds of times.
5. **Chained `echo "rc=$?"` made a task notification say "exit code 0".** — Recovery: read the `RC` lines from the log. — **Prevention:** the
   background-task notification is liveness, not verdict (already in the work skill); write `echo RC name=$?` immediately after each command.
6. **A hook blocked scratch-repo commits that used a `$VAR` path, and blocked `rm -rf` on a `.git`-bearing scratch dir.** — Recovery: built the
   fixture with `git fast-import` into a fresh literal path and left the dir. — **Prevention:** scratch repos get literal absolute paths and
   plumbing (`fast-import`) instead of `git commit`; never plan to `rm -rf` a directory containing `.git`.
7. **A review fix was applied on a premise I had not measured (checkout refspec).** The comment I wrote for the FK lint asserted
   `actions/checkout` configures only the merge ref; a stock checkout does not. — Recovery: reworded the comment to the narrow-refspec case it
   is true for (verifier seat). — **Prevention:** reproduce a CI-environment claim on a scratch clone before it enters a comment (the
   falsifying command is one `git remote -v; git config remote.origin.fetch`).
8. **Fixes introduced two defects of the class under review.** `xargs -d` (GNU-only) and a `?per_page=100` URL the `gh` stub did not model, which
   reddened six `detect-wt` rows. — Recovery: portable `tr | xargs -0`; the stub accepts both URL forms. — **Prevention:** after every URL, flag or
   locale change in a converted reader, run the `steps` section before committing, not after.
9. **A new always-on suite was registered in four files and not in two.** The justification ledger row and the floor band were missed until the
   data-integrity seat ran the ledger test. — Recovery: added the row, moved the floor 113→114 in both pins. — **Prevention:** after adding to
   `ALWAYS_ON_SUITES`, run `scripts/always-on-ledger.test.sh` and read the `f1` band in `test-all-affected.test.sh`.
10. **`/usr/bin/time` is not installed**, so a duration measurement failed and the suite-durations value was an estimate labelled `measured`. —
    Recovery: relabelled `floor`. — **Prevention:** never write `measured` for a hand-set number; use `floor` or `estimate`.
11. **Earlier phases (forwarded from session-state):** the technical-ruling-gate rejected a bad ruling shape; markdownlint failed on
    `session-state.md`; a token line used an apostrophe; `--match` must be the helper's first argument; the first G2 classifier used
    `tr '\0' '\n'` (forgeable by a newline name; fixed with `tr '\n\0' '?\n'`); a deferral-ledger floor was placed in the wrong spot; three
    overlap-preflight rows failed on a tab-named own file; five `$F/...` sites lacked `assert_fixture_dir`; and thirteen meta-guard reds
    (fixture-relative-assert, grep-q-pipe-guard, kb-consumers) followed the sentinel extension. — Recovery: each fixed in place. —
    **Prevention:** run the repo meta-guards after each wave's last suite edit, not once at the end (recorded in the operator constraints).

## Triage (recurring vs one-off)

| item | recurring? | disposition |
|---|---|---|
| stale `origin/main` before a whole-repo ratchet | recurring | fix-now: recorded as the Prevention above; no code change |
| floors/baselines moved by a merge | recurring | one-off per merge; the guards print the remedy |
| rc 124 / reaped run read as a verdict | recurring | documented here and in the work skill sharp edges; no new rule |
| classifier spelling pin | recurring | fix-now-inline: executed rows + mutant control (done in this PR) |
| new always-on suite parity | recurring | fix-now-inline: ledger row + floor (done); the ledger test is the guard |
| hook blocks on scratch repos | one-off | noted |
| `/usr/bin/time` missing | one-off | noted |

## Tags

category: workflow-issues
module: changed-path-readers
