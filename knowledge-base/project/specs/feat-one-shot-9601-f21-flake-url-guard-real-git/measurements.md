# Measurements: F21 flake root cause and url-guard entry-point real-git rows (Ref #9601)

Host: git 2.56.0, vitest 4.1.12, Linux. All runs from `apps/web-platform`, one vitest process per run, serial unless
stated. These are local measurements only. Nothing here was measured in production.

## AC1 Baseline (unmodified tree, planning phase, 2026-11-11)

Isolated F21 row (`-t "F21: the local rescue branch is deleted"`), 130 runs: **3 failures (2.3%)** (runs 3, 21, 106),
load average 7.7-10.3. Every failure was the same assertion: `test/git-data-replication.test.ts:1294`,
`await expect(second.out).resolves.toEqual({ status: "replicated" })`, rejected with
`Command failed: git push { stderr: '' }`. That is the second replicate's main push, a no-op push carrying push options.
Empty stderr does not match the transient-retry regex, so it is not retried.

## AC2 Mechanism (K-push stress, work phase, 2026-11-11)

The production step-2 argv (`push --force <git-data URL> <heads> <tags> --push-option=lease-gen=1
--push-option=worktree-id=<WT>`), through the fake's `-c url.file://<stores>/.insteadOf=<git-data URL base>` prefix,
against a store that already holds every ref (so each push is a no-op). 10 parallel copies x K=1000 pushes per arm,
load average 6.93 at start, 13.20 at end.

| Arm | Failures per copy | Total | Exit codes |
|---|---|---|---|
| plain (direct client-to-receive-pack pipe, the old fake) | 191, 191, 202, 194, 200, 194, 213, 203, 195, 189 | **1972 / 10000** | all 141 (SIGPIPE) |
| drain (`--receive-pack=sh -c 'git-receive-pack "$0"; s=$?; exec >/dev/null; cat; exit $s'`) | 0 x 10 | **0 / 10000** | none |

The wrapper was confirmed to be invoked (a marker file written from inside it; the push returned rc 0). The stress is
checked against its own negative: the plain arm is nonzero, so the stress can fail.

Cause (git `send-pack.c`): with no commands, the client writes a flush plus the push-option packets, then a separately
written trailing flush. `receive-pack` reads the first flush, finds no commands and exits; if it exits before the
client's last write, the client takes EPIPE, which git turns into SIGPIPE (rc 141, no message).

What this does NOT show: the production ssh path was not measured. The wrapper models an ssh-like intermediary that keeps
reading after the remote exits; it is not ssh. With the wrapper in place, F21 can no longer detect this race if
production starts hitting it.

## AC4 / AC5 Post-fix

Serial loop, per-run exit code plus a check that vitest printed `Tests N passed` (so a run that executed nothing
does not count as green). 225 runs executed, 225 green.

| Set | Runs | Failures | Load average (1/5/15 min) start, end |
|---|---|---|---|
| F20 isolated (`-t "F20: store holds heads/fix/x"`) | 5 | 0 | 11.27 9.81 9.60, 11.65 9.95 9.65 |
| F21 isolated (`-t "F21: the local rescue branch is deleted"`) | 200 | **0** | 11.65 9.95 9.65, 11.57 18.90 16.83 |
| whole file (`test/git-data-replication.test.ts`, 71 rows) | 20 | **0** | 11.57 18.90 16.83, 13.13 17.37 16.49 |

Load was higher than in the baseline (7.7-10.3), so the conditions were no easier.

Power: if the post-fix rate were still the baseline 2.3%, 0 failures in 200 runs would happen with probability
0.977^200, about 1%. The 95% upper bound on the post-fix rate from 0/200 is about 1.5% (rule of three). This bounds the
rate; it does not prove it is zero. The K-push stress (AC2, 0/10000 with the wrapper) is the stronger evidence for the
mechanism.

Tree: runs 1-5 (F20) and the first F21 runs used commit db3abb95d3. The helper's env parameter was then changed to take
the shared fixture-env builder by injection (same routing, same wrapper), committed as 20aa1b169f; the later F21 runs
and all 20 whole-file runs used that change. One F21 run started during that two-file edit and passed.

## AC7 Mutants

(filled below from the mutant harness)
