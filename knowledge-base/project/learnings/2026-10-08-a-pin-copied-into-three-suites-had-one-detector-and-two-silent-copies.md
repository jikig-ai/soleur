# Learning: a base-image pin copied into three suites had one drift detector and two silent copies

## Problem

`rule-audit.yml` reported that `ubuntu:24.04` had moved under the git-data rung-1 rehearsal. The issue
(#9252) named one file and a "live" digest. Two things were wrong with that framing:

- The issue's digest (`008173c2…`) was already stale; the tag had moved again to `534baea6…` by the time
  the work started. A digest quoted in an issue is a reading, not a pin.
- The same `UBUNTU_BASE='ubuntu:24.04@sha256:…'` literal lived in THREE suites. The detector parses only
  the rehearsal file, so the other two copies (`git-data-ownership.test.sh`, the inngest Tier B suite)
  were invisible to it and would have gone stale on the next bump with every gate green.

## Solution

- Re-resolved the index digest (`docker buildx imagetools inspect`), confirmed it is an index
  (`application/vnd.oci.image.index.v1+json`) like the old pin, and re-measured `mke2fs -V`, dpkg
  e2fsprogs and the plain / `-O project` / `-O casefold` feature sets inside both images. Identical, so
  the R1 allowlist needed no row change and the fixture was left alone. The measurement is recorded in the
  pin stanza comment.
- Bumped all three literals, then (review round) made the two siblings READ the pin from the rehearsal
  file with the anchored `sed` that `git-data-cutover-access.test.sh` already used, failing setup if it is
  unreadable. A future bump now touches one file.

## Key Insight

When a value is copied into N files and only ONE has a mechanical detector, the other N-1 are not
"in lockstep" — they are unobserved. Four review seats (architecture, test-design, git-history, security)
converged on this independently. If a derivation idiom already exists in the same directory, use it; do not
add a parity test.

## Session Errors

1. **A compound Bash call included `git stash list`, rejected by the stash-block hook.** — Recovery: re-ran
   without it. — **Prevention:** never include any `git stash` subcommand in a worktree command, even
   read-only; probe `refs/stash` with `git rev-parse --verify --quiet refs/stash` instead.
2. **The first re-measure comment quoted the old digest prefix, which the plan's AC-2 grep
   (`git grep 33ceb71981b6`) would match.** — Recovery: reworded to dates only before committing. —
   **Prevention:** a comment that records a retired literal violates an "old literal is gone" sweep; record
   the date, not the value.
3. **The issue's quoted live digest was stale.** — Recovery: the brief said to re-resolve; re-resolved. —
   **Prevention:** resolve a rolling-tag digest at work time and again before marking ready.
4. **The two sibling pins were hand-copied.** — Recovery: derived from the rehearsal file in review. —
   **Prevention:** at plan time, `git grep` the literal repo-wide and ask which copies have a detector.

## Tags
category: infra-tests
module: apps/web-platform/infra
