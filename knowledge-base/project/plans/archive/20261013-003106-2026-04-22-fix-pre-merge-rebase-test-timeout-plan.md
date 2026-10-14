# Plan: Fix `pre-merge-rebase.test.ts` CI timeout on gh-API Signal 3 calls

- **Issue:** #2801
- **Branch:** `feat-one-shot-2801-pre-merge-rebase-test-timeout`
- **Type:** fix (test flake)
- **Priority:** priority/p2-medium
- **Domain:** engineering

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** 5 (Research Reconciliation, Implementation Approach, Risks, Research Insights, Test Scenarios)
**Research agents used:** live verification (Bun test runner), learnings scan (5 bun-test learnings), hook argv trace, grep audit

### Key Improvements

1. **Corrected load-bearing claim:** Verified via `bun test v1.3.11` smoke test that BOTH `test(name, fn, 15000)` and `test(name, fn, { timeout: 15000 })` forms actually enforce the timeout. The original plan called the object form a "vitest-ism that won't work" — this was wrong. Either form is acceptable.
2. **Confirmed hook only needs stub for `gh issue list`:** When the test command is `gh pr merge 123 ...`, the hook extracts `PR_NUMBER=123` from argv (`pre-merge-rebase.sh:76`) and skips the `gh pr list` fallback entirely. Stub shape simplified.
3. **Added env-leak risk mitigation:** `knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md` — bun-test runs all tests in one process. `scripts/test-all.sh` uses `run_suite` per-file so cross-file leak doesn't apply, but the `GIT_ENV` constant must stay module-top-captured (already the pattern on lines 17-28).
4. **`mkdtempSync` timing precedent:** Existing `mkdtempSync` calls happen in `beforeAll` (lines 141-142), so the stub's `binDir` should follow the same lifecycle. No new pattern required.
5. **`test-review-commit`/`test-review-todos`/others are unaffected:** They pass local signal checks (todos/ or commit message) before reaching Signal 3, so the stub is never consulted. Confirms the per-test timeout raise on only the 2 named tests is the right scope.

### New Considerations Discovered

- `scripts/test-all.sh` calls `bun test test/pre-merge-rebase.test.ts` as its own `run_suite` — isolated OS process per file. Cross-file PATH leak is therefore NOT a concern. But the stub must still be cleaned up in `afterAll` so local dev machines don't accumulate `/tmp/hook-test-bin-*` dirs across `bun test --watch` runs.
- The hook's Signal 3 path ALSO runs under the local `REVIEW_COMMIT` check against `origin/main..HEAD` (line 67-68). In tests where HEAD == local main (the `main branch skips sync silently` test), the hook early-exits at line 50 — Signal 3 is never reached. Confirms only 2 tests need the stub.
- **Hook argv trace confirmed** via real shell test: `echo "gh pr merge 123 --squash --auto" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+'` → `123`. Stub only needs `gh issue list` handling for Signal-3-reachable tests.

## Overview

Two tests in `test/pre-merge-rebase.test.ts` intermittently time out at the 5000ms Bun-test default in CI while passing in ~90ms locally:

- `pre-merge-rebase hook (with git repo) > no review evidence blocks merge with deny`
- `pre-merge-rebase hook (with git repo) > detached HEAD without review evidence is denied`

Both exercise the "no review evidence" path in `.claude/hooks/pre-merge-rebase.sh`. That path falls through to **Signal 3** (lines 70-90 of the hook): it shells out to `gh pr list` and `gh issue list --label code-review --search "PR #<number>"` against the live GitHub API. The hook is *designed* to fail open on gh errors, but a slow-but-successful response (rate limit backoff, transient 503, network hop) can push the `gh` subprocess past 5s — and at that point the test has already timed out and logged `killed 1 dangling process`.

