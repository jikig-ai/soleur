# Learning: a test-only override seam used by 100% of tests leaves the production default untested

**Date:** 2026-07-17 · **PR:** #6621 · **Issue:** #6525 · **Surface:** `apps/web-platform/infra/ci-deploy.sh` + `ci-deploy.test.sh`

## Problem

The #6525 fix added a bounded transient-retry loop to `_ghcr_pull_or_recover`, wired through a
test-only override seam `PULL_TRANSIENT_RETRY_SLEEPS` (default `"2 4"` in prod; tests pass `"0 0"`
so the loop runs instantly). All six initial `#6525` tests set the seam to `"0 0"`. That made a
one-character regression **invisible**: mutating the default `${PULL_TRANSIENT_RETRY_SLEEPS-2 4}`
→ `${PULL_TRANSIENT_RETRY_SLEEPS-}` (empty default → `max=0` → **zero retries**) is byte-for-byte
the pre-#6525 bug the PR exists to fix, yet the suite stayed **green** — because no test ever
exercised the unset/default path. The seam that makes the tests fast also made them blind to the
production wiring.

Two adjacent authoring foot-guns surfaced on the same change:

- The shared-predicate **doc comment** reproduced the sibling regex's exact pipe-sequence literal
  (`unauthorized|authentication required|denied|forbidden` and a distinctive token `server
  misbehaving`). A comment is scanned by grep-based Single-Source-of-Truth / count guards
  (#6400 AC3 asserts that auth regex appears exactly once; a self-written T-6525-7 counted a
  distinctive token). The prose literal inflated both counts → guard false-fail.
- A bare `[[ cond ]] && cmd` **standalone statement** added to a helper that runs under
  `set -euo pipefail` returns the failed `[[ ]]`'s non-zero exit when the condition is false →
  `set -e` aborts the whole suite early (looks like a mysterious mid-run crash, not a test FAIL).

## Solution

- **Test the seam's absence.** For every "test-only override" seam (fast-path sleep schedules,
  injected clocks, `MOCK_*` toggles, `SOLEUR_*_FILE` overrides), add at least one companion test
  that runs with the seam **unset** so the production default is actually exercised. Here: T-6525-8
  runs with `PULL_TRANSIENT_RETRY_SLEEPS` unset (default `"2 4"`) and a no-op `sleep` mock
  (`MOCK_SLEEP_NOOP=1`) to stay fast, asserting exactly 3 pulls (1 + 2 retries) — which pins both
  that the default is non-empty (kills the zero-retry mutation) and the exact retry count.
  **Mutation-proven:** with the default emptied in-place, T-6525-8 FAILS (1 pull); restored via a
  pre-mutation backup copied back in a separate Bash call.
- **`-` vs `:-` for a disable lever.** The seam documented `""` as "disable the retry", but
  `${VAR:-default}` substitutes the default on empty *and* unset, so empty silently gave the
  default. Use `${VAR-default}` (no colon) when empty must mean empty; add a test locking it
  (T-6525-9: empty → exactly 1 pull).
- **Never reproduce a sibling regex's literal in a doc comment** near a grep-based count/SSOT
  guard — describe the class in prose (`the auth-denied class`) instead of pasting the pipe
  sequence. Verify with the guard's own grep before the full run.
- **Never write a bare `[[ … ]] && cmd` standalone under `set -e`** — use `if [[ … ]]; then cmd; fi`
  (an `if` always exits 0 when the condition is false).

## Key Insight

A fast-path override seam is a **coverage hole disguised as a convenience**: the value that makes
tests fast is the exact value production never uses, so 100%-override adoption means the prod
default has zero executable coverage. Every override seam needs a companion "seam-absent" test.
Corollary from this file's long history: a comment is not inert — grep-based guards read comments,
so a literal pasted into prose participates in the count it was meant to only describe.

## Session Errors

1. **RED test run exceeded the 120 s foreground limit** — Recovery: re-ran in `run_in_background`. Prevention: `ci-deploy.test.sh` is a ~5-min suite; always background it. (one-off / known)
2. **Monitor timed out at 300 s** waiting for the >5-min suite — Recovery: polled the log file directly. Prevention: for this suite, poll via `run_in_background` completion notification, not a 300 s Monitor. (one-off)
3. **Doc comment reproduced sibling regex literals** (`unauthorized|…|forbidden`, `server misbehaving`) → would trip #6400 AC3 `count==1` + T-6525-7 token count — Recovery: reworded to prose, verified with the guards' grep pre-run. Prevention: describe regex classes by name in comments; never paste the sibling's pipe-sequence near a count guard. (recurring)
4. **`[[ "${MOCK_SLEEP_NOOP:-}" == "1" ]] && create_mock_sleep` standalone under `set -euo pipefail`** aborted the whole suite when the condition was false — Recovery: changed to `if [[ … ]]; then … fi`. Prevention: never use bare `[[ ]] && cmd` as a statement in a `set -e` region. (recurring)
5. **Sandbox mutation run aborted (EXIT=2)** — the copied test resolves `DEPLOY_SCRIPT` + canary/lib siblings relative to its own dir, absent in a 2-file sandbox copy — Recovery: mutated `ci-deploy.sh` in place with a backup, restored from the backup in a separate Bash call. Prevention: to mutation-prove this file, mutate in place (backup first, restore in a separate call, run under a timeout). (recurring for this file)

## Tags
category: test-failures
module: apps/web-platform/infra
related: [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]], [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]]
