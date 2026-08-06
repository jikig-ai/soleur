# Tasks — lint-diagnosis-claims infra scope (#7310)

Plan: `knowledge-base/project/plans/2026-08-06-fix-lint-diagnosis-claims-infra-scope-plan.md`
Branch: `feat-one-shot-7310-lint-diagnosis-claims-infra-scope` · PR #7315 · closes #7310

Phase order is load-bearing: the RED fixture lands before the two GREEN edits, so the
fixture is observed failing. A fixture that passes before the fix tests nothing.

## Phase 1 — RED: the regression fixture

- [ ] **1.1** In `scripts/lint-diagnosis-claims.test.sh`, extend the fixture-tree setup
      (`mkdir -p "$FIX/.github/workflows" "$FIX/.github/actions/some-action"`) to also create
      `"$FIX/apps/web-platform/infra"`.
- [ ] **1.2** In ARM 1 (fixtures that MUST trip), add a synthesized
      `apps/web-platform/infra/registry-userdata-budget.sh` fixture carrying the verbatim
      historical message ending `#7280's registry_rationale_strip is the fix.`
      Synthesize the surrounding script (`cq-test-fixtures-synthesized-only`); quote only the
      offending sentence, exactly as ARM 1 already does for the two historical offenders.
- [ ] **1.3** Assert `census_of "$FIX"` is `1`, with a comment naming what the case pins:
      the directory (part 1) **and** the phrasing (part 2). Then `rm` the fixture.
- [ ] **1.4** Run `bash scripts/lint-diagnosis-claims.test.sh`. It **must fail**. Record the
      failure output — this is the proof the fixture is load-bearing.

## Phase 2 — GREEN: scope

- [ ] **2.1** `scripts/lint-diagnosis-claims.sh:61` — add `"apps/web-platform/infra"` to `DIRS`.
- [ ] **2.2** Update the `SCOPE.` header prose (`:18-23`) to name the fourth directory and
      why it matters: it is where the `registry_rationale_strip is the fix` message shipped,
      invisible to this lint for the same reason `.github/actions/` was invisible to
      `lint-workflows.sh`.
- [ ] **2.3** Update the `DIRS` inline comment (`:54-60`) to match. Leaving either prose block
      stale makes the file's own documentation lie about its scope.

## Phase 3 — GREEN: the CLAIM alternative

- [ ] **3.1** `scripts/lint-diagnosis-claims.sh:75-80` — append the alternative
      `\bis the (?:fix|cause)\b` to `CLAIM`. Keep both `\b` anchors; both are load-bearing
      (they block `This the fix`, `is the fixture`, `is the fixed`, `is the causes`).
- [ ] **3.2** Run the suite. It must now be green.

## Phase 4 — Verify

- [ ] **4.1** AC1/AC2 — `grep -c 'apps/web-platform/infra' scripts/lint-diagnosis-claims.sh` ≥ 1;
      `grep -cF 'is the (?:fix|cause)' scripts/lint-diagnosis-claims.sh` = 1.
- [ ] **4.2** AC3 — `bash scripts/lint-diagnosis-claims.sh`; assert **stdout** reads
      `lint-diagnosis-claims: OK — 1 unmeasured causal claims (baseline 1)`.
      Do not read `$?` as the verdict.
- [ ] **4.3** AC4 — `bash scripts/lint-diagnosis-claims.sh --census` prints `1`.
- [ ] **4.4** AC5 — `bash scripts/lint-diagnosis-claims.test.sh` → **12 passed, 0 failed**.
- [ ] **4.5** Update the `MIN_ASSERTIONS` parenthetical (`:201`) from
      `(11 at time of writing)` to `12`. The floor value `9` stays.
- [ ] **4.6** AC6 — confirm `scripts/lint-diagnosis-claims.highwater` is untouched:
      `git diff --name-only origin/main...HEAD | grep -c highwater` = 0.
- [ ] **4.7** AC7 — mutation test, **both arms**: revert only `DIRS` → suite fails; restore.
      Revert only the `CLAIM` alternative → suite fails; restore.
- [ ] **4.8** AC8 — `SCOPE.` header names `apps/web-platform/infra`.
- [ ] **4.9** AC9 — `bash scripts/test-all.sh` `scripts` shard green.
      Do not run `run-registered-suites.sh` concurrently (shared `TMPDIR` → false RED).

## Phase 5 — Follow-up

- [ ] **5.1** AC10 — file the `OPERATOR_LINE` anchor-gap issue. Body must carry the measured
      delta (un-anchoring to `(?:^|\|\||&&|;)` moves the census 1 → 2, i.e. a red required
      check), name `.github/workflows/reusable-release.yml:1289`, and state that the message
      there is hedged (*"a plausible cause"*) so the first question is whether it is a genuine
      claim or a false positive. Label `type/chore`, `domain/engineering`.
