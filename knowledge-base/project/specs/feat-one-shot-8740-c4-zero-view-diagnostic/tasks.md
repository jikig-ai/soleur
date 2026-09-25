# Tasks: fix(c4): zero-view model diagnostic on GET /api/kb/c4/project (#8740)

Plan: `knowledge-base/project/plans/2026-09-25-fix-c4-zero-view-model-project-diagnostic-plan.md`.
Ref #8740. Do not close it. Do not write to any tenant repository.

## Phase 1: Setup

- [ ] 1.1 Re-read the plan's Phase 1, Sharp Edges and Acceptance Criteria.
- [ ] 1.2 Confirm the one-reader census for `Diagnostic.line`: `grep -rn "d\.line\|\.line\b" apps/web-platform/components/kb` should show `c4-diagnostics.tsx` only, plus the unrelated `search-overlay.tsx`.

## Phase 2: Core Implementation (RED first, then GREEN)

- [ ] 2.1 Shared helper
  - [ ] 2.1.1 Create `apps/web-platform/lib/c4-model-shape.ts` exporting `plainObjectSize` (pure, no imports).
  - [ ] 2.1.2 In `apps/web-platform/server/c4-render.ts`, import it and delete the local copy (3 call sites).
- [ ] 2.2 Route tests (RED), in `apps/web-platform/test/c4-project-route.test.ts`
  - [ ] 2.2.1 Add a hoisted `mockMirrorWarnWithDebounce` spy to the observability mock. This is required, not optional.
  - [ ] 2.2.2 T1: zero-view model → one diagnostic (exact copy literal, `line: 0`, `sourceFsPath: "model.likec4.json"`), and the spy called once with `null`, the ctx, key `ws-1:engineering/architecture/diagrams` and errorClass `c4-project-read:zero-view-model`.
  - [ ] 2.2.3 T2: model with views → `[]`, spy not called.
  - [ ] 2.2.4 T3: empty model → `[]`, spy not called.
  - [ ] 2.2.5 T4 (`it.each`), all returning 200:
    - absent `views` → diagnostic;
    - `views: []` → diagnostic;
    - `elements: ["x"]` → none;
    - `elements: "xy"` → none.
- [ ] 2.3 Strip tests (RED), in `apps/web-platform/test/c4-shared.test.tsx`
  - [ ] 2.3.1 S1: `line: 0` →
    - "Diagram warnings" is shown and "Diagram has errors" is absent;
    - the item text is exactly `M`;
    - no "line 0".
  - [ ] 2.3.2 S2: `line: 3` → the item text is exactly `line 3: bad ref`.
- [ ] 2.4 Route (GREEN), in `apps/web-platform/app/api/kb/c4/project/route.ts`
  - [ ] 2.4.1 Add the non-exported `ZERO_VIEW_DIAGNOSTIC` with the plan's final copy.
  - [ ] 2.4.2 Compute `elementCount` with `plainObjectSize`, and leave the `viewIds` derivation unchanged.
  - [ ] 2.4.3 On zero views with elements present: add the diagnostic and call `mirrorWarnWithDebounce(null, …)`. The literal `op: "zero-view-model"` must appear exactly once in the file.
- [ ] 2.5 Strip (GREEN), in `apps/web-platform/components/kb/c4-diagnostics.tsx`
  - [ ] 2.5.1 Render the `line N:` prefix only when `d.line > 0`.
  - [ ] 2.5.2 Add a comment reserving `line <= 0` for model-level diagnostics.
- [ ] 2.6 Add the errorClass registry line in `apps/web-platform/server/observability.ts`: `c4-project-read:zero-view-model`, permanent read-side canary.
- [ ] 2.7 Follow-through probe
  - [ ] 2.7.1 Write `scripts/followthroughs/c4-zero-view-model-8740.test.sh` first (RED). Stub `curl` and `git` on `PATH`. Cover the nine rows in plan Phase 1 item 5, including:
    - the "signal wins" row;
    - the not-deployed row (exit 2);
    - the liveness-absent row (exit 3);
    - the `environment%3Aproduction` row;
    - the route-literal drift row.
  - [ ] 2.7.2 Write `scripts/followthroughs/c4-zero-view-model-8740.sh`:
    - check order: signal → /health `build_sha` ancestry → server-startup liveness;
    - exit codes 0/1/2/3;
    - `SENTRY_ACTIONS_RO_TOKEN` only, with no `${VAR:?}`;
    - the xtrace refusal block;
    - a header with the exit contract, how to stop FAIL comments, and the `RETIREMENT:` order.
  - [ ] 2.7.3 `chmod +x` both scripts, and `git update-index --chmod=+x` both.
  - [ ] 2.7.4 Register the test in `scripts/test-all.sh` beside the other follow-through suites.

## Phase 3: Testing

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-project-route.test.ts test/c4-shared.test.tsx test/c4-render.test.ts test/c4-render-boundary.test.ts test/c4-workspace.test.tsx test/c4-diagram.test.tsx`
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 3.3 `bash scripts/followthroughs/c4-zero-view-model-8740.test.sh` and `bash scripts/lint-followthrough-varq-ban.sh`
- [ ] 3.4 `git grep -n "function plainObjectSize" -- apps/web-platform` prints exactly one line.
- [ ] 3.5 At QA, attach a screenshot of the zero-view workspace state at the minimum left-panel width.

## Phase 4: Ship (issue hygiene, automated)

- [ ] 4.1 PR body: `Ref #8740` and the Re-render Decision summary. No closing keyword in the title or body.
- [ ] 4.2 After deploy:
  - paste the verbatim `<!-- soleur:followthrough … -->` block into #8740, unfenced, with `earliest` = deploy + 14 days;
  - add the `follow-through` label;
  - run the sweeper with `dry_run=true` and confirm #8740 is parsed.
- [ ] 4.3 Comment on #8740 with:
  - what shipped;
  - options (a), (b) and (c);
  - the close rule;
  - how to stop FAIL comments.
- [ ] 4.4 Comment on #8739 naming the "then reload the page" clause to remove when it ships.
