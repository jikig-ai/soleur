# Tasks: feat: Inngest execution placement — codified, drift-guarded rule (#7230)

Plan: `knowledge-base/project/plans/2026-09-28-feat-inngest-execution-host-placement-rule-plan.md`

Constraints for the whole PR:

- No edit under `apps/web-platform/infra/**`, because any such merge fires a production apply.
- No `.github/workflows/*` edit.
- No change to `app/api/inngest/route.ts`.
- Verify with CI plus targeted vitest; do not run the local full affected gate.

## Phase 0: Walker extraction (behaviour-preserving)

- [x] 0.1 Snapshot the pre-extraction walker's sorted reach and problems sets for the clock entry
      **and every served function module** (about 71 entries) to scratch files. Baseline:
      `watchdog-dispatch-clock.test.ts` has 63 passed.
- [x] 0.2 Move `resolveSpecifier`, `specifiersOf` and `walk` into
      `apps/web-platform/test/helpers/ts-import-graph.ts`.
  - [x] 0.2.1 Inject `fs = { readFile, exists, listFiles, appRoot }`. It is **required** on every
        new helper; only the clock test's legacy call has a real-filesystem default. `rel()`
        uses `fs.appRoot`.
  - [x] 0.2.2 Add `elideTypeOnlySpecifiers?: boolean`, off by default.
  - [x] 0.2.3 Add `recordDynamicImportArgs?: boolean`, off by default. It records a non-literal
        import as `{ file, argText }`.
  - [x] 0.2.4 Add no `stopAt`: the walk descends through the definer modules.
- [x] 0.3 Point `watchdog-dispatch-clock.test.ts` at the helper, with no assertion change.
- [x] 0.4 Re-run the clock test (it must be green) and `diff` every post-extraction reach and
      problems set against 0.1 (all diffs must be empty). Record both in the PR body.

## Phase 1: RED — the guard suite

- [x] 1.1 Create `apps/web-platform/test/server/inngest/execution-placement.test.ts`. It holds the
      guard config and the pure helpers over the `readFile` seam:
  - `PORTABLE_SAFE_SHARED_EXPORTS` (14 names);
  - `HOST_STATE_VERIFIER_WORKFLOWS`;
  - `servedFunctions`;
  - `derivePinning`;
  - `portableViolations`;
  - `circularityViolations`;
  - the serve-URL anchor check.
- [x] 1.2 Guard 1: set identity by function id. It must:
  - unwrap `as` / `satisfies` / parenthesized configs;
  - resolve const ids (`REQUESTED_FUNCTION_ID`, `FN_ID`, `FUNCTION_NAME`);
  - fail closed on non-Identifier array elements;
  - cross-check the array against route.ts imports;
  - run mutation rows 1–7 and harness rows H1–H2.
- [x] 1.3 Guard 2: portable boundary. It must cover:
  - definer edges from any closure module, including namespace, `require`/`import()` and
    re-exports, with per-specifier `type` skipping;
  - the closure marker scan, which descends through the definers and exempts only their own
    source text;
  - `{ offenders, checkedCount, closureSizes }`, with the anti-vacuity floor inside the helper;
  - the allowlisted-export body scan;
  - type-only elision;
  - mutation rows 1–11 and harness rows H1–H3.
- [x] 1.4 Guard 3: anti-circularity. It must cover:
  - the forbidden set, imported from `WATCHDOG_DISPATCH_TABLE`, plus the verifier list in the test
    file;
  - a scan of `server/inngest/**/*.{ts,mjs}` plus every served closure;
  - the exact `cron-ux-audit.ts` exemption `{ botFixturePath: 2, botSigninPath: 1 }`;
  - the directory scan through `fs.listFiles`, with filtering inside the helper;
  - workflow-existence staleness;
  - mutation rows 1–7 and harness rows H1–H2.
- [x] 1.5 Guard 4: the serve-URL anchor. It must check:
  - one module reaching a `serve` adapter, including namespace, default and `require` forms;
  - the production `SERVE_HOST` literal is `"https://app.soleur.ai"`, checked by AST;
  - `serveHost` references `SERVE_HOST`;
  - mutation rows 1–4 and harness rows H1–H2.
- [x] 1.6 At least one RED row per guard asserts that the failure message names the fix.
- [x] 1.6a All fixtures are synthesized (synthetic ids and module names). No row copies or mutates a
      tracked file. The real-tree test and the fixture tests call the same helper, differing only
      in `fs`.
- [x] 1.7 Run `./node_modules/.bin/vitest run test/server/inngest/execution-placement.test.ts`.
      Expect RED, because the leaf is missing.

