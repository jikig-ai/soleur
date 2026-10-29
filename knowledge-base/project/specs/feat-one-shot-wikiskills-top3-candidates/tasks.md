# Tasks - create arm shows the server's per-pattern top-3 candidates (Ref #10550)

Plan: `knowledge-base/project/plans/2026-10-29-feat-create-arm-top3-candidates-in-prompt-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-wikiskills-top3-candidates/decision-challenges.md`
Constraints: do not fire `cron-compound-promote` or `soleur:trigger-cron`; never `git stash`; "Ref #10550" only (no comment, no close); touch no other issue; the `nearest-not-top3` gate and its tests stay intact; claim no PR-opening effect.

## Phase 1 - Tests first (RED)

All in `apps/web-platform/test/server/compound-promote-create.test.ts` (new describe after the `prepareCreate` describe), plus one line in `compound-promote-marker-numbers.test.ts`.

- 1.1 Equality with the gate: `createCandidates(page, SKILLS)` equals an independent recompute from `rankOverlap(patternOverlapText(page), SKILLS)` minus hidden skills, minus score 0, first `OVERLAP_TOP_K` (never built from the function under test).
- 1.2 A hidden top scorer is never listed.
- 1.3 IDF population: a synthetic fixture where visible-only ranking orders two skills differently from all-skills ranking; candidates follow the all-skills order.
- 1.4 Zero score is not a candidate; a pattern with two positive scores lists two; a pattern with none has no line and the prompt carries the "no line, do not create from it" bullet.
- 1.5 Per-offered only: two patterns give two lines, one pattern gives one, never a non-offered pattern.
- 1.6 Fenced `create-candidates` block between the pattern index and the skill list.
- 1.7 Ceiling counts the block: `numbers.bytes` equals index + block + skill block rebuilt independently; a fixture that fits without the block and overflows with it is refused.
- 1.8 Prompt rules: existing anchored overlap sentence unchanged; three new bullets asserted in anchored sentences built from `OVERLAP_TOP_K` and `CREATE_NO_ACTION_REASONS` (escape hatch names `no-pattern-qualifies`).
- 1.9 `nearest_in_offered`: 1 / 0 on `nearest-not-top3` with candidates (fixture picks a listed candidate the proposal text pushes below rank 3, precondition asserted); absent on `overlap`, `nearest-missing`, `open-pr-nearest` and when no candidates were offered; two-pattern case uses the named pattern.
- 1.10 Harness self-check row: test 1.1's expectation is not tautological. Marker-numbers census: `nearest_in_offered` in `CREATE_SENTRY_ONLY_NUMBERS`, absent from `CREATE_MARKER_NUMBERS`.
- 1.11 Run them; confirm they fail for the right reason (missing exports).

## Phase 2 - Pure module (`apps/web-platform/server/compound-promote-create.ts`)

- 2.1 Export `patternOverlapText` (title + summary + tags), `hiddenSkillNames` (one expression, also used by `checkCreate`), `createCandidates` (all-skills ranking, drop hidden, score > 0, first `OVERLAP_TOP_K`).
- 2.2 `prepareCreate`: compute candidates for `args.patterns`; fenced `create-candidates` block (`<pattern_slug>: a, b, c`, body `none` when empty) between the pattern index and the skill list; add its bytes to `inputBytes`; keep every existing prompt line verbatim; add the three bullets next to the overlap bullet.
- 2.3 `checkCreate`: in the `nearest-not-top3` branch only, add `nearest_in_offered` (0/1) to the refusal numbers when candidates exist for the named pattern. Class, detail, `nearest_rank`, `top1` unchanged.

## Phase 3 - Marker allowlist

- 3.1 `apps/web-platform/server/compound-promote-marker.ts`: add `"nearest_in_offered"` to `CREATE_SENTRY_ONLY_NUMBERS`; no other mention of the key in the file; `CREATE_MARKER_NUMBERS` untouched.

## Phase 4 - Runbook and ADR

- 4.1 Runbook row "`refused`, `prefer-patch`, `nearest-not-top3`": candidates now supplied, residual risk, the three readings of `extra.nearest_in_offered` (absent, 0, 1), the paths that carry it and those that do not, the single-re-rank flip condition, no PR-opening claim.
- 4.2 One clause near the `create_top1` / `create_nearest_rank` field row pointing at that row.
- 4.3 ADR-092: one amendment paragraph, "Amendment, 2026-10-29 (#10550)", after the 2026-10-28 amendment.

## Phase 5 - Verify (GREEN)

- 5.1 From `apps/web-platform`: `./node_modules/.bin/vitest run` on the seven compound-promote suites named in the plan, and `./node_modules/.bin/tsc --noEmit`.
- 5.2 markdownlint on the runbook and ADR-092; `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 5.3 Re-run the plan-time probe: every open real pattern has at least one candidate; `prepareCreate` is `ready`; record the byte count.
- 5.4 `git diff origin/main...HEAD` on the existing gate tests (~L984-1005) and the anchor regex (~L1246): additions only. `compound-promote-patterns.ts` and `compound-promote-create-arm.ts` byte-identical to `origin/main`.

## Phase 6 - Ship (pipeline stages)

- 6.1 PR body: "Ref #10550" (never "Closes"); candidates shown, gate unchanged, expected to reduce but not remove `nearest-not-top3`, no PR-opening claim; render `decision-challenges.md`.
- 6.2 After merge: verify the deploy, then `soleur:postmerge`.
- 6.3 Live-fire is an operator hold: ask for the explicit go-ahead naming the action; do not fire any trigger otherwise.
