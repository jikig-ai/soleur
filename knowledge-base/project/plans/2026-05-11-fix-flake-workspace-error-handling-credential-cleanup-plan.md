---
title: "fix: deflake workspace-error-handling 'cleans up credential helper' test"
issue: 3597
branch: feat-one-shot-fix-flake-workspace-error-handling-3597
type: bug
classification: test-flake-remediation
created: 2026-05-11
requires_cpo_signoff: false
---

# fix: deflake workspace-error-handling 'cleans up credential helper' test (#3597)

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Implementation, Risks, Test Strategy, Acceptance Criteria, Sharp Edges
**Research agents / sources used:** Context7 (`/vitest-dev/vitest`), WebSearch (vitest flake patterns 2025-2026), `repo-research-analyst`-equivalent grep over `apps/web-platform/test/git-auth.test.ts` + `apps/web-platform/server/{workspace.ts,git-auth.ts}`, `learnings-researcher`-equivalent scan of `knowledge-base/project/learnings/` (4 directly applicable learnings found: `2026-05-07-vitest-domock-factory-throw-wrapped-message.md`, `2026-04-23-git-askpass-over-shell-helper-for-headless-auth.md`, `2026-04-18-extraction-di-boundaries-and-mock-cascade.md`, `2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`).

### Key Improvements

1. **Adopted the canonical in-repo askpass-cleanup test pattern (`git-auth.test.ts:223-244`) instead of the readdir-snapshot proposal.** The repo already has a battle-tested assertion shape: capture the `GIT_ASKPASS` env var off the `execFile` mock's `opts.env`, then `expect(existsSync(capturedAskpassPath)).toBe(false)` after the rejected promise settles. This is byte-equivalent in semantic to the readdir-delta approach but is (a) tightly scoped to *this test run's* askpass file (no `/tmp` race surface), (b) does not need to re-implement `getAskpassDir`'s heuristic, and (c) eliminates risk R1 and R3 entirely.
2. **Risk-class corrected** — the original deepen-plan candidate (readdirSync delta) carried two false risks (R1 dir-heuristic divergence, R3 `$HOME` writeability) that vanish under the env-capture pattern. Risk section rewritten.
3. **Verified `vitest.config.ts` unit project does NOT enable `isolate: true`** (line 17-21). Cross-test module-graph leakage is real but the existing `beforeEach { vi.resetModules() }` (line 17-19) + `afterEach { vi.restoreAllMocks(); vi.doUnmock("child_process"); vi.doUnmock("../server/github-app") }` (line 21-30) covers all mock surfaces this test installs. No additional cleanup needed.
4. **Issue #2848 already tracks the `randomCredentialPath` deprecated-export sweep** (still open) — confirms keeping the harmless mock stub in this test is the correct scope-out decision.
5. **Recommendation gate:** the existing canonical pattern in `git-auth.test.ts:223-244` is `existsSync(capturedAskpassPath)` — the deepen-pass aligns test #3 to that exact shape, lowering reviewer cognitive load (one pattern, two test files) and eliminating the small noise-window of the readdir-snapshot approach.

### New Considerations Discovered

