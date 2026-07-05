---
title: A bash function's return-code contract change has a test blast radius beyond its sibling .sh suite — grep every TS/bun suite that sources it via subprocess
date: 2026-07-05
category: test-failures
tags: [bash, test-blast-radius, orphan-suite, return-code-contract, content-publisher, resume, full-suite-exit-gate]
issue: 6065
pr: 6069
---

## Context

#6065 changed `scripts/content-publisher.sh`'s `post_*` skip paths from `return 0`
to a `return 3` skip sentinel (so an all-skip file stays `scheduled` instead of
flipping to `published`). The plan's Phase 4 authored a NEW bash test suite
(`scripts/test-content-publisher.sh`) and wired it into `test-all.sh` — and stopped
there. But a **pre-existing** bun suite, `test/content-publisher.test.ts`, sources
the same script via `Bun.spawnSync(["bash", ...])` and asserts the exit code of each
`post_*` skip path directly. Nine of its assertions still expected `exitCode 0`.
The originating one-shot session was killed before it reached the Phase 2 full-suite
exit gate, so the stale bun assertions shipped to the WIP PR and reddened the
`test-bun` CI shard (`test-scripts` was green — the trap: the shard that owns the
NEW suite passes, the shard that owns the ORPHAN suite fails).

## The lesson

When a change alters a **bash function's return-code (or stdout) contract**, the
test blast radius is `{sibling .sh suite}` ∪ `{every TS/bun/pytest suite that shells
out to that script}`. `tsc`/the touched-file loop never sees the subprocess suite —
only a repo-wide grep or the full-suite exit gate does. Cheapest enumeration at
work-start:

```bash
git grep -lE '<script-basename>|<function-name>' -- '*.test.ts' '*.test.js' '*.sh' '*.py'
```

For `content-publisher.sh` specifically, the subprocess suite is
`test/content-publisher.test.ts` (a `runFunction()` helper that sources the script
under `set -euo pipefail`, so a `return 3` propagates as `exitCode 3`).

## Prevention

- Treat "renamed/added the sibling .sh test" as necessary-not-sufficient. Grep for
  every consumer of the changed contract before declaring Phase 2 done.
- The **full-suite exit gate** (`bash scripts/test-all.sh`, all shards) is the
  backstop that catches orphan suites — the same class as #3533. A resumed session
  MUST re-run it: prior-session "tests pass" claims cover only the suites that
  session ran.
- Same shape as the hook-source-swap sweep and the supabase-chain sweep, generalized
  to "any cross-language consumer of a changed contract."

See also: `2026-06-15-hook-source-swap-sweep-all-real-hook-renderers-not-name-filtered.md`,
the Phase 2 Full-Suite Exit Gate (#3533).
