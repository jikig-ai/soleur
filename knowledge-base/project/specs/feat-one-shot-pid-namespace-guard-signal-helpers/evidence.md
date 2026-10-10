# Evidence: PID-namespace guard for signal-helper mutants

Every figure below was read from command output on this branch. Written from the final state; corrections are appended, never edited in place.

## What was built

| Piece | File | Result |
|---|---|---|
| Helper | `plugins/soleur/scripts/run-in-pid-namespace.sh` | rc 125 plus a `RUN_IN_PID_NAMESPACE_REFUSED reason=<missing-unshare\|userns-unavailable\|not-isolating>` first stderr line on every refusal, the command never started, no fallback |
| Helper suite | `plugins/soleur/scripts/run-in-pid-namespace.test.sh` | real namespaces: `31 passed, 0 failed (31 cases, 0 skipped, real-namespace=yes)`; with a failing `unshare` first on `PATH`: `14 passed, 0 failed (14 cases, 18 skipped, real-namespace=no)` plus the SKIP line and row R8 (the real helper refuses); with `SOLEUR_REQUIRE_REAL_NS=1` and no namespace: rc 1 |
| Verb | `scripts/soleur-sandbox.sh run-isolated` | `tests/scripts/test-soleur-sandbox.sh`: `PASS: 75 checks across 75 cases` (57 before, 18 new arms) |
| Scan | `plugins/soleur/scripts/scan-ancestor-signal-helpers.py` + suite + baseline | suite `112 passed, 0 failed (112 cases, 0 skipped, planned 112)`; live scan `773 files, 8 findings, 8 baselined, 0 new, 0 stale, 0 unbounded, 0 skipped` and `ancestor-signal scan: CLEAN` in about 0.5 s; the exact discoverability command under `env -i` and `timeout 15` took 0.47 s |
| Second walker | `plugins/soleur/test/roadmap-reconcile.test.sh` | `112 passed, 0 failed` (109 before plus the three TS15f rows); the fake gh `term` walker is bounded at `SOLEUR_TEST_SUITE_PID` and pid 1 and signals nothing when the variable is unset |
| Docs | `work-scratch-sandboxes.md`, `risk-tier-and-fix-rounds.md`, `test-design-reviewer.md`, `plan-sharp-edges.md`, `review/SKILL.md` (one 179-byte pointer), ADR-250 amendment 3 | `review/SKILL.md` 476678 to 476857 bytes (ceiling 477000, ceiling file untouched) |

The baseline has **8 rows (2 W, 6 P)**, not the plan's 7: the sixth P row is `run-registered-suites.test.sh` (`_shim=$PPID`, then `kill -9 "$_shim"` two lines later), the derived-parent shape D3 describes and the prototype count left out. Class L (listed only) is 14, as predicted; class G has no site.

## Measured facts the design rests on

- `unshare -Urpf --kill-child --mount-proc -- sh -c 'echo "pid=$$ ppid=$PPID nspid=..."'` prints `pid=1 ppid=0 nspid=1`; exit codes pass through (7 stays 7); without `--mount-proc` the NSpid line has two fields (`nspid=2`) while `$$` is still 1, which is why the isolation check reads NSpid as well as `$$`.
- A command run through the helper sees `2 [] [-n]`-style arguments verbatim, including an empty argument and a leading `-n`; a command file whose name begins with a dash runs (`exec --`).
- Nested use works (`1 0` from a helper inside a helper).
- A backgrounded child tagged in its argv is gone after the helper returns (N5) and after the helper is SIGKILLed from outside (N5c).

## Mutation batteries (driver run through the helper itself, in a PID namespace)

Driver: a scratch script (not committed) over an allocator sandbox with a `git init` inside. One mutant at a time under `ulimit -v 6000000` and `timeout -k 10`, pristine copy restored by `cp` after every row, landing asserted by content anchor plus a changed-file check, unmutated controls first (helper suite rc 0, 31/0; verb suite rc 0, 75/0). Only rc 1 plus a `FAIL` line counts as a kill.

**Guard 1 (helper), 14 of 14 killed:** exec line replaced by `exec -- "$@"` (R4), probe always succeeds (R2), refusal exits 0 (R1), refusal falls through (R1), no missing-`unshare` arm (R1), no not-isolating arm (R3), each of `-p`, `--kill-child`, `--mount-proc`, `-U` dropped (R4b), in-namespace check deleted (R7), `unshare` resolved by bare name (R2), witness never written (R6), `/proc` half of the check dropped (N7).

**Guard 3 (verb), 12 of 13 killed on the strict discriminator** (a line starting `[FAIL]`; a first pass used a looser match that also hit a section header, so the strict re-run is the record): drop all shape checks, verb dispatches to usage, drop `pwd -P` agreement, drop basename, drop marker-present, drop marker-regular, drop marker-not-symlink, missing helper falls back to a direct run, helper run before `cd`, helper marker printed on a shape refusal, trailing-slash trimming removed. Two rows are labelled, not hidden:
- Drop the owner check: GREEN as predicted. A directory owned by another user cannot be built without root, so the conjunct has no fixture here; it is exercised by the verb's own text only.
- Drop the absolute-path check: SURVIVED, and is **equivalent**: a relative path can never equal the result of `pwd -P`, so the `pwd -P` agreement check refuses every relative path first. The relative-path arm was changed to use a relative path that does resolve to a real sandbox (`cd` into its parent, pass the basename), which is the case where the two checks could have differed.

