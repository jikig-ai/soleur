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

Run on commit 20aa1b169f plus this file's previous commit (tree clean at start). Scratch harness: for each mutant, copy the target to
a pristine copy, apply the anchor replacement after asserting it matches exactly once, run each listed file in its own
vitest process serially with the JSON reporter, record the failed row names, restore from the pristine copy and assert
the hash equals the committed one. Every restore hash matched, and `git status --short` was empty at the end.

Baseline (no mutation), 3 reps: `git-data-replication.test.ts` 71/71 and the new file 7/7, every rep.

| Mutant | Edit | Run set | Reps RED | Killing rows (identical in every rep) |
|---|---|---|---|---|
| N6 | `git-data-replication.ts`: drop `assertNoUrlRewrite(workspacePath);` before `const pushTarget` | replication, new file | 3/3 | mocked "the url/remote rewrite guard runs before ANY push" x2 (insteadOf, pushurl); R-PUSH-1; R-PUSH-2. **F21, F20 and every other row green in all 3; R-FETCH-* green.** |
| N6 on old T4 | same | host-git-consumers-real-git, host-git, replication, git-auth | 1/1 | the same two mocked rows only (59 + 29 + 66 rows green in the other files) |
| GC1 | `git-data-client.ts`: drop `assertNoUrlRewrite(workspacePath);` | new file, git-data-client | 3/3 | R-FETCH-1, R-FETCH-2, R-FETCH-3; mocked "a url.* rewrite ... REFUSES the fetch". R-PUSH-* green. |
| G-DISPATCH | guard: `if (keys.length > 0) throw` -> `if (false) throw` | new file | 3/3 | R-PUSH-1, R-PUSH-2, R-FETCH-1, R-FETCH-2, R-FETCH-3 (every refusal row) |
| G-SECOND | guard: remote-name branch -> `return false;` | new file | 3/3 | R-PUSH-2, R-FETCH-2, R-FETCH-3 (R-PUSH-1, R-FETCH-1 green) |
| G-OVER | guard: remote-name branch -> `return name !== undefined;` | new file | 3/3 | R-PUSH-0 (must-pass input refused) |
| H-FAKE | helper: drop the `-c url...insteadOf` prefix | new file, replication | 3/3 | R-PUSH-0, R-FETCH-0, R-FETCH-3; replication positive control, F20, both F21 rows |
| H-SPLICE-FETCH | helper: splice the receive-pack wrapper for every verb, not only `push` | new file | 1/1 | R-FETCH-0, R-FETCH-1, R-FETCH-2, R-FETCH-3 |
| WS1 | `workspace.ts`: drop `assertWorkspaceGitShape(workspacePath);` | workspace, context-queries-hook | 3/3 | workspace "re-provisioning a workspace whose .git is a gitfile naming another repository leaves that repository untouched" |
| WS3 | `workspace.ts`: `...(pin ? { cwd: workspacePath } : {})` -> `cwd: workspacePath` | same | 3/3 | workspace "a fresh workspace ends up with a real .git directory that git resolves"; the gitfile re-provisioning row |
| CQ1 | `context-queries-hook.ts`: drop `cwd: repoRoot` from the ls-files invocation | same | 3/3 | context-queries-hook "a gitfile .git naming another repository is refused: reported once as git-refused, ..." |

No mutant survived, so no row was added for WS1, WS3 or CQ1 (plan 5.1).

H-FAKE, against the plan's prediction: the plan expected every control to go red. The B-carrier controls of R-PUSH-1,
R-PUSH-2, R-FETCH-1 and R-FETCH-2 stay green, because those carriers route the URL to B by themselves and never use the
fake's prefix. Only rows that need the route to A go red (the positive rows and R-FETCH-3's inverted control). That is
the right behaviour, not a gap: a fake that can reach no store is caught by R-PUSH-0 and R-FETCH-0.

N6 on old T4, why it is RED now when the earlier battery (2026-11-10 12:27 CET, scratchpad `lead.out`) recorded
`SURVIVED ... pass=217`: on PR #12512's branch the push-side guard call arrived in db20b598bf (2026-11-10 11:17 CET), and
the first rows covering it, the two mocked "runs before ANY push" rows, arrived in 62cece11c7 (12:48 CET). At 12:27 the
call existed and no row covered it, so N6 could not be killed. The harness timestamp is local time on a CET host (not
otherwise verified). The real-git rows in this PR add R-PUSH-1 and R-PUSH-2 as independent killers.

Not claimed: this is the 11-mutant set above, not the earlier 39-mutant battery, which was not re-run.

## Addendum — 2026-11-11 (review fixes, commit 44f981dcfd)

The sections above are kept as recorded. Three corrections and additions from the review panel:

- **Row IDs renamed.** In the new file, R-PUSH-n is now UG-PUSH-n and R-FETCH-n is now UG-FETCH-n, because the old IDs
  shared the R-PUSH-/R-FETCH- prefix with `git-data-remote-url-wrapper.test.ts` (R-PUSH-SHALLOW, R-FETCH-OVERLAY). The AC7 table above uses the old names for the same rows.
- **AC7's mutant run was on commit 2974cad3c9's tree** (20aa1b169f plus the measurements commit).
- **The N6 window explanation has a fetch-side analogue that was not measured.** On #12512's branch the fetch-side
  guard call arrived in db20b598bf and the first row covering it (the mocked "REFUSES the fetch" row) in 62cece11c7, the
  same window as N6. So GC1 would likely have survived the earlier battery too. That is a prediction from history, not a
  measurement: GC1 was run on this branch only. Both commits may be unreachable from any ref after the squash merge.

New rows: each of UG-PUSH-1 and UG-PUSH-2 now runs with and without a local `soleur-store-tip-*` rescue branch.
UG-PUSH-3 is new: `url.<B>.pushInsteadOf`, whose control lands in B. UG-FAKE pins the fake's push argv. The new file
has 13 rows. Before these fixes, a guard moved below the rescue push (N6-MOVE) and a guard narrowed to `insteadOf`
(M-A) both survived the panel's probes.

Mutants were run in a sandbox on the tree later committed as 44f981dcfd, which only added a type-only cast in UG-FAKE after the run. Each was run serially, 3 reps, with the JSON reporter, and every
restore was hash-checked. Baseline: the new file 13/13 and `git-data-replication.test.ts` 71/71.

| Mutant | Edit | Run set | Reps RED | Killing rows (identical in every rep) |
|---|---|---|---|---|
| N6 | drop the push-side `assertNoUrlRewrite` | new file, replication | 3/3 | UG-PUSH-1..3, both rescue shapes (6 rows); the two mocked "runs before ANY push" rows |
| N6-MOVE | the push-side call moved from before step 1 to before step 2 (the main push) | new file, replication | 3/3 | UG-PUSH-1..3 **with a rescue branch** only (3 rows); replication file 71/71 green |
| M-A | guard `url.` prefix test narrowed to `^url\..*\.insteadof$` | new file | 3/3 | UG-PUSH-3, both rescue shapes |
| GC1 | drop the fetch-side `assertNoUrlRewrite` | new file | 3/3 | UG-FETCH-1..3 |
| H-SPLICE-DROP | helper: no `--receive-pack` splice for push | new file, replication | 3/3 | UG-FAKE only; replication file 71/71 green, including F21, as expected at a race rate this low |

Not claimed: H-SPLICE-DROP's replication green is three runs. It says nothing about the race rate without the wrapper.
That rate is AC2.