## Phase 2: GREEN — the manifest leaf

- [x] 2.1 Discovery pass: print `derivePinning` for every served function. Use its output, not the
      plan's regex table, to seed the rows.
- [x] 2.2 Create `apps/web-platform/server/inngest/execution-placement.ts`. It is import-free, with
      a header modelled on `cron-manifest.ts` that states the `onFailure` inheritance rule. It
      exports the `ExecutionPlacement` type and `EXECUTION_PLACEMENT`, with one row per served
      function and a reason on every non-`portable` row.
- [x] 2.3 Re-class tighter on any Guard 2 hit. Never widen the allowlist. Note each divergence
      from the plan's tables in the PR body.
- [x] 2.4 Run the suite: GREEN. Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 3: Registry test cross-reference

- [x] 3.1 In `function-registry-count.test.ts`, add a class-neutral comment next to
      "UPDATE this number" pointing to `EXECUTION_PLACEMENT` and Guard 1. It is a comment only.

## Phase 4: ADR amendments (full filenames)

- [x] 4.1 `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`:
  - [x] 4.1.1 Append `## Amendment — 2026-09-28 (#7230): execution placement`, containing:
    - the decision table;
    - the three classes;
    - a pointer to the test;
    - single-host enforcement: Guard 4 plus (g) plus Condition C;
    - the allowlist sentence;
    - the `onFailure` rule;
    - the re-open triggers and #9137;
    - four known gaps;
    - the re-derived corollary table (#9138; never call native `schedule:` reliable).
  - [x] 4.1.2 In the corollary sub-bullet, correct in place the "pinned to web-1 by the single
        `sdk_url` callback" claim and the "~34 of 53" count. Mark it `[corrected 2026-09-28, #7230]`.
  - [x] 4.1.3 Registration checklist: add row 8 (class-neutral) and change "seven" to "eight",
        with a revision note.
- [x] 4.2 `ADR-030-inngest-as-durable-trigger-layer.md`: one amendment-log pointer line.
- [x] 4.3 `ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md`: fix the "via `sdk_url`"
      wording in the failure-domain row, and re-point the "(#7230)" reversal trigger to #9137.
- [x] 4.4 `ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md`: add a placement line to
      the #8611 amendment.
- [x] 4.5 `ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`: add a dated one-line
      note under Decision sub-item 1 saying step fan-out follows `serveHost` +
      `cloudflare_record.app` + the placement classes, not `--sdk-url`.
- [x] 4.6 The ADR-033 amendment also carries:
  - the P1-2 target constraint (per-class app ids or function-aware ingress);
  - the `host-affine` stickiness and co-location rule (`CRON_WORKSPACE_ROOT`, deploy lease,
    `cron-workspace-gc`);
  - the `volume-bound` definition, which is the sole-copy LUKS holder;
  - the sanctioned Inngest-scheduled watchers row;
  - the best-effort wording for `scheduled-prod-version-drift`.

## Phase 5: C4

- [x] 5.1 `model.c4`: edit the `inngest -> api` edge prose to name the single step-executing host
      (web-1) and the registration-only `--sdk-url`, and point to the placement rule, with no
      counts.
  - Re-source `inngest -> supabase`, `inngest -> github` (ghcr token minter) and
    `inngest -> doppler` to `api`, each annotated "(Inngest-fired function, executed on web-1)".
  - Before editing, grep `views.c4` for these edges.
- [x] 5.2 Let the lefthook `c4-model-regenerate` step regenerate and re-stage `model.likec4.json`.
      Never hand-edit it. If the hook is skipped, run `bash scripts/regenerate-c4-model.sh`.
      Review the `c4-model.md` `## Notes` advisory.
- [x] 5.3 Run `test/c4-code-syntax.test.ts`, `test/c4-render.test.ts`,
      `bash plugins/soleur/test/c4-count-parity.test.sh` and
      `bash plugins/soleur/test/c4-model-freshness.test.sh`.

## Phase 6: Verify and ship prep

- [x] 6.1 Run the targeted vitest set: execution-placement, function-registry-count,
      watchdog-dispatch-clock, and the c4 tests.
- [x] 6.2 Run `npx markdownlint-cli2` on the edited `.md` files.
- [x] 6.3 Check that `git diff --name-only origin/main...HEAD` has no `apps/web-platform/infra/`,
      no `.github/workflows/`, and no `app/api/inngest/route.ts`.
- [ ] 6.4 PR body:
  - the first line is the merge-consequence statement;
  - `Closes #7230`;
  - links to #9137 and #9138;
  - the walker-equivalence evidence;
  - any discovery divergences;
  - the decision-challenges render.