**Guard 2 (scan), by the scan subagent over the final scanner and suite:** 80 mutants, 74 killed, 5 predicted green (`=~` dropped from the comparator regex, the git-failure arm removed because the empty-population arm still returns rc 3, `os.replace` to `os.rename`, git timeout 120 to 121, a widened line pre-filter), 1 equivalent (removing `rstrip("\r")` changes nothing observable because every later step uses `\s` or `str.split()`); earlier rounds found 5 survivors that were fixed with fixtures (trailing-comment cut, quoted verbs after `;` or `&&`, `kill -s 0 $PPID`, a bound token with `exit` but no comparison, the `ps` and PPid-field cursors).

## The incident shape, run only inside the namespace

Through the helper, in the sandbox copy of the roadmap-reconcile suite:
1. Unmutated suite: `112 passed, 0 failed` inside the namespace.
2. No-kill rehearsal (catch-all match, `kill` replaced by `echo`): `REHEARSAL-TARGET 2254 suite=1313`. The walk resolved a target above the module and stopped at the suite's own PID (1313), never above it.
3. Catch-all match with the real `kill` and the bound kept: suite rc 0, `112 passed, 0 failed`. The bound contains the catch-all mutant (it signals only the module), so the mutant is harmless and green by design; this is the S5 bound doing its job.
4. The incident shape (catch-all match AND the suite-PID bound removed, real `kill`): inside the namespace the walk terminated the suite's own subshell chain (`Terminated`, TS15e not reached) and stopped at pid 1; the host session, and this session's pid, were unaffected afterwards. This is the mutant that ended the desktop session four times, run where it cannot.

## Repo-global gates (each run alone)

- `python3 scripts/lint-shell-capture-exit.py --baseline ...`: `1528 script(s) scanned, 0 new findings, 224 baselined`.
- `bash scripts/guard-vacuity-floor.test.sh`: `23 passed, 0 failed`.
- `bash scripts/lint-orphan-test-suites.sh`: `655 covered, 0 orphaned` (the two new suites register through the existing `plugins/soleur/scripts/*.test.sh` glob; no runner edit).
- `python3 scripts/lint-guard-contract.py <plan>`: 3 guard entries.
- `bash .claude/hooks/grep-q-pipe-guard.test.sh`: rc 0 (the new files add no early-exit pipe under the swept roots).
- `scripts/lint-skill-body-budget.py --base <merge-base>` OK; `scripts/lint-skill-body-budget.test.sh` 15/0; `bun test plugins/soleur/test/components.test.ts` 1398 pass, 0 fail; `bun test review-tier-parity.test.ts` 12/0 (docs subagent).
- `scripts/pre-push-ratchet-lane.sh` first run: RED on two members, both caused by this change and fixed at the source: `fixture-relative-assert` (a relative `cp` operand and a `cd "$(dirname ...)"` in the sandbox suite; now guarded with `assert_fixture_dir`) and `test-affected-kb-consumers` (the scan suite named two files whose text carries `knowledge-base/` paths; the scan docstring no longer spells the learning path and the suite's two regexes escape the file-name dots so the oracle no longer reads them as script tokens). Re-run of the members: `fixture-relative-assert` 62/0, `fixture-dir-operand-assert` 71/0, `test-affected-kb-consumers` 22/0.
- Shellcheck: the new files carry two intentional info notes (SC2016 on the single-quoted text that runs inside the namespace) and one file-level SC2319 disable with its reason (the suite's `check` consumes the status of the condition above it by design).

## What a merge fires (derived, not assumed)

A matcher over every `.github/workflows/*.yml` with a `push`, `pull_request`, `merge_group` or `pull_request_target` trigger, applied to the 62 files of `git diff --name-only origin/main...HEAD`: `version-bump-and-release.yml` 55 of 62, `web-platform-release.yml` 10 of 62, `deploy-docs.yml` 5 of 62; the other 15 push-filtered workflows and every path-filtered `pull_request` workflow match 0 of 62; the seven unfiltered push workflows run as on every merge.

## Not run here, stated

- `scripts/test-all.sh` in any form (CI's required `test` check is the full battery).
- A Docker `ubuntu:24.04` userland run: CI's scripts leg is the userland check. In that image the real-namespace rows are expected to SKIP (the default seccomp profile blocks `unshare`), so only the refusal branch runs there.
- The `REAL_NS=yes` rows may never run in CI: ubuntu-24.04 restricts unprivileged user namespaces and `ci.yml` relaxes the sysctl only best-effort on the scripts leg.
