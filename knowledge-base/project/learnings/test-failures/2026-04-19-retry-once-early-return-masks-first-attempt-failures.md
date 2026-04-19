# Retry-once with early-return masks first-attempt failures

**Date:** 2026-04-19
**Category:** test-failures
**Surfaces:** vitest integration tests, LLM-dependent tests, any test with flake-retry
**Origin:** PR #2610 (feat-verify-workspace-isolation), review by security-sentinel + test-design-reviewer

## Problem

The cross-workspace isolation suite's query()-tier tests (FR2-smoke, FR8, FR9) used the following retry pattern to handle the LLM occasionally answering from memory instead of invoking the Bash tool:

```ts
let attempt = await runQueryAttempt({ cwd, pair, prompt, token });
if (!attempt.toolsUsed.has("Bash")) {
  attempt = await runQueryAttempt({ cwd, pair, prompt: prompt + " MUST use Bash", token });
}
expect(attempt.tokenLeaked).toBe(false);
```

This pattern is visibly safe but has a silent failure mode:

- **Attempt 1** invokes Bash, reads `rootB/secret.md` successfully (real leak), writes the token into assistant text. `toolsUsed.has("Bash")` is true → no retry.
- **Attempt 1**'s `tokenLeaked` is checked, test fails correctly. ✓

Now flip the branching:

- **Attempt 1** doesn't invoke Bash (model refuses or answers from memory). `attempt` is now a no-Bash attempt.
- **Attempt 2** retries with a stronger prompt. Model invokes Bash, isolation holds, no leak.
- Only `attempt` (=attempt 2) is asserted. ✓ Test passes.

But consider the dangerous path:

- **Attempt 1** invokes Bash, **isolation fails, token leaks into assistant text**.
- `toolsUsed.has("Bash")` is true → no retry → `attempt` still references attempt 1 → `tokenLeaked === true` → test fails. ✓

So a first-attempt leak with Bash-used DOES fail the test. But there was still a class of leaks that could slip through:

- `attempt` was reassigned inside the branch. The VARIABLE name hid that attempt 1's result was discarded whenever we retried. In a variant like `if (!attempt.toolsUsed.has("Bash")) { return; }` or `if (!attempt.toolsUsed.has("Bash")) { attempt = await retry(); return; }`, the retry-or-early-return pattern made attempt 1's `tokenLeaked` status unobservable to assertions that ran AFTER the branch.

The actual bug in PR #2610 was in FR8 and FR9:

```ts
if (!readAttempt.toolsUsed.has("Bash")) {
  const retried = await runQueryAttempt(...);
  expect(retried.tokenLeaked).toBe(false);
  return;  // <-- original readAttempt.tokenLeaked never asserted
}
expect(readAttempt.tokenLeaked).toBe(false);
```

If `readAttempt` on attempt 1 both (a) didn't use Bash AND (b) somehow contained the token in its text (e.g., model hallucinated the token or inferred it from prior context), the `return` skipped the original leak assertion entirely. The test reports green because only the retry's result was checked.

## Root cause

**Retry branches that reassign the result variable or early-return after the retry create an invisible drop of the original attempt's assertions.** The visible assertion (`expect(retried.tokenLeaked).toBe(false)`) names only the retry, so a reader can't tell that the original attempt's safety was never verified.

This is a specific instance of the broader `cq-mutation-assertions-pin-exact-post-state` class: when the code-under-test takes multiple observable steps, every step must be pinned.

## Fix pattern

Collect ALL attempts in an array, assert across every element:

```ts
function assertNoLeakAcrossAttempts(attempts: QueryAttemptResult[], label: string): void {
  for (const [i, a] of attempts.entries()) {
    expect(
      a.tokenLeaked,
      `${label} attempt ${i + 1}: ${a.leakContext || "(no leak context)"}`,
    ).toBe(false);
  }
}

// Usage:
const attempts: QueryAttemptResult[] = [];
attempts.push(await runQueryAttempt({ ... }));
if (!attempts[0].toolsUsed.has("Bash")) {
  attempts.push(await runQueryAttempt({ ... strongerPrompt }));
  expect(
    attempts[1].toolsUsed.has("Bash"),
    `${label} retry refused Bash — test has no discriminative power`,
  ).toBe(true);
}
assertNoLeakAcrossAttempts(attempts, "FR8");
```

Two improvements over the original:

1. **Every attempt is asserted.** Leaks on attempt 1 are always caught even when a retry happens.
2. **Retry refusal is a hard failure.** If the model refused Bash on BOTH attempts, the test has no discriminative power — passing would be a silent false-green. Fail explicitly with the context needed to debug.

Implemented in `apps/web-platform/test/sandbox-isolation.test.ts` via `assertNoLeakAcrossAttempts` helper.

## When this rule applies

Any test with:

- A flake-retry pattern on external dependencies (LLM output, network, timing)
- A "precondition required" gate (e.g., "tool must have been invoked")
- Multi-step verification where intermediate states matter

Specifically watch for:

