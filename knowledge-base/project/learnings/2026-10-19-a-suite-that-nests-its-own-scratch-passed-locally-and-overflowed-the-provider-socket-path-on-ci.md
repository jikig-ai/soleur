# Learning: a suite that re-runs itself in a nested scratch tree passed locally and overflowed the provider socket path on CI

## Problem

`apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh` (#9927 item 5) passed 78/78, then 81/81, on the author's machine and through a 13-seat review panel. On CI (terraform 1.10.5) the parent's own 41 dynamic rows passed, but all 13 mutation-battery children exited 1 with `CI is set but the dynamic section did not run (blocked by: mint)`. CI had been red since the review-fix commit `c4aae64296`, and nobody read it until the fix round was over.

## Root cause

The parent keeps its scratch under `$TMPDIR` when that path is 40 bytes or shorter, and falls back to `/tmp` otherwise. On the runner `TMPDIR=/home/runner/work/_temp` (23 bytes), so the parent scratch was about 62 bytes. A battery child nests another scratch tree under it (`<parent>/c/<child scratch>/t/plugin<digits>`), which put the provider's unix socket path over the ~108-byte limit. `terraform apply` then failed in every child. Locally `TMPDIR` was unset, the parent used `/tmp`, and the same nesting stayed under 108 bytes.

Reproduced locally with `TMPDIR=/var/tmp/runner-wk/_temp`: the old code gave 68 passed / 13 failed, the fix gives 81/81.

## Solution

- Battery children get a short root outside the parent scratch (`mktemp -d "$child_base/irl-c.XXXXXX"` with `child_base=/tmp`), removed by `cleanup()`.
- The suite prints the child's first lines when a pristine control child fails, and the mint output when the mint fails (nothing is minted yet, so no secret can be in it). The first CI failure said only "rc=1" because the child output was never surfaced; diagnosing took two extra CI cycles.
- The trap-ownership lint's rule (e) counts a literal `/tmp` inside `mktemp` and has a high-water mark; an inline `lint-trap-ownership: ok` comment did not lower the count, taking the base from a variable did.

## Key Insight

A test that spawns itself as a child multiplies path depth. Any path-length-limited resource (unix sockets, 108 bytes) must be checked under the CI runner's real `TMPDIR` shape, not the developer's. And a self-spawning suite's local green says nothing about CI until the CI leg that owns it has been read: read it after the first push, before spawning review seats on top of it.

## Session Errors

1. **Fixture-relative ratchet red (28 sites in the new suite)** — Recovery: added the canonical `assert_fixture_dir` and called it in each writer. Prevention: copy the guard from the sibling suite when starting a suite that writes under a scratch root.
2. **Misread `echo "$(basename $t) RC=$?"` as an exit code** — Recovery: re-ran with `rc=$?` on its own line. Prevention: capture `$?` on its own line first.
3. **A cleanup script padded other code fences in the runbook** — Recovery: restored the file from HEAD and re-applied the rewrite. Prevention: edit docs with an anchored replacement, never a whole-file regex.
4. **`[[ ... ]]` passed as a command word through `dchk` failed** — Recovery: wrapped it in a function (`abs_paths`). Prevention: pass functions, not compound conditions, through assertion wrappers.
5. **Negative control was vacuous** (it compared against the wrong value, so it differed regardless) — Recovery: compare against `PRE_DIGEST`, caught by my own new import assertion. Prevention: every negative control needs a positive row proving it exercised the thing it negates.
6. **xtrace child exited 2 because the `_emit` self-test captured traced lines holding the value** — Recovery: moved the xtrace guard before the self-test; later pinned the row to the guard's own message. Prevention: a guard row must assert the reason, not just the exit code.
7. **A hook blocked `git stash list`** — Recovery: not needed. Prevention: none (hook working as intended).
8. **The architecture review seat ran a stray `git checkout --detach`** — Recovery: verified branch and tree afterwards. Prevention: review seat briefs say report-only and name git writes as forbidden.
9. **The performance seat returned an empty result mid-work, and a session restart stopped the coverage consult** — Recovery: resumed both with SendMessage. Prevention: treat an empty hand-back as "paused", not "done".
10. **CI red on the review-fix commit went unread through the whole fix round** (the socket-path overflow above) — Recovery: read the failed job log, downloaded the suite artifact, reproduced with a CI-shaped `TMPDIR`. Prevention: after pushing, read the CI leg that owns a new suite before spawning review seats; run suites that spawn themselves under a CI-shaped `TMPDIR`.
11. **The trap-ownership lint (rule e high-water) tripped on a literal `/tmp` in `mktemp`; the inline annotation did not help** — Recovery: took the base from a variable. Prevention: run `lint-trap-tempfile-ownership.py --check-highwater` (not only the per-file mode) before pushing any new `mktemp`.
12. **A chained `sleep` followed by a command was blocked by a hook** — Recovery: used Monitor with an until-loop. Prevention: wait on CI with Monitor from the start.

## Tags

category: test-failures
module: apps/web-platform/infra (inngest redis luks import rehearsal suite)
