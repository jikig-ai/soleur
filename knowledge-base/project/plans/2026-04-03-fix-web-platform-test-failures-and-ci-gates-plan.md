---
title: "fix: 71 pre-existing web-platform test failures (jsdom/document not defined) and CI gate improvements"
type: fix
date: 2026-04-03
---

# fix: 71 pre-existing web-platform test failures and CI gate improvements

## Overview

71 React component tests in `apps/web-platform/test/*.tsx` fail with `ReferenceError: document is not defined` when run under `bun test`, but pass under `npx vitest run`. The root cause is that Bun's built-in test runner does not support vitest's `environmentMatchGlobs` configuration, so `.tsx` test files that need a DOM environment (happy-dom) run in a bare Node-like environment without `document`, `window`, or other browser globals.

CI and pre-commit hooks already use `npx vitest run` (via `scripts/test-all.sh` line 55), so these failures do not block merges. However, the `/ship` skill's Phase 4 runs `bun test` directly, and several plan/spec documents reference `bun test` as the verification command. This creates a confusing developer experience where "the tests pass in CI but fail locally."

The second part of this issue is strengthening CI gates so that no PR can merge to main with failing tests, regardless of which runner is used.

## Problem Statement

### Part 1: bun test failures

**Affected files (7 `.tsx` test files, 71 tests):**

- `test/at-mention-dropdown.test.tsx` (14 tests)
- `test/chat-input.test.tsx` (11 tests)
- `test/chat-page.test.tsx` (8 tests)
- `test/dashboard-page.test.tsx` (9 tests)
- `test/error-states.test.tsx` (8 tests)
- `test/oauth-buttons.test.tsx` (7 tests)
- `test/settings-page.test.tsx` (12 tests)

Plus 1 cross-contamination failure in `test/ws-protocol.test.ts` (`idle timeout > NON_TRANSIENT_CLOSE_CODES`) that only fails when run alongside `.tsx` files (passes in isolation).

**Root cause:** Vitest's `environmentMatchGlobs` in `vitest.config.ts` maps `test/**/*.tsx` to `happy-dom`, providing a DOM environment. Bun's test runner ignores this config entirely -- it has no vitest config awareness. Bun requires a separate mechanism: a preload script in `bunfig.toml` that calls `@happy-dom/global-registrator` to register DOM globals.

**Current workaround:** `test-all.sh` line 55 already uses `npx vitest run` for web-platform instead of `bun test`. CI passes. But `bun test` in the app directory (used by `/ship` Phase 4 and referenced in plan documents) still fails.

### Part 2: CI gate gaps

1. **`/ship` Phase 4 uses `bun test`** -- This is the command agents run before shipping. It produces 71 failures that are then rationalized as "pre-existing" and bypassed.
2. **Plan/spec documents reference `bun test`** -- Multiple plans and task files tell developers to verify with `bun test apps/web-platform/` instead of `npx vitest run`.
3. **No required status check for e2e** -- The `CI Required` ruleset requires only the `test` job. The `e2e` job (Playwright) is not required.

## Proposed Solution

### Phase 1: Fix bun test DOM environment

Add a happy-dom preload script for Bun's test runner so that both `bun test` and `npx vitest run` produce the same results.

**1.1 Create `apps/web-platform/test/happy-dom.ts`:**

A preload script that registers happy-dom globals for Bun's test runner:

```typescript
import { GlobalRegistrator } from "@happy-dom/global-registrator";

GlobalRegistrator.register();
```

**1.2 Update `apps/web-platform/bunfig.toml`:**

Add a `[test]` section with the preload script:

```toml
[test]
preload = ["./test/happy-dom.ts"]
```

**1.3 Verify both runners produce identical results:**

- `bun test` -- should show 390 pass, 0 fail
- `npx vitest run` -- should show 390 pass, 0 fail (already works)

### Phase 2: Fix /ship skill test command

**2.1 Update `plugins/soleur/skills/ship/SKILL.md` Phase 4:**

Change the test command from `bun test` to `bash scripts/test-all.sh`. This is the same command CI uses, ensuring parity between local ship checks and CI. The `test-all.sh` script already handles:

- Per-directory test isolation (avoids Bun FPE crash)
- Vitest for web-platform (DOM environment support)
- Bun test for other suites (telegram-bridge, plugins)

### Phase 3: Add e2e to required status checks (optional hardening)

**3.1 Add `e2e` to the CI Required ruleset:**

Currently only `test` and `dependency-review` are required. The `e2e` job (Playwright tests) can fail without blocking merges. Add it to required checks via:

