# Tasks: fix(c4): zero-view model diagnostic on GET /api/kb/c4/project (#8740)

Plan: `knowledge-base/project/plans/2026-09-25-fix-c4-zero-view-model-project-diagnostic-plan.md`
(deepened 2026-09-25). Ref #8740, Ref #8861. Do not close #8740. Do not write to any tenant repository.

## Phase 1: Setup

- [ ] 1.1 Re-read the plan's Phase 1, Guard Contract, Sharp Edges and Acceptance Criteria.
- [ ] 1.2 Confirm the one-reader census for `Diagnostic.line`: `grep -rn "d\.line\|\.line\b" apps/web-platform/components/kb` should show `c4-diagnostics.tsx` only, plus the unrelated `search-overlay.tsx`.

## Phase 2: Core Implementation (RED first, then GREEN)

- [ ] 2.1 Shared model shape
  - [ ] 2.1.1 Create `apps/web-platform/lib/c4-model-shape.ts`. It is pure, with no imports, and exports:
    - `c4ModelCounts`;
    - `type Diagnostic`;
    - `MODEL_LEVEL_LINE = 0`.
  - [ ] 2.1.2 `components/kb/c4-shared.tsx` re-exports `Diagnostic`.
  - [ ] 2.1.3 `server/c4-render.ts` uses `c4ModelCounts` in the `empty_model` and `layout_failed` gates and in the self-probe, and deletes `plainObjectSize`.
- [ ] 2.2 Route tests (RED), in `apps/web-platform/test/c4-project-route.test.ts`
  - [ ] 2.2.1 Add a hoisted `mockMirrorWarnWithDebounce` spy to the observability mock. This is mandatory.
  - [ ] 2.2.2 T1: canonical-dir zero-view → one diagnostic with the exact copy, `line: 0` and `model.likec4.json`. The spy is called with:
    - `null`;
    - the ctx (`feature`, `op`, `message`, and no `tags`);
    - the key `ws-1:<modelEntry.path>`;
    - the errorClass.
  - [ ] 2.2.3 T2 (with views) and T3 (empty model) → `[]`, spy not called.
  - [ ] 2.2.4 T4 (`it.each`): absent `views` or `views: []` → diagnostic; `elements` an array or a string → none.
  - [ ] 2.2.5 T5: non-canonical dir → the other-dir copy, with no "Concierge".
  - [ ] 2.2.6 T6: malformed dirs → 400 with zero GitHub calls; the canonical dir → 200.
  - [ ] 2.2.7 T7: the same model → the same debounce key.
- [ ] 2.3 Strip tests (RED), in `apps/web-platform/test/c4-shared.test.tsx`
  - [ ] 2.3.1 S1: `line: 0` and `line: -1` →
    - "Diagram warnings" is shown and "Diagram has errors" is absent;
    - the item text is exactly `M`;
    - no "line 0".
  - [ ] 2.3.2 S2: `line: 3` → the item text is exactly `line 3: bad ref`.
- [ ] 2.4 Concierge copy test (RED): add C1 to `apps/web-platform/test/c4-concierge-copy.test.ts`, one addendum-only `it` checking the anchor phrases.
- [ ] 2.5 Route (GREEN), in `apps/web-platform/app/api/kb/c4/project/route.ts`
  - [ ] 2.5.1 `dir` hardening:
    - length ≤ 256;
    - an escape-only control and line-separator regex;
    - a per-segment allowlist;
    - per-segment `encodeURIComponent` in `githubDir`.
  - [ ] 2.5.2 Add the non-exported `ZERO_VIEW_DIAGNOSTIC` and `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR`.
  - [ ] 2.5.3 Detect with `c4ModelCounts`, leaving the `viewIds` derivation unchanged. On a zero-view model:
    - add the diagnostic, typed `Diagnostic[]`;
    - call `mirrorWarnWithDebounce(null, …, \`${activeWorkspaceId}:${modelEntry.path}\`, "c4-project-read:zero-view-model")`.
    - The literal `op: "zero-view-model"` appears exactly once in the file.
- [ ] 2.6 Strip (GREEN), in `components/kb/c4-diagnostics.tsx`: render the prefix only when `d.line > MODEL_LEVEL_LINE`, with the reservation comment.
- [ ] 2.7 Concierge (GREEN): append the plan's sentence to `C4_PROMPT_ADDENDUM` in `server/c4-concierge-tools.ts`. Run both copy suites.
- [ ] 2.8 Add the errorClass registry line in `server/observability.ts`.
- [ ] 2.9 Add the ADR-050 addendum paragraph on its own lines. Do not touch the `Failure classes:` line.
- [ ] 2.10 Follow-through probe
  - [ ] 2.10.1 Write `scripts/followthroughs/c4-zero-view-model-8740.test.sh` first (RED):
    - its own `pass`/`fail` counters and an instrument self-test;
    - `curl` and `git` stubs that log their argv, exit 99 on anything unrouted, and are scoped to the probe run;
    - rows 1-15 from plan Phase 1 item 8, each asserting the exit code, the reason line and a non-empty call log.
  - [ ] 2.10.2 Write `scripts/followthroughs/c4-zero-view-model-8740.sh`:
    - check order: token → signal → /health `build_sha` validation, INTRO, `cat-file`, `merge-base` → liveness;
    - exit codes 0/1/2/3;
    - the curl flags from the plan, with the token sent via `-H @-`;
    - `environment:production` and the project pin on both queries;
    - the public-repo output rules;
    - a header with the exit contract, how to stop FAIL comments, the forgeable-signal residual risk and the `RETIREMENT:` order.
  - [ ] 2.10.3 `chmod +x` both scripts and `git update-index --chmod=+x` both.
  - [ ] 2.10.4 Register the test in `scripts/test-all.sh`.

## Phase 3: Testing

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-project-route.test.ts test/c4-shared.test.tsx test/c4-render.test.ts test/c4-render-boundary.test.ts test/c4-workspace.test.tsx test/c4-diagram.test.tsx test/c4-concierge-copy.test.ts test/c4-prompt-addendum-honesty.test.ts`
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 3.3 `bash scripts/followthroughs/c4-zero-view-model-8740.test.sh` and `bash scripts/lint-followthrough-varq-ban.sh`
- [ ] 3.4 `git grep -n "function plainObjectSize" -- apps/web-platform` prints exactly one line.
- [ ] 3.5 At QA, attach a screenshot of the zero-view workspace state at the minimum left-panel width.

## Phase 4: Ship (issue hygiene, automated)

- [ ] 4.1 PR body: `Ref #8740`, `Ref #8861`, and the Re-render Decision summary. No closing keyword in the title or body.
- [ ] 4.2 After deploy:
  - paste the verbatim `<!-- soleur:followthrough … -->` block into #8740, unfenced, with `earliest` = deploy + 14 days;
  - add the `follow-through` label;
  - run the sweeper with `dry_run=true` and confirm #8740 is parsed.
- [ ] 4.3 Comment on #8740 with:
  - what shipped;
  - options (a), (b) and (c);
  - the close rule;
  - how to stop FAIL comments.
- [ ] 4.4 Comment on #8739 naming the three "then reload the page" clauses to remove: the two route copies and the addendum.
