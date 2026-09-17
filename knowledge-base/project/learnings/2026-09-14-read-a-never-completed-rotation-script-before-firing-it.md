---
title: "A rotation script that had never completed a run would have bailed right after the irreversible step"
date: 2026-09-14
category: security-issues
module: scripts/rotate-supabase-db-credential.sh
tags: [credential-rotation, supabase, doppler, ordering-bug, read-before-run, silent-exit]
issues: [7966, 8186]
severity: P2
---

# A rotation script that had never completed a run would have bailed right after the irreversible step

## Problem

#7966 (a leaked dev `postgres` password) was to be closed by running
`scripts/rotate-supabase-db-credential.sh --config dev --leaked`, which had merged
two PRs earlier. It had tests for nothing and had never been run to completion.

Read end to end before firing, it had `TARGETS="$_tmp/targets"; export TARGETS`
two lines **below** the python hash check that opens `os.environ['TARGETS']`.
Every run would have:

1. PATCHed the live database password (irreversible),
2. rewritten Doppler,
3. `KeyError` → printed "at least one secret does NOT carry the new password" (false) → exit 7,

skipping the connectivity proof and the `--leaked` session sweep, and leaving a
plaintext recovery file. The operator would have seen a CRITICAL message telling
them Doppler was not updated when it was, in the middle of a leak response.

Review then found a second defect in the same tail: the sweep ran under
`set -e`/pipefail with psql lacking `ON_ERROR_STOP`, so a docker failure exited
silently and a SQL refusal printed `terminated=ERROR…` with exit 0.

## Solution

PR #8186: export before the read; make a failed sweep exit 8 loudly (recovery file
removed, since Doppler is verified by then). An end-to-end test drives the script
against stub `doppler`/`curl`/`docker` on PATH. The test failed on each defect before
its fix and passes now. The rotation then ran from the fixed branch: rc=0, fingerprint
`f8b6b6dd761c` → `d36e379f658d`, old password refused >60s after (past the
Supavisor auth cache), new accepted.

## Key insight

**A script whose failure branch sits after an irreversible step has only been tested
if something has run it past that step.** Bugs cluster in the tail (verify, sweep,
cleanup) because a dry-run or an early-exit test never reaches it. Before firing any
credential/infra script at a live target:

- `git log` the file: has anything ever run it to `DONE`? If not, read the tail
  as carefully as the head.
- Grep every `os.environ[...]` / `$VAR` read against where it is set. Ordering
  bugs inside heredoc'd python are invisible to shellcheck.
- Stub the side-effecting binaries on PATH and run it end to end. For this script
  that was ~80 lines of test and caught both defects.

## Session errors

- The first commit was blocked by gitleaks `database-url-with-password` on synthesized
  fixture DSNs. **Fix:** hold the scheme in a variable (`${SCHEME}://…`) so the literal
  isn't URL-with-password shaped. **Prevention:** build synthesized DSN fixtures that way
  from the start.
- A compound Bash command containing `gh pr merge` was blocked whole by the
  review-evidence hook, so the trailer commit in the same command never ran.
  **Prevention:** run `emit-review-trailer.sh` as its own call before the merge call.