```bash
gh api repos/jikig-ai/soleur/rulesets/14145388 \
  --method PUT \
  --field 'rules[0].type=required_status_checks' \
  --field 'rules[0].parameters.strict_required_status_checks_policy=true' \
  --field 'rules[0].parameters.required_status_checks[0].context=test' \
  --field 'rules[0].parameters.required_status_checks[0].integration_id=15368' \
  --field 'rules[0].parameters.required_status_checks[1].context=dependency-review' \
  --field 'rules[0].parameters.required_status_checks[1].integration_id=15368' \
  --field 'rules[0].parameters.required_status_checks[2].context=e2e' \
  --field 'rules[0].parameters.required_status_checks[2].integration_id=15368'
```

Note: This should be evaluated carefully. If e2e tests are flaky, making them required could block legitimate PRs. Assess e2e stability first by checking recent CI run history.

## Technical Considerations

### Why not just remove bun test entirely?

`bun test` is faster than vitest for non-DOM test files. The `test-all.sh` script already uses bun for `plugins/soleur/`, `apps/telegram-bridge/`, and root-level tests. Only `apps/web-platform/` needs vitest because of the DOM environment requirement. Having bun test also work for web-platform (via the preload script) means developers can run `bun test` from any directory and get correct results.

### happy-dom vs jsdom

The project already uses `happy-dom` (not `jsdom`) for vitest due to ESM compatibility issues documented in `knowledge-base/project/learnings/2026-03-30-tdd-enforcement-gap-and-react-test-setup.md`. The preload script uses the same library (`@happy-dom/global-registrator`) for consistency. `happy-dom` is already a devDependency in `apps/web-platform/package.json`.

### Cross-runner compatibility

Per `knowledge-base/project/learnings/integration-issues/vitest-bun-test-cross-runner-compat-20260402.md`, test files must use vitest imports (bun has vitest compat) and avoid runner-specific mock APIs. The `.tsx` test files already follow this pattern -- they just need the DOM globals to be available.

### The `setup-dom.ts` file

The existing `test/setup-dom.ts` conditionally imports `@testing-library/react` cleanup only when `document` is defined. With the happy-dom preload, `document` will always be defined for bun test, so cleanup will always run (matching vitest behavior with the happy-dom environment).

## Acceptance Criteria

- [ ] `cd apps/web-platform && bun test` passes with 0 failures (390 pass)
- [ ] `cd apps/web-platform && npx vitest run` continues to pass (390 pass)
- [ ] `bash scripts/test-all.sh` passes with 0 failures
- [ ] `/ship` Phase 4 test command changed from `bun test` to `bash scripts/test-all.sh`
- [ ] No plan/spec documents reference `bun test` as verification for web-platform without noting to use vitest

## Test Scenarios

- Given a fresh checkout, when running `cd apps/web-platform && bun test`, then all 390 tests pass with 0 failures
- Given a fresh checkout, when running `cd apps/web-platform && npx vitest run`, then all 390 tests pass (regression check)
- Given the happy-dom preload is configured, when running `bun test test/dashboard-page.test.tsx` in isolation, then all dashboard tests pass (previously 9 failures)
- Given the happy-dom preload is configured, when running `bun test test/settings-page.test.tsx` in isolation, then all settings tests pass (previously 12 failures)
- Given the `/ship` skill Phase 4, when it runs the test suite, then it uses `bash scripts/test-all.sh` (not `bun test`)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change affecting test runner configuration and CI quality gates.

## References

- GitHub issue: #1430
- Related closed issue: #1413 (closed prematurely)
- Learning: `knowledge-base/project/learnings/2026-03-30-tdd-enforcement-gap-and-react-test-setup.md`
- Learning: `knowledge-base/project/learnings/integration-issues/vitest-bun-test-cross-runner-compat-20260402.md`
- Learning: `knowledge-base/project/learnings/2026-04-01-ci-quality-gates-and-test-failure-visibility.md`
- Bun DOM testing docs: `https://bun.sh/docs/test/dom`
- Current vitest config: `apps/web-platform/vitest.config.ts`
- Current bunfig: `apps/web-platform/bunfig.toml`
- test-all.sh: `scripts/test-all.sh` (line 55 -- already uses vitest for web-platform)
- Ship skill: `plugins/soleur/skills/ship/SKILL.md` (Phase 4, line 225 -- uses `bun test`)
- CI Required ruleset: ID 14145388 (requires `test` + `dependency-review`, not `e2e`)
