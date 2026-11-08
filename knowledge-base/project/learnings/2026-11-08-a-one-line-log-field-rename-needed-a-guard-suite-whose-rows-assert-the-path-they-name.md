# Learning: a one-line log-field rename shipped a guard suite whose rows asserted their labels, not their paths

## Problem

Epic 9601 slice 2 replaced the raw conversation id on the `untrusted-classify` WARN line with a pepper-keyed
`sessionIdHash` (one line in `emit()`). The production change was correct first time. The 13-seat review panel
then found seven P2s, all in the verification I had written around it, not in the line itself:

- A six-row table-driven suite (one row per emit path) asserted only the row's label. Retuning `SCORE_MAX_CHARS`,
  the flag threshold, or `normalize` left rows green while silently moving them onto another path.
- The real-logger case stubbed `LOG_LEVEL=silent` after the logger module was already cached. In a full run the stub
  was a no-op; run alone, pino made `warn` a no-op and the case failed. Its comment claimed the opposite.
- A trimmed assertion left `workspaceIdHash` unpinned: copying `hashUserId(ctx.sessionId)` onto the neighbouring
  field stayed 80/80 green.
- The lookup docs described the recipe in prose, omitted the existing hash helper, and left the userid-recovery
  runbook's `jq` filter without the new key (its own contract says a new 64-hex emission must join the `or` chain).

## Solution

- Give every table row an `expect` object (`flagged`, `truncated`, `unscored`, `unscoredReason`) and assert it in the
  driver, so a row cannot drift onto another path while keeping its label.
- Count rows at COLLECTION time (`registered += 1` inside the loop) and assert `registered === rows * states` in a
  precondition test, so a neutered loop is red even though a loop that registers nothing registers no failures.
- Pin the neighbouring field to its own oracle and assert it differs from the new one.
- Clear ambient `LOG_LEVEL` / `SENTRY_BREADCRUMB_LEVEL` in `vi.hoisted` before the logger loads; run each new case
  alone (`-t`) and under `CI=1` / `SOLEUR_SUBAGENT=1`.
- Do not mock a module whose module-load environment the test must re-read: a `vi.mock` factory's result is cached
  across `vi.resetModules()`, so a pepper-at-load test saw `pepper_unset` for every case until the mock was removed.
- Unpack `Error` (`message`, `stack`, `cause`) in the sink scan: `JSON.stringify` renders an Error as `{}`.
- Prove each new guard by a mutation that reds it, and one pair that shows the unpacker is load-bearing (leak alone
  is red, leak plus unpacker dropped is green).

## Key Insight

A table-driven suite's per-row name is a claim; the row must assert the shape that makes the claim true, or a later
retuning moves the row without anyone noticing. And any test that depends on a value read once at module load
(pepper, log level) must clear the ambient environment in `vi.hoisted` and avoid mocking that module.

## Session Errors

1. **`cd ..` from `apps/web-platform` landed in `apps/`, so `scripts/markdown-lint.sh` was not found (exit 127).** Recovery: ran from the worktree root. **Prevention:** start every Bash call with an absolute `cd` to the worktree root; never rely on `cd ..`.
2. **Mutation row M2 edited the first `256 * 1024`, which is `ENVELOPE_MAX_CHARS`, not `SCORE_MAX_CHARS`, and "survived".** Recovery: re-ran against the full declaration line. **Prevention:** anchor a mutation on the whole declaration or call and print the changed line, not the first numeric literal.
3. **`drive(mod, p, sessionId = SESSION_ID)`: an explicit `undefined` took the default.** Recovery: `"sessionId" in opts`. **Prevention:** never use a default parameter where `undefined` is a meaningful caller value.
4. **Real-logger test stubbed `LOG_LEVEL` after the logger was cached (no-op in a full run, failed alone).** Recovery: clear the env in `vi.hoisted`. **Prevention:** run each new test alone with `-t` before trusting a full-file green.
5. **Mocked `@/server/observability`; its factory result is cached across `vi.resetModules`, so every pepper-set case saw `pepper_unset`.** Recovery: dropped the mock and observed Sentry through its own spies. **Prevention:** do not mock a module whose load-time env the test re-reads.
6. **The wiring test read `log.warn.mock.calls[0]`, which was an earlier test's line.** Recovery: `mockClear()` before the call. **Prevention:** clear the spy immediately before the action under test.
7. **Table rows asserted labels, not shape (panel P2).** Recovery: per-row `expect`. **Prevention:** for any table-driven guard, name the edit that moves a row onto another path and say which assertion reds.
8. **Working directory drifted to the bare root twice.** Recovery: re-entered the worktree each call. **Prevention:** as in 1.

## Tags
category: test-failures
module: apps/web-platform/server/untrusted-content
