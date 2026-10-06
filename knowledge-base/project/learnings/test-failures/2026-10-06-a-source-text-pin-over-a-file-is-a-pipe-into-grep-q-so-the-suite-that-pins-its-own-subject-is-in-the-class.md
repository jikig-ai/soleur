# Learning: a source-text pin over a file is a pipe into `grep -q`, so a suite that pins its own subject is in the early-exit class

## Problem

On run 37426931446 (attempt 2) `gen-github-egress-cidr.test.sh` failed with
`FAIL: live fetch bounded (no comment-stripped meta_json=... line)`, `94 passed, 1 failed`, rc 1 after 5 s, and
passed on attempt 1. The failure was not in the diff of the PR being merged and the suite never touches a stub,
so it read as a flake.

## Root cause

Line 779 is `grep -vE '^[[:space:]]*#' "$GEN" | grep -qE '^[[:space:]]*meta_json=...'` under `set -uo pipefail`.
`$GEN` is 17,002 bytes and the match is on line 88. `grep -v` writes in 4 KiB chunks, `grep -q` exits at the
first match, and the producer takes SIGPIPE (rc 141), or EPIPE (rc 1) where SIGPIPE is ignored as on the CI
runner. `pipefail` reports the producer's status, so a present line reads as absent. Measured at the exact
assertion, 3,000 iterations: default SIGPIPE 4 misses, ignored SIGPIPE 1 miss (19 and 11 in an earlier run of the
same loop); `grep: write error: Broken pipe` on stderr. After the rewrite: 0 and 0.

## Solution

`grep -vE ... "$GEN" | grep -cE '...' >/dev/null`: the same exit status as `grep -q`, and `-c` reads the whole
stream. All five pipe-fed readers in the file were converted; four of them are `| grep -q` over a producer that
is a file or a python oracle, not a stub.

## Key insight

The earlier sweep looked for the pipe where a stub is involved. A suite that PINS ITS OWN SUBJECT (reads the
script under test, strips comments, greps for a construct) has a producer longer than a pipe chunk by
construction, and is in the class with no stub at all. The probability is small per run (0.04 to 0.6 percent
here) and CI parallelism is what lifts it into a red check, which is why it reads as a flake and passes on rerun.
Verdict by artifact: read the failing run's own log, find the assertion's line, and reproduce THAT pipeline in a
loop under both SIGPIPE dispositions before deciding flake versus real.

## Tags

category: test-failures
module: gen-github-egress-cidr, grep-q-pipe-guard

## Related

- `2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md`
- `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`
- Trackers: #9217, #7376, #7005