This plan removes the live-API dependency from the two failing tests by redirecting the hook's `gh` invocations to a deterministic stub on `PATH`, and — as defense-in-depth — raises the per-test Bun-test timeout on all tests that can reach Signal 3.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Reality | Plan response |
|---|---|---|
| "vitest's default 5000ms test timeout" | Tests run under **bun test** (1.3.11), not vitest. `bun test --help` confirms default is 5000ms — same number, different runner. | Plan refers to "bun test default 5000ms". Either `test(name, fn, 15000)` or `test(name, fn, { timeout: 15000 })` form works (verified via smoke test 2026-04-22 — see Research Insights). Pick whichever matches repo convention; `test/pre-merge-rebase.test.ts` currently uses no per-test timeouts. |
| Signal 3 "can take > 5s" | Hook code (lines 79-88) wraps both `gh` calls in `2>/dev/null || true` — they succeed-or-fail-open but do not have a client-side timeout. | Keep fail-open semantics. Stub the `gh` binary in tests so no wall-clock variance enters the test. |
| "hook spawns a `gh` subprocess that hangs past the timeout" | The 2-test set hits the "no review evidence" path. `no review evidence blocks merge with deny` also reaches Signal 3 today — the "Branch already up-to-date" detached test bypasses earlier guards because it is detached. | Stub `gh` for both tests; defense-in-depth raise timeout to 15000ms on the whole `describe("pre-merge-rebase hook (with git repo)", ...)` block (one-line change). |

## Hypotheses (triaged)

The issue lists three suggested fixes. Disposition:

1. **Stub the `gh` call in the test** — ACCEPT. Root-cause fix; removes wall-clock variance from the assertion path.
2. **Raise the per-test timeout to 15000ms** — ACCEPT (defense-in-depth). Even with the stub in place, a second class of flake (GitHub Actions VM CPU contention, `Bun.spawn` cold-start on first invocation) could push past 5s. 15000ms gives enough headroom without masking real regressions.
3. **Both** — THIS IS THE PLAN.

## Open Code-Review Overlap

None. Queried all 28 open `code-review`-labeled issues against `test/pre-merge-rebase.test.ts`, `.claude/hooks/pre-merge-rebase.sh`, and `scripts/test-all.sh` — zero overlap.

## Files to Edit

- `test/pre-merge-rebase.test.ts` — inject a `gh` stub via `PATH` in `beforeAll`; raise `describe`-block timeout to 15000ms; add assertion at end of the two affected tests that the stub was consulted (optional — see Test Scenarios).

## Files to Create

- None. A dedicated stub script is NOT written to disk; it is created at test time via `writeFileSync` into a tmpdir and referenced via `PATH` prefix (keeps the stub colocated with its lifecycle). This matches the repo's existing pattern of tmpdir scaffolding in the same test file (`mkdtempSync`, line 142).

## Implementation Approach

### 1. `gh` stub injection

In `beforeAll` of the `describe("pre-merge-rebase hook (with git repo)", ...)` block:

1. Create a per-suite `binDir = mkdtempSync(join(tmpdir(), "hook-test-bin-"))` (same pattern as lines 141-142).
2. Write an executable `binDir/gh` shell script. Deepen-pass finding: only the `gh issue list` invocation is reachable in these tests (the `gh pr list` fallback at `pre-merge-rebase.sh:79` is skipped because `gh pr merge 123` provides the PR number literally). Stub shape:

   ```bash
   #!/usr/bin/env bash
   # Test stub for `gh` — pre-merge-rebase.test.ts Signal 3 isolation.
   # Hook signals reachable in tests:
   #   gh issue list --label code-review --state all --search "PR #N" --limit 1 --json number --jq '...'
   # Return empty (no review issue found) → hook proceeds to deny branch.
   touch "$(dirname "$0")/.gh-called"
   case "$1 $2" in
     "issue list"|"pr list")
       # Both fail-open shapes — hook tolerates empty stdout
       exit 0
       ;;
     *)
       echo "[test stub] unexpected gh invocation: $*" >&2
       exit 0
       ;;
   esac
   ```

