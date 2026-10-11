# Tasks: fix cross-workspace isolation canary probe unresolved vitest/config import

Plan: knowledge-base/project/plans/2026-10-09-fix-workspace-isolation-vitest-config-plan.md
Issues: Ref #9860 (latest comment), Ref #2640 — PR body uses `Ref`, NOT `Closes`
(sibling pipeline #9884 owns the `sandbox_broken` verdict).

Collision guard: do NOT touch `apps/web-platform/infra/ci-deploy.sh`,
`apps/web-platform/infra/ci-deploy.test.sh`,
`knowledge-base/engineering/operations/runbooks/canary-probe-set.md`, or
`plugins/soleur/test/preflight-discoverability-test.test.ts` — all four carry
sibling PR #9884 diffs.

## Phase 1: regression pin (TDD — RED first)

- [ ] 1.1 RED(unit): add an `it` to the existing `describe` in
  `apps/web-platform/test/dockerfile-vitest-version-pin.test.ts` asserting the
  canary config carries zero `import` statements in its non-comment code
  (reuse the test's existing `code` comment-stripping; assert
  `code` does not match `/^\s*import\b/m` — `\b` also catches a dynamic
  `import(…)` arm, which a `\s`-terminated predicate would miss). Run
  `npx vitest run test/dockerfile-vitest-version-pin.test.ts` from
  `apps/web-platform/` — confirm RED on the current config.
- [ ] 1.2 GREEN: `apps/web-platform/test/vitest.canary.config.ts` — delete
  `import { defineConfig } from "vitest/config"`, change
  `export default defineConfig({…})` to `export default {…}` (identical keys),
  and extend the header comment noting the in-image run resolves no bare
  specifiers from the config file (suite-side `vitest` imports resolve
  internally — measured at plan time on vitest 4.1.11).
- [ ] 1.3 Re-run `npx vitest run test/dockerfile-vitest-version-pin.test.ts` —
  green; the existing minimality `it` (payload-only `include:`, no
  `globalSetup`/`setupFiles`/`projects`) must stay green.

## Phase 2: in-image equivalence verification

- [ ] 2.1 Reproduce the prod context locally: temp dir with only the three
  payload files (`test/vitest.canary.config.ts`,
  `test/sandbox-isolation.test.ts`,
  `test/helpers/sandbox-isolation-fixtures.ts`) plus a `node_modules`
  containing only a stub/prod-dep set, then run the worktree vitest binary
  under `/usr/bin/env -i` with the probe's env knobs — confirm the suite is
  collected with no `[UNRESOLVED_IMPORT]` (recipe measured at plan time:
  `Tests 1 passed` on a minimal probe; the real suite exercises
  `SOLEUR_ISOLATION_TIERS=direct`).
- [ ] 2.2 `bash apps/web-platform/infra/ci-deploy.test.sh` — confirm the CWI
  arms (CWI-1 argv pin, CWI-4 report-only, CWI-10 vacuous-green) are unchanged
  and green; the diff must not touch `ci-deploy.sh`.

## Phase 3: docs + ship prep

- [ ] 3.1 One paragraph in
  `knowledge-base/engineering/operations/runbooks/workspace-isolation-canary-probe.md`
  under "Image strategy" recording the zero-import constraint on
  `vitest.canary.config.ts` and the pin that enforces it.
- [ ] 3.2 `git diff --name-only origin/main...HEAD` — assert none of the four
  collision-guard paths appear (merge-base diff, not the moving tip).
- [ ] 3.3 `npx markdownlint-cli2` on the edited runbook — green.
- [ ] 3.4 PR body: `Ref #9860` and `Ref #2640` on own lines (never `Closes`);
  note that the probe stays report-only and the soak counter
  (`consecutive_pass`) can now actually accumulate toward the promotion gate
  in `scripts/followthroughs/workspace-isolation-verdict-2640.sh`.
