# Tasks: normalizeRepoUrl idempotent fixpoint

Plan: `knowledge-base/project/plans/2026-10-20-fix-normalize-repo-url-idempotent-fixpoint-plan.md`
Branch: `feat-one-shot-normalize-repo-url-idempotent-fixpoint` | Draft PR: #10692 | Ref #10624

## Phase 0: Setup

- 0.1 `git fetch origin main`; merge/rebase the branch onto `origin/main`.

## Phase 1: RED — regression fixtures (test file only)

- 1.1 In `apps/web-platform/test/lib/repo-url.property.test.ts`, inside `describe("normalizeRepoUrl — regression fixtures")`, add the reported counterexample fixture with the comment `// regression fixture: fast-check seed -1029694662 path 68:0:0:0:0:0:1:0:0`; assert `normalizeRepoUrl(" http://a.aa/..git/")` is `http://a.aa` and that a second call returns the same value. No `{ seed }` params.
- 1.2 Add three extra pinned examples (label `// pinned example (scratch fuzz 2026-10-20, no fast-check seed)`): `"http://a.aa/" + "..git/".repeat(5)` -> `http://a.aa`; `"xx:B"` -> `xx://b`; `"x" + " /".repeat(8)` -> `x`. Each asserts value and idempotence.
- 1.3 Run `cd apps/web-platform && bunx vitest run test/lib/repo-url.property.test.ts`; confirm the new fixtures are RED against the unmodified SUT; save the failing assertion lines for the PR body.

## Phase 2: GREEN — the fix

- 2.1 In `apps/web-platform/lib/repo-url.ts`: rename the existing body (after the `null` guard) to internal `normalizeRepoUrlPass`; export `normalizeRepoUrl` as a single fixpoint loop (`current = raw; cap = raw.length + 3; for i < cap { next = pass(current); if next === current return current; current = next }; return current`). No new import, no Sentry, no throw (CTO re-ruling).
- 2.2 Update the header comment (reword, do not merely append: idempotence delivered by the fixpoint loop; canonical-form step 6; termination argument incl. same-length pass 2; the SQL twin mirrors steps 1-5 only where `new URL()` does not rewrite the path; #10633).
- 2.3 Delete the stray `/* #9815 e2e probe — REVERTED BEFORE COMMIT */` line.
- 2.4 Re-run the property test file; confirm all green; save the output for the PR body.

## Phase 3: Verification

- 3.1 `cd apps/web-platform && bunx vitest run test/lib/repo-url.property.test.ts test/repo-url.test.ts test/repo-url-sql-parity.test.ts test/current-repo-url.test.ts`.
- 3.2 Run the suites that load the real module: `test/current-repo-url.test.ts`, `test/server/inngest/workspace-reconcile-on-push.test.ts`, plus any webhook / active-repo route suite (`git grep -l "webhooks/github/route\|workspace/active-repo/route" -- 'apps/web-platform/test/**'`). The three setup-route suites fully mock `@/lib/repo-url` and are not evidence.
- 3.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- 3.4 Scratch (uncommitted, session scratchpad) high-run-count hunt: >= 3 seeds x 100k runs over the property file's `inputArb` plus a dot-segment alphabet; record any other counterexample and any input hitting the `raw.length + 3` cap (that flips the CTO ruling to a Sentry mirror).
- 3.5 Mutation battery from the plan's Guard Contract (revert to single pass; fixed cap 4; return after first pass) — confirm each goes RED, then restore.

## Phase 4: Docs

- 4.1 Add a 1-2 line "Second yield" note after "First yield" in `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md` (yield only: counterexample, run id, bounded convergence loop). The SQL divergence goes in the `lib/repo-url.ts` header and the PR body.

## Phase 5: Ship

- 5.1 PR #10692 body: root cause, RED and GREEN output, SQL mirror finding (no migration), other counterexamples found, stray-line deletion, follow-up issue for generator widening. `Ref #10624`, `Ref` failing run 39400877769, `Ref #10633`; never Closes/Fixes/Resolves. Do not comment on any issue; do not touch PR #10528, git-data or legal files; do not dispatch any workflow.
- 5.2 If the same suite flakes in the merge queue after this PR is queued, file a flake issue; do not re-enqueue a third time.
