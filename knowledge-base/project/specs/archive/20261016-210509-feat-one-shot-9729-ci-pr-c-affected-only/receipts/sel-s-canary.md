# Cold, warm and restored selector wall time on a fresh hosted runner (S4 PR C, Ref #9729)

Vehicle: the throwaway branch `canary-sel-9729` (cut from the feature head, one extra push-triggered workflow, never merged and
not in this PR's diff). Run 38915022354 (the first run, 38914189034, called the selector with `CI` set and is superseded: it reported
every suite selected). Both jobs ran on `ubuntu-latest`: **4 vCPU** (`nproc=4`), kernel `6.17.0-1022-azure`,
image `20261012.334.1`, Ubuntu 24.04.5 LTS. The selector was called the way the driver calls it:
`env -u CI -u SOLEUR_TEST_FORCE_ALL -u GITHUB_OUTPUT ... bash scripts/test-all.sh --print-selection --paths=README.md`, with the checkout
mirrored from `pr-selection` (`fetch-depth: 0`). Times below are the jobs-API step times (and the in-step `date` wall clock).

| Pass | Where | Wall (in-step) | Jobs-API step | Derive cache |
|---|---|---|---|---|
| cold | job `cold-warm`, fresh runner, empty cache | **146.4 s** | 14:21:15Z to 14:23:41Z (146 s) | hits 0, misses 631 |
| warm | same job, same cache | **13.4 s** | 14:23:41Z to 14:23:55Z (14 s) | hits 629, misses 2 |
| restored | job `restored` (needs `cold-warm`), a SECOND fresh runner, cache saved by the first job and restored with `actions/cache/restore` | **10.8 s** | 14:24:19Z to 14:24:30Z (11 s) | hits 629, misses 2 |

Selection result for the doc-only path: `AFFECTED_SUMMARY selected=114 of=631 always_on=114 edge=0 fallback=none`.

Overheads in the same runs (jobs API): `actions/checkout` with full history 16 s and 17 s; cache restore 1 s; the whole `restored` job
33 s (14:24:00Z to 14:24:33Z), billed as one minute. So the restored path costs about 11 + 17 + 1 = **29 s** of the job.

Reading (units: seconds of wall time, one pass, one runner each, README.md as the only path):
- a COLD pass takes **146 s**, above the driver's 90 s budget, so a cold production job is censored by construction (`selector_timeout`), as the
  ADR predicted; the stage-2 notices of the dark window agree (6 of 10 at the 90 s ceiling);
- a restored cache brings the pass to **about 11 s**, so the restored-cache selection wall plus checkout and restore overhead is about
  29 s, well inside the 120 s R3 allowance (criterion c, timing leg);
- the derive cache records carry the worktree path and the cwd, and the canary's two runners share one workspace path, so the restore on a
  different runner hit 629 of 631 records; the production cache design (restore-only, key from main) is PR D's.