3. `chmodSync(ghPath, 0o755)`.
4. **PATH extension.** `GIT_ENV` is a `const` at module top (line 23) — it cannot be reassigned in `beforeAll`. Two options:
   - **Option A (preferred):** Move `GIT_ENV` construction to a `let` + lazy initializer, or use a mutable `GIT_ENV.PATH = ...` assignment (objects are mutable, `const` only pins the binding). Since `GIT_ENV` is a plain object, `(GIT_ENV as any).PATH = \`${binDir}:${cleanEnv.PATH ?? ""}\`` in `beforeAll` works.
   - **Option B (cleaner):** Redeclare `GIT_ENV` as `let` at module top, and rebuild in `beforeAll` with the stub PATH prefixed. Since module-top `GIT_ENV` is used BEFORE `beforeAll` runs (import-time only for the `cleanEnv` destructure on line 17-22, not for any spawn), either approach is equivalent in runtime behavior. Recommend Option A for minimal diff.
5. `afterAll` removes `binDir` with `rmSync(binDir, { recursive: true, force: true })`.
6. **PATH sanity assertion.** Add as first line of each of the two target tests: `expect(new TextDecoder().decode(Bun.spawnSync(["which", "gh"], { env: GIT_ENV }).stdout).trim()).toBe(\`${binDir}/gh\`);`. Fails loudly if the stub didn't win PATH resolution.

**Why PATH-stubbing not a direct JS mock:** The hook is a bash script executed via `Bun.spawn(["bash", HOOK_PATH], ...)`. JS-level mocks on the hook's `gh` invocation are not reachable — the subprocess sees only the environment and `PATH`. This is the same technique `test/x-community.test.ts:54` uses to control subprocess environment.

**Why a shell stub not a symlink to `/bin/true`:** The hook pipes `gh` output into `jq` and expects a JSON-shaped response in some paths. A stub that echoes `""` (empty string) lets `jq` parse, returns empty, and the hook treats it as "no review issue found" — the exact code path the test wants to exercise.

### 2. Per-test timeout raise

Bun-test 1.3.11 accepts **both** numeric and object forms as the third arg:

- `test(name, fn, 15000)` — numeric milliseconds (matches Bun docs at [bun.sh/docs/cli/test](https://bun.sh/docs/cli/test))
- `test(name, fn, { timeout: 15000 })` — vitest-compatible object form; Bun accepts this too

**Verification (2026-04-22):** Smoke-tested both forms against `bun 1.3.11`:

```text
$ bun test /tmp/bun-timeout-smoke2.test.ts
(fail) object-form ACTUALLY enforces timeout [101.00ms]
  ^ this test timed out after 100ms.
(fail) third-arg number ACTUALLY enforces timeout [100.00ms]
  ^ this test timed out after 100ms.
```

Both forms actually enforce the timeout — not a silent no-op. Use whichever is more readable; the numeric form is fewer characters and matches Bun docs' canonical form.

**Plan decision:** Apply `, 15000` (numeric form) as the third arg to ONLY the two tests named in the issue. Broader application risks masking a real 5s slowdown in a test that currently finishes in 90ms.

### 3. Optional: assert stub was consulted

Not necessary for GREEN, but cheap insurance against a future PATH regression: the stub can `touch "$binDir/.gh-called"` before exiting, and the test can assert the sentinel exists. Recommend ADD — cost is one line each side, benefit is a sharp signal if CI's `gh` wins PATH resolution vs. the stub.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `bash scripts/test-all.sh` passes on this branch (all suites). Verified: 22/22 suites passed.
- [x] `bun test test/pre-merge-rebase.test.ts` passes locally in < 5s total (no regression to the remaining 19 tests). Verified: 21 pass / 0 fail, 3.09s.
- [x] The two target tests complete in < 500ms each when the stub is active (measured via bun test's per-test output). Observed at RED: 125ms + 115ms; GREEN removes only the assertion overhead.
- [x] The `.gh-called` sentinel file (if implemented) is present after each of the two target tests runs, proving the hook's Signal 3 path reached the stub. Verified: both tests assert `existsSync(ghCalledSentinel)` post-run.
- [x] `rg "import.*vitest|require\(['\"]vitest" test/pre-merge-rebase.test.ts` returns zero — the file must continue to import exclusively from `bun:test` (line 1). (Object-form `{ timeout: N }` is a *valid* bun-test form per 2026-04-22 smoke test — not banned.)
- [x] `test/pre-merge-rebase.test.ts` still imports from `"bun:test"` (not `"vitest"`) — grep confirms.

### Post-merge (operator)

- [ ] After merge, verify CI run green on main. Target: five consecutive green runs of `test/pre-merge-rebase` suite across the next ~5 merges (or ~24h of main-branch activity, whichever arrives first).
- [ ] If any of the five runs fail with the same `test timed out after 5000ms` pattern in these two tests, re-open #2801 with the new CI run URL.

## Test Scenarios

Write the assertion changes BEFORE the implementation (per `cq-write-failing-tests-before`). Order:

1. **RED step 1:** Add a `beforeAll` that writes a `gh` stub that does **nothing** (echoes empty, exits 0). Add the `PATH` extension. Confirm the 2 target tests still pass — they should, since the stub mimics the "no review found" response the hook's fail-open path already produces on gh errors. If they fail, the stub shape is wrong — fix before proceeding.
2. **RED step 2 (optional):** Add the sentinel-file assertion to the 2 target tests. Run — it should FAIL because the stub doesn't yet `touch` the sentinel.
3. **GREEN:** Add `touch "$binDir/.gh-called"` to the stub. Re-run — sentinel assertion passes.
4. **REFACTOR:** Raise per-test timeout to 15000ms on the 2 tests. Verify with `bun test test/pre-merge-rebase.test.ts --timeout=1` that **only** those 2 tests have their own timeout (the global 1ms flag should fail the other 19 tests; the 2 covered tests should pass because their inline timeout overrides the CLI flag).

**Edge cases to cover:**

- Stub is still on PATH in the `main branch skips sync silently` test — harmless, hook never reaches Signal 3 from main.
- Stub must not shadow `gh` for OTHER `Bun.spawnSync` calls inside test helpers. Verify: `grep -n 'gh ' test/pre-merge-rebase.test.ts` — returns zero non-hook invocations today, so the PATH-prefix approach is safe.
- The `afterAll` must `rmSync(binDir, { recursive: true, force: true })` to avoid tmpdir leak across repeated local runs.

## Risks

- **Bun-test timeout arg shape.** ~~Verified via smoke test~~ (see Research Insights). Risk class matches `cq-abort-signal-timeout-vs-fake-timers` and `cq-test-mocked-module-constant-import` — the verify-runner-mechanics-first discipline is still important, but this specific concern is now closed. Implementer does NOT need to re-smoke-test.
- **PATH resolution on CI.** Ubuntu-latest runners resolve `gh` from `/usr/local/bin/gh`. Prefixing `PATH` with `${binDir}:` puts the stub first. Sanity-check at work-skill time: `Bun.spawnSync(["which", "gh"], { env: GIT_ENV })` should return `${binDir}/gh` before any test runs. Add a one-line assertion in `beforeAll` to guarantee this: `expect(new TextDecoder().decode(Bun.spawnSync(["which", "gh"], { env: GIT_ENV }).stdout).trim()).toBe(\`${binDir}/gh\`);`.
- **Env-var leak across bun-test files (mitigated by `scripts/test-all.sh`).** Per `knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md`, bun-test runs all files in one process. BUT `scripts/test-all.sh` uses `run_suite` → `bun test <one-file>` per suite — separate OS process per file. The PATH mutation in `GIT_ENV` is scoped to this file's `Bun.spawn` calls, not to `process.env`, so there is no cross-file leak vector. `GIT_ENV` is already module-top-captured (lines 17-28) — keep that pattern.
- **tmpdir accumulation on local `bun test --watch`.** `afterAll` must `rmSync(binDir, { recursive: true, force: true })`. Matches the existing `afterAll` pattern on lines 162-165.
- **Silent stub drift.** If the hook gains a new `gh` invocation shape (say, `gh api graphql ...`), the stub's default-exit-0-empty response may mask a real bug. Mitigation: the stub's "any other invocation" branch writes a warning line to stderr like `[test stub] unexpected gh invocation: $*` — doesn't fail the test, but makes the drift visible in test output.
- **The "killed 1 dangling process" message.** Issue says "Both log `killed 1 dangling process`". That message comes from Bun-test's post-timeout cleanup of the `gh` subprocess. After this fix, the message should NOT appear for these two tests. If it recurs on a different test, that's a new issue — not covered here.
- **No change to the hook itself.** The hook's fail-open semantics on `gh` errors are correct; the flake is test-side. Tempting alternative — "add a client-side timeout to the hook's `gh` calls" (e.g., `timeout 3 gh ...`) — is NOT taken because: (a) it regresses hook behavior for real users who DO want Signal 3 to work (slow-but-successful responses become spurious denies); (b) hook is battle-tested and not in scope; (c) test-side stub is the minimal fix.
- **Shared bare remote ordering dependency.** Per `knowledge-base/project/learnings/test-failures/2026-04-07-shared-bare-remote-ordering-dependency.md` and the existing `beforeEach` (lines 167-194), tests share the same `remoteDir` and must reset `refs/heads/main` to `initialMainSha` between cases. The stub's `binDir` is fresh per suite and outside the git repos, so it cannot interact with the bare-repo reset logic. No additional cleanup needed.

## Non-Goals

- Reworking the review-evidence gate or hook logic.
- Adding a generic gh-stub helper for other test files. `test/x-community.test.ts` and `test/content-publisher.test.ts` have their own env-isolation patterns; unifying is a separate refactor.
- Changing Bun-test configuration or runner orchestration in `scripts/test-all.sh`.
- Filing a tracking issue for the "gh stub helper" idea — see Non-Goal 2 above. If this pattern recurs, a follow-up refactor issue is warranted at that point.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Raise timeout only (no stub) | Treats symptom. Live-API call is still there; next slow response pushes past 15s. |
| Stub only (no timeout raise) | Leaves no headroom for `Bun.spawn` cold-start on CI first-run. Defense-in-depth cheap. |
| Add client-side `timeout 3 gh ...` in the hook | Changes hook behavior for real users; Signal 3 fails more often in the field. |
| Rewrite the test to call hook-internal functions directly (unit-style) | Hook is a bash script with no sourceable function boundary. Out of scope. |
| Skip the two tests in CI only | Masks the flake. Kills the only CI coverage of Signal 3. |
| Replace `gh` with a GraphQL-stub HTTP server | Over-engineered for two tests. The stub-on-PATH form is ~20 lines. |

## Research Insights

### Runner Verification (2026-04-22)

- **Bun version pinned:** `.bun-version` → `1.3.11`. `bun --version` → `1.3.11`. Matches pin.

- **Bun-test default timeout:** `bun test --help` → `--timeout=<val>  Set the per-test timeout in milliseconds, default is 5000.` Confirmed.

- **Timeout arg forms (both work):** Smoke-tested against `bun 1.3.11`:

  ```ts
  // Both forms DID time out at 100ms when the test sleeps 200ms:
  test("third-arg number ACTUALLY enforces timeout", async () => {
    await Bun.sleep(200); expect(1).toBe(1);
  }, 100);
  test("object-form ACTUALLY enforces timeout", async () => {
    await Bun.sleep(200); expect(1).toBe(1);
  }, { timeout: 100 } as any);
  ```

  ```text
  (fail) object-form ACTUALLY enforces timeout [101.00ms]
    ^ this test timed out after 100ms.
  (fail) third-arg number ACTUALLY enforces timeout [100.00ms]
    ^ this test timed out after 100ms.
  ```

  Either form is valid bun-test syntax. The initial plan claim that the object form is a "vitest-ism that won't work" was wrong. Bun accepts both.

### Hook Behavior Verification

- **PR number extraction from argv:** `echo "gh pr merge 123 --squash --auto" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+'` → `123`. Because the test always invokes `gh pr merge 123 ...` (literal PR number), the hook takes the short path at `pre-merge-rebase.sh:76`: `PR_NUMBER=123` is set directly, and the `gh pr list` fallback at line 79 is **NEVER** executed. **Conclusion:** The stub only needs to handle `gh issue list` — the `gh pr list` branch is dead code for this test file.

- **Signal 3 reached only when Signals 1+2 are empty:** `pre-merge-rebase.sh:74` gates the `gh` calls behind `[[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]`. Tests that `addReviewEvidence(repoDir)` (creating `todos/review-finding.md` with `tags: code-review`) make `REVIEW_TODOS` non-empty, short-circuiting Signal 3. Only two tests don't set up review evidence: the two named in the issue. Stub scope confirmed at exactly 2 tests.

- **Hook Signal 3 invocation shapes:**
  - `gh pr list --repo <owner/repo> --head <branch> --state open --json number --jq '.[0].number // empty'` — **not reached** when `gh pr merge <N>` includes a literal PR number.
  - `gh issue list --label code-review --state all --search "\"PR #${PR_NUMBER}\"" --limit 1 --json number --jq '.[0].number // empty'` — the ONLY call the stub must handle.

### Repo Precedent

- **Existing PATH handling in this repo:** `test/x-community.test.ts:31,54` uses `env.PATH` passthrough. My plan adds PATH **prefix-extension**, which is similar but new to `pre-merge-rebase.test.ts`. The `GIT_ENV` constant on lines 17-28 is already module-top-captured and includes `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_GLOBAL`, `GIT_CEILING_DIRECTORIES` — adding `PATH: \`${binDir}:${cleanEnv.PATH ?? ""}\`` fits the same shape.

- **`mkdtempSync` precedent:** `beforeAll` at lines 141-142 already creates two tmpdirs (`hook-test-remote-`, `hook-test-local-`). Adding `hook-test-bin-` follows the same convention; the `afterAll` at line 162-165 already demonstrates the cleanup pattern.

### CI Behavior

- **`.github/workflows/ci.yml`** runs `bash scripts/test-all.sh` with `GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` set. This is why `gh` in the hook reaches the GitHub API on CI — authenticated calls are subject to primary/secondary rate limiting. The Soleur org's concurrent CI runs share a rate-limit budget, stretching response time for any single `gh` invocation. Local runs either lack `GITHUB_TOKEN` entirely or use the developer's PAT — both also reach the API, which is why `bun test` in isolation CAN reproduce the flake on slow links (just less frequently than CI).

- **`scripts/test-all.sh` isolation:** Each `run_suite` invocation spawns a new `bun test <file>` process (line-by-line). Env-var leaks across test files (per `2026-04-18-bun-test-env-var-leak-across-files-single-process.md`) do NOT apply between suites because the OS process resets. Leaks *within* a single file (e.g., between two tests in this file) still apply — but the stub's PATH is constant for the whole file, so no intra-file leak risk either.

### Applicable Learnings

- `knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md` — **Review before implementation.** Establishes the pattern of module-top env capture + afterEach restore. The fix here modifies `GIT_ENV` (a module-top `const`) by appending `PATH`, NOT `process.env` — lower-risk path.
- `knowledge-base/project/learnings/test-failures/2026-04-07-shared-bare-remote-ordering-dependency.md` — Documents the `beforeEach` reset pattern already in place (lines 167-194). Stub doesn't touch git state.
- `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` — Explains per-file `run_suite` orchestration. Relevant because the fix must not assume cross-file state; confirmed it doesn't.
- `knowledge-base/project/learnings/test-failures/2026-03-18-bun-test-segfault-missing-deps.md` — Not directly applicable; no new deps added.
- `knowledge-base/project/learnings/test-failures/2026-04-05-bun-test-dom-failures-dual-runner-exclusion.md` — Not applicable; no DOM or dual-runner concern.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (test-only fix). Engineering domain (CTO) is implicit in the `domain/engineering` label on the issue; no additional domain leader invocation needed because:

- No product surface, no user-facing copy, no brand or conversion concern.
- No new dependency, no new infra, no Terraform touch.
- No security boundary — the hook's fail-open semantics are unchanged.

## PR Reminder

PR body MUST include `Closes #2801` (per `wg-use-closes-n-in-pr-body-not-title-to`).

Use `/ship` to commit + push + open PR. Apply the `priority/p2-medium` and `type/chore` labels from the source issue.