- **`vi.doMock` factory throws are vitest-wrapped (learning `2026-05-07-vitest-domock-factory-throw-wrapped-message.md`).** Informational — this plan does NOT throw from a factory; the mock injects errors via the execFile callback path, which is unaffected by the wrapper. No remediation needed, but a `// NOT a factory throw — error injected via callback` comment in the test next to the mock keeps the trade-off visible to future maintainers.
- **Vitest v3.1.2+/v4 has a documented uptick in CI timeout flakes** (vitest issues #7871, #8559, #8766). The fix here removes the network dependency entirely; even on the worst-affected vitest version the deterministic test should run in <100ms. No vitest pin recommended.
- **Mock-cascade hygiene (learning `2026-04-18-extraction-di-boundaries-and-mock-cascade.md`).** When `vi.doMock("child_process", () => …)` returns a wholesale shape that omits `execFile`, the SUT's top-level `promisify(execFile)` at `git-auth.ts:30` crashes at module load with `No "execFile" export is defined on the "child_process" mock`. The deepened skeleton in Phase 1 below uses `vi.importActual` + spread (matching the canonical pattern in test #2 and `git-auth.test.ts:33-58`) so the SUT's growing import surface never breaks this test.
- **Web-platform vitest config does NOT set a `testTimeout` override** (`vitest.config.ts:11-45`). Per vitest issue #8559, even if the unit project did set a custom `testTimeout`, the value would NOT propagate from root → project. After the fix, no per-test or per-project override is needed.

### Sources

- [Vitest docs — vi.doMock & resetModules (Context7)](https://github.com/vitest-dev/vitest/blob/main/docs/api/vi.md)
- [Vitest issue #8559 — testTimeout doesn't propagate to projects](https://github.com/vitest-dev/vitest/issues/8559)
- [Vitest issue #8766 — v4 pool timeout regression](https://github.com/vitest-dev/vitest/issues/8766)
- [Vitest issue #7871 — flaky userEvent timeouts (v3.1.2+)](https://github.com/vitest-dev/vitest/issues/7871)
- [LogRocket — Advanced guide to Vitest mocking](https://blog.logrocket.com/advanced-guide-vitest-testing-mocking/)
- In-repo canonical pattern: `apps/web-platform/test/git-auth.test.ts:223-244`
- In-repo deferred cleanup: `gh issue view 2848` (`randomCredentialPath` test-mock sweep, still open)

## Overview

The vitest case `provisionWorkspaceWithRepo error wrapping > cleans up credential helper even when clone fails` (in `apps/web-platform/test/workspace-error-handling.test.ts:101`) intermittently exceeds vitest's 5s default ceiling on CI (PR #3589 run 25675305009, 1/372 files failed). The flake is real-network: unlike sibling test #2 at line 50, this case does NOT mock the subprocess module, so the production `gitWithInstallationAuth` actually invokes `git clone https://github.com/nonexistent/fake-repo-xxx` and waits on DNS + TCP + HTTP-404 against github.com. On contended CI runners that round trip can blow past 5s.

The fix mirrors test #2's deterministic pattern (mock the subprocess `execFile` to inject a clone failure with realistic stderr) AND retargets the cleanup assertion onto the *actually* load-bearing artifact -- the **askpass script** in `apps/web-platform/server/git-auth.ts:90-97`. The test's current assertion (`existsSync(credPath)` against `randomCredentialPath()`-supplied paths) is vacuously true: `randomCredentialPath` is deprecated (`github-app.ts:483-491`, "No prod call sites after the GIT_ASKPASS migration") and that path is never created in production. The test as written validates nothing about credential cleanup.

### Research Insights

**Canonical in-repo pattern (load-bearing finding):** `apps/web-platform/test/git-auth.test.ts:223-244` already implements the assertion contract this plan needs ("cleans up askpass script even when git fails"). The shape: declare `let capturedAskpassPath: string | undefined;` in the test scope, capture `opts?.env?.GIT_ASKPASS` inside the `execFile` mock implementation at the moment the SUT invokes git, then assert `existsSync(capturedAskpassPath!)` is `false` after the rejected promise settles. Adopting it verbatim (a) removes the need to re-implement `getAskpassDir`, (b) is scoped to *this test run's* askpass file with zero `/tmp` race surface, (c) matches the established codebase convention so reviewers do not have to learn a second pattern.

**Vitest `vi.doMock` semantics (Context7 + docs).** `vi.doMock` is NOT hoisted (unlike `vi.mock`); it affects only the *next* dynamic `import()` after the doMock call. Static `import` at the top of a test file is hoisted to module-init and will NEVER see a `doMock`. The Phase 1 skeleton uses `await import("../server/workspace")` AFTER both `doMock` blocks -- this is mandatory.

**Mock-cascade defense (learning `2026-04-18-extraction-di-boundaries-and-mock-cascade.md`).** Wholesale `vi.doMock("child_process", () => ({ execFile: ... }))` factories that omit real exports crash at SUT load with `No "execFile" export is defined on the "child_process" mock` whenever the SUT's import surface grows. The Phase 1 skeleton uses `vi.importActual<typeof import("child_process")>("child_process")` + spread (matching `git-auth.test.ts:33-58`) so the mock survives future imports added to `git-auth.ts` (e.g., a hypothetical future `import { spawn } from "child_process"`).

**Factory-throw wrapper class (learning `2026-05-07-vitest-domock-factory-throw-wrapped-message.md`).** Informational only -- the Phase 1 skeleton injects errors via the `execFile` *callback*, not by throwing from the factory. A `// NOT a factory throw -- error injected via callback` inline comment makes the choice visible so a future maintainer does not "simplify" the test into the wrapper-message-swallowing trap.

**Vitest v3.1.2+/v4 CI flake regression** (vitest issues #7871, #8559, #8766). Documented uptick in 5000ms-timeout flakes on contended CI runners since v3.1.2 / v4 pool changes. The determinism fix here is version-independent; no `testTimeout` override is needed.

**Deferred cleanup (issue #2848, still open).** The `randomCredentialPath` test-mock stub across 6 files (this one + 5 others) is already tracked for mechanical sweep. Removing only this test's stub mid-flake-fix would create asymmetric file state. Keep the stub; let #2848 land the sweep.

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing impact. The change is test-only -- production `provisionWorkspaceWithRepo` is not modified. A broken landing means the flake persists, blocking PR merges intermittently (developer-friction class).

**If this leaks, the user's data/workflow/money is exposed via:** N/A. Test code is not shipped to production. No regulated-data surface is touched.

**Brand-survival threshold:** none

Threshold `none` justification: this is a test-flake fix on a test file. The production code (`workspace.ts`, `git-auth.ts`) is read-only context. No sensitive path is modified (no `app/api`, no schema, no auth flow, no `.sql`). Preflight Check 6 will pass on `diff scope = test-only`.

## Research Reconciliation -- Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Sets up a vi.doMock of `../server/github-app` ... asserts the credential helper file is removed" | Confirmed at `test/workspace-error-handling.test.ts:103-117`. The asserted path comes from the **mocked** `randomCredentialPath` -- a path the test itself fabricated. | Replace assertion with one against the askpass script path in `$HOME`/`/tmp` (the real cleanup artifact). |
| "Test does several fs ops + a mocked subprocess" | Half-true. `vi.doMock("../server/github-app", ...)` is set, but the subprocess module is **NOT** mocked in test #3 (it IS mocked in test #2 at line 61). So `gitWithInstallationAuth` runs a **real** `git clone` against github.com. | Mirror test #2: add `vi.doMock` for the subprocess module that injects a deterministic clone failure with stderr buffer. |
| "5s vitest default timeout is tight when CI's I/O contention spikes" | Confirmed against `apps/web-platform/vitest.config.ts:7-45` (no `testTimeout` override, so vitest default 5000ms applies). | After determinism fix, no timeout bump is needed. If schedule pressure forces a smaller-scope fix, the fallback is `test("...", async () => { ... }, 15000)`. |
| "File last touched: #2842 (replace credential.helper=! with GIT_ASKPASS)" | Confirmed: `git-auth.ts:1-20` header documents the migration; `github-app.ts:483-491` carries the deprecated `randomCredentialPath` stub with `@deprecated` JSDoc explicitly naming this test family as the reason for keeping the export. | The assertion-retarget cleanly aligns the test with the GIT_ASKPASS migration's actual cleanup contract. |

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 -- `bun run --filter @soleur/web-platform vitest run test/workspace-error-handling.test.ts` passes 5 consecutive times locally, with no run exceeding 2s wall-clock for the third test case (deterministic -- no network). Verified: 5/5 runs green, each <1s.
- [x] AC2 -- The third test's `child_process` mock is present and parallels test #2's shape (lines 61-89) AND the canonical sibling at `git-auth.test.ts:33-58, 223-244`: `vi.doMock("child_process", async () => { const actual = await vi.importActual<typeof import("child_process")>("child_process"); return { ...actual, execFile: vi.fn().mockImplementation(...) }; })`. The implementation invokes the callback with a synthetic `git exited 128` error and a realistic stderr buffer when `cmd === "git" && args.includes("clone")`.
- [x] AC3 -- The third test's cleanup assertion uses the canonical env-capture pattern: `let capturedAskpassPath: string | undefined;` is declared before the doMock block; the execFile mock implementation assigns `capturedAskpassPath = opts?.env?.GIT_ASKPASS` inside the `cmd === "git" && args.includes("clone")` branch; after `await expect(...).rejects.toThrow()` settles, the test asserts both `expect(capturedAskpassPath).toBeTruthy()` AND `expect(existsSync(capturedAskpassPath!)).toBe(false)`. The shape mirrors `git-auth.test.ts:223-244` byte-equivalent.
- [x] AC4 -- `bun run --filter @soleur/web-platform tsc --noEmit` is green (type-check clean after test edits). Verified: tsc --noEmit exit 0.
- [x] AC5 -- `bun test plugins/soleur/test/components.test.ts` is green (skill registry unchanged -- sanity). Verified: 1029 pass / 0 fail.
- [x] AC6 -- `grep -n "existsSync(credPath)" apps/web-platform/test/workspace-error-handling.test.ts` returns 0 lines; the misleading assertion on the deprecated `randomCredentialPath` return value is gone.
- [x] AC7 -- `grep -n "cleans up askpass script even when clone fails" apps/web-platform/test/workspace-error-handling.test.ts` returns 1 line (rename applied); `grep -n "cleans up credential helper even when clone fails"` returns 0 lines (old title removed).
- [ ] AC8 -- PR body references `Closes #3597` (issue closure semantic -- test-only fix lands at merge, no post-merge operator step required). PR body also notes "Test title rename: 'credential helper' -> 'askpass script' to match the GIT_ASKPASS artifact (#2842 migration semantic)" so reviewers do not flag the rename as scope creep.

### Post-merge (operator)

- [ ] AC9 -- After merge, re-run CI on the next 5 main-branch commits and confirm zero occurrences of "Test timed out in 5000ms" against `workspace-error-handling.test.ts`. If the flake recurs against a different test in the same file, file a follow-up with the same root-cause-analysis pattern (network call escapes the mock boundary).

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200` cross-referenced against `apps/web-platform/test/workspace-error-handling.test.ts`, `apps/web-platform/server/workspace.ts`, and `apps/web-platform/server/git-auth.ts` -- no open scope-out names any of these files.

## Files to Edit

- `apps/web-platform/test/workspace-error-handling.test.ts` -- lines 101-118. Rewrite the third test to (a) mock the subprocess-module `execFile` with a deterministic clone failure (mirror lines 61-89), (b) retarget cleanup assertion to the askpass script artifact, (c) remove the misleading `credPath = ${randomCredentialPath()}` assertion target (keep the mocked stub itself for symmetry with the other 4 tests in the file, per the `@deprecated` JSDoc note that preserves the export for exactly this kind of test).

## Files to Create

None.

## Implementation

### Phase 1 -- Retarget test #3 to deterministic + correct artifact (canonical-pattern aligned)

Replace the body of the third test case (lines 101-118). The deepen-pass discovered the canonical in-repo pattern at `apps/web-platform/test/git-auth.test.ts:223-244` ("cleans up askpass script even when git fails") -- adopt it byte-equivalent so reviewers see one pattern across two test files.

**Canonical pattern (from `git-auth.test.ts:223-244`):**

1. Mock `../server/github-app` -- only the symbols that `workspace.ts` reads at module-init (the existing test already does this correctly).
2. Mock `child_process` with `importActual` + spread; intercept `execFile` and, when `cmd === "git" && args.includes("clone")`, capture the askpass path off `call.opts.env.GIT_ASKPASS`, then invoke the callback with a synthetic `git exited 128` error bearing realistic stderr.
3. Dynamic-import `provisionWorkspaceWithRepo` AFTER the doMock blocks (per Context7 doc -- `vi.doMock` only affects the *next* dynamic import).
4. `await expect(...).rejects.toThrow()` to drain the rejection.
5. Assert `existsSync(capturedAskpassPath)` is `false`.

**Recommended skeleton (drop-in for lines 101-118):**

```ts
test("cleans up askpass script even when clone fails", async () => {
  vi.doMock("../server/github-app", () => ({
    generateInstallationToken: vi.fn().mockResolvedValue("ghs_faketoken123"),
    // randomCredentialPath stub kept for symmetry with sibling tests; the
    // deprecated export is being swept by #2848. Removing it here would be
    // out of scope for the flake fix.
    randomCredentialPath: vi.fn().mockReturnValue(`/tmp/git-cred-${randomUUID()}`),
    checkRepoAccess: vi.fn().mockResolvedValue("ok"),
  }));

  let capturedAskpassPath: string | undefined;

  // NOTE: factory does NOT throw -- error is injected through the execFile
  // callback. Avoids the vitest-wrapper-message swallowing class documented
  // in 2026-05-07-vitest-domock-factory-throw-wrapped-message.md.
  vi.doMock("child_process", async () => {
    const actual = await vi.importActual<typeof import("child_process")>("child_process");
    return {
      ...actual,
      execFile: vi
        .fn()
        .mockImplementation(
          (
            cmd: string,
            args: string[],
            opts: { env?: NodeJS.ProcessEnv; cwd?: string; timeout?: number } | undefined,
            cb: (err: Error | null, result: { stdout: Buffer; stderr: Buffer }) => void,
          ) => {
            if (cmd === "git" && args.includes("clone")) {
              // Canonical pattern: capture GIT_ASKPASS off the env block that
              // gitWithInstallationAuth (git-auth.ts:230-242) sets right
              // before invoking execFile. This is the ACTUAL artifact the
              // try/finally in git-auth.ts:228-258 cleans up.
              capturedAskpassPath = opts?.env?.GIT_ASKPASS;
              const err: Error & { stderr?: Buffer } = new Error("git exited 128");
              err.stderr = Buffer.from(
                "fatal: repository 'https://github.com/nonexistent/fake-repo-xxx/' not found\n",
              );
              cb(err, { stdout: Buffer.from(""), stderr: err.stderr });
              return;
            }
            cb(null, { stdout: Buffer.from(""), stderr: Buffer.from("") });
          },
        ),
    };
  });

  const { provisionWorkspaceWithRepo } = await import("../server/workspace");
  const userId = randomUUID();

  await expect(
    provisionWorkspaceWithRepo(userId, "https://github.com/nonexistent/fake-repo-xxx", 12345),
  ).rejects.toThrow();

  // Cleanup contract: gitWithInstallationAuth's finally block unlinks the
  // askpass script even on clone failure (git-auth.ts:90-97, 256-258).
  // Mirror of git-auth.test.ts:223-244.
  expect(capturedAskpassPath).toBeTruthy();
  expect(existsSync(capturedAskpassPath!)).toBe(false);
});
```

Mechanical edits required to apply this skeleton:

- KEEP the `vi.doMock("../server/github-app", ...)` block (lines 103-107) -- the new skeleton's first doMock is identical.
- DELETE the `const credPath = ...` line (102) and the `existsSync(credPath)` assertion (117).
- INSERT the `child_process` doMock block + the `let capturedAskpassPath: string | undefined;` declaration (modelled byte-for-byte on `git-auth.test.ts:223-235` plus `mockExecFile`'s behavior callback shape at `git-auth.test.ts:29-60`).
- REPLACE the final `expect` with the `existsSync(capturedAskpassPath!)` assertion.
- RENAME the test title from "cleans up credential helper even when clone fails" -> "cleans up askpass script even when clone fails" (the credential-helper terminology pre-dates the GIT_ASKPASS migration of #2842; "askpass script" matches the production artifact name in `git-auth.ts:79-84`).
- The `fs` import block at line 11 already imports `existsSync` -- no change required (no `readdirSync` / `accessSync` needed under the canonical pattern; this is a strict improvement over the v1 deepen-plan draft).
- DO NOT bump the per-test timeout. After the determinism fix, the test should complete in <100ms wall-clock.

**Why the canonical-pattern wins over the readdir-snapshot approach (rejected v1 deepen):**

| Concern | readdirSync delta (v1) | env-capture (canonical) |
| --- | --- | --- |
| Asserts on this test's askpass file | No -- aggregate delta over askpass-dir | Yes -- captured by path |
| Re-implements `getAskpassDir` heuristic | Yes (risk R1, R3) | No -- env block IS the heuristic's output |
| Concurrent `/tmp` writer noise | Possible delta inflation | Zero |
| Reviewer pattern-match cost | New pattern | Identical to existing `git-auth.test.ts:223-244` |
| LOC | ~15 | ~8 |

The canonical pattern is unambiguously better. v1 deepen kept readdir-snapshot as a fallback; v2 deepen drops it entirely.

### Phase 2 -- Verify

Run locally:

```bash
cd apps/web-platform
bun run vitest run test/workspace-error-handling.test.ts
# Repeat 5x to confirm no flake:
for i in 1 2 3 4 5; do bun run vitest run test/workspace-error-handling.test.ts || break; done
bun run tsc --noEmit
```

Confirm AC1-AC6 before pushing.

## Test Strategy

The test file already uses vitest (default for `apps/web-platform`). No new framework needed. No new dependencies -- the existing `fs` import block already provides `existsSync`. The deterministic-mock shape is identical to test #2 in the same file AND to the canonical `git-auth.test.ts:223-244` "cleans up askpass script even when git fails" test, so reviewer pattern-match is trivial.

**Determinism mechanism:** The fix removes the test's only real-network dependency. Before the fix, test #3 invokes `provisionWorkspaceWithRepo(...)` which calls `gitWithInstallationAuth(...)` which calls `execFileAsync("git", ["clone", ...])` against `https://github.com/nonexistent/fake-repo-xxx`. The clone hits real DNS + TCP + HTTP-404 against github.com; on contended CI runners this round trip can exceed 5s. After the fix, `execFile` is mocked to invoke the callback synchronously with a synthetic error, so the entire path completes in microseconds.

**Vitest version note:** `bun pm ls vitest` should confirm the version in `apps/web-platform`. Recent vitest versions (v3.1.2+, v4) have documented CI-timeout flake regressions (see Enhancement Summary sources). The fix here is version-independent -- the determinism removal makes the test immune to vitest pool/worker timing behavior.

**No new test cases.** The deepen-pass deliberately does NOT propose adding tests for the new mock-cascade hygiene or env-capture pattern; both are exercised by the test itself, and over-instrumenting a flake fix violates the YAGNI principle the code-simplicity reviewer enforces.

## Risks (post-deepen, canonical-pattern aligned)

- **R1 (CLOSED by canonical pattern) -- Askpass-dir heuristic divergence.** No longer applicable. The test captures `GIT_ASKPASS` directly off the env block that `gitWithInstallationAuth` (`git-auth.ts:230-242`) sets right before invoking `execFile`. The captured path IS the heuristic's output -- the test does not re-implement the heuristic, so a future change to `getAskpassDir` (`git-auth.ts:63-67`) surfaces immediately as a change in the captured path's prefix without breaking the assertion semantic.
- **R2 (CLOSED by canonical pattern) -- readdir on `/tmp` noisy.** No longer applicable. The new assertion is scoped to exactly one path (the one captured from the env). Concurrent `/tmp` writers cannot induce false positives or false negatives.
- **R3 (CLOSED by canonical pattern) -- `$HOME` writeability differs in CI.** No longer applicable. The test reads the dir-selection result from the SUT's env block, not from its own re-implemented heuristic.
- **R4 -- vitest module-graph isolation.** The unit project in `vitest.config.ts:13-21` does NOT set `isolate: true` (the component project does, at line 41). Module-level `vi.doMock` registrations between tests are cleared by the existing `afterEach` at `workspace-error-handling.test.ts:21-30` (`vi.restoreAllMocks()` + `vi.doUnmock("child_process")` + `vi.doUnmock("../server/github-app")`) plus `vi.resetModules()` at `beforeEach` lines 17-19. The new `child_process` mock in test #3 is already covered by the existing `doUnmock("child_process")` line. **No additional cleanup needed.** Verified by reading the afterEach contents and the canonical sibling pattern at `git-auth.test.ts:66-70` which mirrors the same hygiene.
- **R5 -- Mock-cascade on growing SUT imports.** Per learning `2026-04-18-extraction-di-boundaries-and-mock-cascade.md`, wholesale `vi.doMock("child_process", () => ({ execFile: ... }))` that omits real exports breaks at SUT module-load time when `git-auth.ts:30` evaluates `promisify(execFile)`. The Phase 1 skeleton uses `vi.importActual<typeof import("child_process")>("child_process")` + spread, mirroring `git-auth.test.ts:33-58`, which survives any future expansion of `git-auth.ts`'s import surface (e.g., if `git-auth.ts` adds `import { spawn } from "child_process"` tomorrow, this mock continues to work because `spawn` falls through to the actual module).
- **R6 -- `removeWorkspaceDir`'s `execFileSync` calls under the mock.** `workspace.ts:143` runs `removeWorkspaceDir(workspacePath)` in parallel with `checkRepoAccess` via `Promise.all`. `removeWorkspaceDir` (`workspace.ts:246-298`) uses `execFileSync` (not `execFile`) for `rm -rf`, `chmod -R u+rwX`, `find -delete`, `rmdir`, `mv`. The new mock only intercepts `execFile` (async), so `execFileSync` falls through to the real binary. This is **correct behavior** -- on a fresh test workspace dir (which doesn't exist), `removeWorkspaceDir` short-circuits at line 253 (`if (!existsSync(workspacePath)) return;`). Even if a stale dir exists from a prior test, `rm -rf` on a few-KB tree takes <10ms. No mocking required, but the contract is documented here so a future change (e.g., async-ifying `removeWorkspaceDir`) does not silently break this test.
- **R7 -- v3.1.2+/v4 vitest pool-flake regression** (vitest issues #7871, #8559, #8766). Documented vitest CI-timeout flake increase since v3.1.2; even on the worst-affected versions the deterministic test should complete in <100ms. No version pin or `testTimeout` override is recommended -- the determinism fix removes the symptom regardless of the upstream issue.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above with threshold = `none` and a justification covering the test-only diff scope.
- The "cleans up credential helper" test title in the current file is misleading -- it refers to an artifact that the GIT_ASKPASS migration (#2842) removed. The Phase 1 rename to "askpass script" is a clarity fix, not a feature change. Reviewer note in the PR body (AC8) should explicitly call this out so the rename does not look like scope creep.
- Per `cq-test-fixtures-synthesized-only`, the new test continues to use synthesized fixtures (mocked execFile callback) -- no live github.com call survives the fix. This is the root cause of the flake being closed, not a side effect.
- Per `wg-when-tests-fail-and-are-confirmed-pre`, this flake was confirmed pre-existing (PR #3589 diff is "exclusively CI lint scripts + markdown + bash test fixtures -- no overlap with apps/web-platform"). The fix lands as a separate PR per the workflow gate.
- The `randomCredentialPath` export in `github-app.ts:489-491` is `@deprecated` but kept alive only to avoid breaking unmigrated tests. **Issue #2848 (still open) already tracks the deprecation sweep across 6 files** (kb-delete, kb-upload, kb-rename, kb-route-helpers, push-branch, workspace-error-handling). After this PR, test #3's mock stub call survives as harmless symmetry with the other 4 tests in the same file -- consistent with #2848's "remove from all 6 files in one mechanical sweep" framing. Do NOT remove only this test's stub mid-flake-fix; that creates an asymmetric file state #2848 will have to untangle.
- The Phase 1 skeleton uses `vi.doMock` with a non-throwing factory (errors are injected through the `execFile` callback). Per learning `2026-05-07-vitest-domock-factory-throw-wrapped-message.md`, a `vi.doMock` factory that *throws* is wrapped by vitest with a synthetic Error whose `.message` is opaque ("[vitest] There was an error when mocking a module..."). The Phase 1 skeleton's `// NOT a factory throw -- error injected via callback` comment makes the design choice visible at the call site so a future maintainer who tries to "simplify" by hoisting the error throw into the factory does not silently break the assertion semantic.
- **Canonical-pattern enforcement.** The Phase 1 skeleton mirrors `apps/web-platform/test/git-auth.test.ts:223-244` byte-equivalent. If a future contributor proposes a different cleanup-assertion shape for this test (spy-on-cleanupAskpassScript, readdir-snapshot, fixture-cleanup hook), point them at AC3 and the sibling test -- divergence between the two test files for the same SUT contract is a smell.
- Per Context7 docs on `vi.doMock` semantics ("only affects the *next* dynamic import after vi.doMock is called"), the Phase 1 skeleton's `await import("../server/workspace")` MUST appear AFTER both `vi.doMock` blocks. The existing `beforeEach { vi.resetModules() }` (line 17-19) ensures the cache is clear so the mocks apply on each test's first dynamic import. Static `import` at the top of the file would NOT see the mocks (statics are hoisted; doMock is not).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- test-only flake remediation against a deterministic mock. No product/UX surface, no schema, no auth flow, no marketing surface, no legal surface, no analytics.

## Follow-on issues (out of scope for this PR)

After #3597 ships, the user requested sequential one-shots for #3607 then #3595. These are separate scopes and will be re-planned in their own one-shot cycles:

- **#3607** -- Harden `skill-security-scan` curl-pipe-bash detection against split-line / indirect-invocation obfuscation; widen download-tool allowlist (P2, `domain/engineering`, `code-review`, `deferred-scope-out`).
- **#3595** -- bot-workflow enumeration: YAML-aware parser for audit/lint parity (P2, `domain/engineering`, `code-review`, `deferred-scope-out`).

Both are P2 contested-design scope-outs requiring their own brainstorm/plan cycles. They are NOT bundled into this PR.

## Verification grep (AC pre-flight)

Before opening the PR, run:

```bash
# AC2 -- verify the child_process mock landed in test #3.
# File should contain ≥ 4 doMock blocks total: test #2 (existing), new test #3,
# test #4 (existing), test #5 (existing).
rg -n 'vi\.doMock\("child_process"' apps/web-platform/test/workspace-error-handling.test.ts | wc -l
# Expect: 4

# AC3 -- verify the canonical env-capture assertion shape is present
rg -n 'capturedAskpassPath|GIT_ASKPASS' apps/web-platform/test/workspace-error-handling.test.ts
# Expect: ≥ 2 hits (declaration + capture + assertion)

# AC6 -- verify test #3 no longer asserts on randomCredentialPath's return value
rg -n 'existsSync\(credPath\)' apps/web-platform/test/workspace-error-handling.test.ts
# Expect: 0 hits

# AC7 -- verify test title was renamed
rg -n 'cleans up askpass script even when clone fails' apps/web-platform/test/workspace-error-handling.test.ts
# Expect: 1 hit
rg -n 'cleans up credential helper even when clone fails' apps/web-platform/test/workspace-error-handling.test.ts
# Expect: 0 hits

# Cross-file canonicality check: assertion shape matches the sibling test
diff <(rg -n 'capturedAskpassPath' apps/web-platform/test/workspace-error-handling.test.ts | wc -l) \
     <(rg -n 'capturedAskpassPath' apps/web-platform/test/git-auth.test.ts | wc -l)
# Expect: similar order of magnitude (both files use the same pattern; not strict equality)
```