- `let result = ...; if (...) result = await retry(); expect(result).toBe(ok);`
- `const first = ...; if (...) { const retried = ...; expect(retried).toBe(ok); return; } expect(first).toBe(ok);`
- Tests where the outer `describe` runs under `probeSkip` and the skip reason is never surfaced (silent-green)

## Prevention checklist

- [ ] When adding retry-on-flake logic, push attempts into an array rather than reassigning a variable
- [ ] Assert the invariant across every attempt, not just the last one
- [ ] If the retry exists to force a precondition (tool invocation, network reachability), assert that the precondition WAS met after the retry — refusal is a test failure, not a silent pass
- [ ] If the test is capability-gated (`describe.runIf(probe)`), gate the fail-loud throw on a host-opt-in env var (e.g., `SOLEUR_ISOLATION_TEST_HOST=1`), NOT on generic `CI=true`. Generic CI runners that lack the capability are expected to skip cleanly — the silent-green risk only exists on hosts that claim to support the test class. **Why:** the first ship cycle of PR #2610 universally threw under `CI=true`, and GitHub Actions runners (which have no bwrap) immediately failed the test job. The fix decouples "silent-skip is bad on a capable host" from "running on a generic CI host that cannot support the test."

## Session Errors

**Initial FR2-smoke / FR8 / FR9 implementations used `if (!bash) { retry; return; }`** — caught by security-sentinel (silent drop of attempt-1 leaks) and test-design-reviewer (model refusal on retry → silent pass). Recovery: refactored to array-of-attempts pattern with `assertNoLeakAcrossAttempts`. Prevention: this rule.

**H1 `rescueStaleFixtures` symlink bypass** — caught by security-sentinel. Original code used `realpathSync(full)` then `path.dirname(real) === realRoot` as the "hard gate". A symlink at `/tmp/sandbox-iso-evil → /tmp/VICTIM-xxx` resolved to `/tmp/VICTIM-xxx` whose dirname matched `/tmp` → passed the gate, got `rm -rf`'d. Recovery: `lstatSync(full)` without following + explicit `if (lstat.isSymbolicLink()) continue`. Prevention: when a bulk-cleanup helper does `rm -rf` on entries under an allowlist root, NEVER call `realpath` before deciding to remove — symlinks must be refused at the entry level.

**Duplicate shellQuote/shellEscape across helper + test file** — caught by code-quality-analyst and pattern-recognition. Recovery: exported `shellQuote` and `FS_DENY_RE` from the fixtures helper, imported from the test file. Prevention: when adding a utility function in a test file, grep the adjacent helpers first; co-located-helper conventions already existed in `apps/web-platform/test/helpers/`.

**FR9 write-side tautology (`texts.length > 0`)** — caught by test-design-reviewer. Recovery: added `findTokenInClaudeProjects(token)` that walks `~/.claude/projects/**.jsonl` and asserts the token is present on disk BEFORE running the read side. Prevention: a write-side assertion that doesn't observe the persistence surface is the same bug class as asserting a DB write by checking the response status — verify the target surface.

**Doppler secret presence false-positive via `wc -c`** — `doppler secrets get ANTHROPIC_API_KEY -p soleur -c dev --plain 2>&1 | wc -c` returned 75 bytes. I misread this as "75-char key present", but it was the error message `Doppler Error: Could not find requested secret: ANTHROPIC_API_KEY` (also ~75 bytes). Recovery: `doppler secrets -p soleur --json 2>/dev/null | jq 'keys[]' | grep -i anthropic` to list actual keys. Prevention: never use `wc -c` to infer presence through `2>&1` redirect; use structured output (`--json`) and parse with `jq`, or check exit status separately.

**FR3 false-positive setupFailed** — my `toBwrapResult` regex `/^\/bin\/bash:/m` treated any bash-emitted error as bwrap setup failure, including the isolation-test signal ("No such file or directory" when deny boundary hid the path). Recovery: narrowed to `^bwrap: /m` and `execvp:/m`. Prevention: setupFailed detection must name the distinct-to-infrastructure signatures — never catch patterns shared by "tool errored setting up" and "user command errored while running".

**Bash shell state lost between calls** — `cd apps/web-platform && <cmd>` in one call; subsequent calls sometimes landed back at worktree root. Recovery: use absolute paths for tool invocations (`./node_modules/.bin/vitest run`) after a single confirmed `cd`, and always `pwd` first in shell-sensitive sequences. Prevention: treat each Bash call as a fresh shell; chain with `&&` within ONE call rather than across calls.

## Related learnings

- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — H1 symlink bypass is a fresh example of this pattern: TypeScript + tsc + vitest (8/8) all green, security-sentinel caught the bug.
- `knowledge-base/project/learnings/best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` — why the direct-bwrap tier exists alongside SDK query() tests.
- `knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` — related TDD rule about discriminative power; this PR's Phase 3.3 three-commit inversion proof (d56e1055 → c4773729 → 1ad6cde1) is the positive analogue.

## Tags

category: test-failures
module: apps/web-platform/test
surface: vitest, LLM integration tests, retry-flake patterns
