# Tasks — lint-diagnosis-claims infra scope (#7310)

Plan: `knowledge-base/project/plans/2026-08-06-fix-lint-diagnosis-claims-infra-scope-plan.md`
Branch: `feat-one-shot-7310-lint-diagnosis-claims-infra-scope` · PR #7315 · closes #7310

Phase order is load-bearing: the RED fixture lands before the two GREEN edits, so the
fixture is observed failing. A fixture that passes before the fix tests nothing.

## Phase 1 — RED: the regression fixture

- [x] **1.1** In `scripts/lint-diagnosis-claims.test.sh`, extend the fixture-tree setup
      (`mkdir -p "$FIX/.github/workflows" "$FIX/.github/actions/some-action"`) to also create
      `"$FIX/apps/web-platform/infra"`.
- [x] **1.2** In ARM 1 (fixtures that MUST trip), add a synthesized
      `apps/web-platform/infra/registry-userdata-budget.sh` fixture carrying the verbatim
      historical message ending `#7280's registry_rationale_strip is the fix.`
      Synthesize the surrounding script (`cq-test-fixtures-synthesized-only`); quote only the
      offending sentence, exactly as ARM 1 already does for the two historical offenders.
- [x] **1.3** Assert `census_of "$FIX"` is `1`, with a comment naming what the case pins:
      the directory (part 1) **and** the phrasing (part 2). Then `rm` the fixture.
- [x] **1.4** RED observed: `EXIT=1`, `11 passed, 1 failed`, the new case reporting
      `expected: 1 / actual: 0` — the directory was out of scope, exactly as predicted.

## Phase 2 — GREEN: scope

- [x] **2.1** `scripts/lint-diagnosis-claims.sh:61` — add `"apps/web-platform/infra"` to `DIRS`.
- [x] **2.2** Update the `SCOPE.` header prose (`:18-23`) to name the fourth directory and
      why it matters: it is where the `registry_rationale_strip is the fix` message shipped,
      invisible to this lint for the same reason `.github/actions/` was invisible to
      `lint-workflows.sh`.
- [x] **2.3** Update the `DIRS` inline comment (`:54-60`) to match. Leaving either prose block
      stale makes the file's own documentation lie about its scope.

## Phase 3 — GREEN: the CLAIM alternative

- [x] **3.1** `scripts/lint-diagnosis-claims.sh:75-80` — append the alternative
      `\bis the (?:fix|cause)\b` to `CLAIM`. Keep both `\b` anchors; both are load-bearing
      (they block `This the fix`, `is the fixture`, `is the fixed`, `is the causes`).
- [x] **3.2** Suite green: **12 passed, 0 failed**. Also confirmed the lint does not
      self-flag: the new regex line is not an `OPERATOR_LINE` (the helper-call alternative
      needs whitespace before the quote; `r"` has none) and the new comment starts with `#`,
      which the scanner skips. `scripts/` is in scope, so this was worth measuring, not
      assuming.

## Phase 4 — Verify

- [x] **4.1** AC1 — `grep -c 'apps/web-platform/infra' scripts/lint-diagnosis-claims.sh` = 4 (≥ 1 ✓).
      AC2 (amended) — `grep -cE '^\s*r"\\bis the \(\?:fix\|cause\)\\b"' scripts/lint-diagnosis-claims.sh` = 1 ✓.
      The original bare-literal `grep -cF` form returned 2 (the explanatory comment also
      carries the literal) and, worse, still returned 1 with the regex line deleted — it
      would have passed on a broken lint. Re-anchored on the regex construct.
- [x] **4.2** AC3 — stdout read `lint-diagnosis-claims: OK — 1 unmeasured causal claims
      (baseline 1).` Verdict taken from the message, not `$?`.
- [x] **4.3** AC4 — `--census` printed `1`.
- [x] **4.4** AC5 — **12 passed, 0 failed**.
- [x] **4.5** `MIN_ASSERTIONS` parenthetical updated to `12`; floor value `9` unchanged
      (still has headroom).
- [x] **4.6** AC6 — `git diff --name-only origin/main...HEAD | grep -c highwater` → `0`.
- [x] **4.7** AC7 — mutation test, both arms: `DIRS`-only revert → 11/1; `CLAIM`-only revert
      → 11/1; baseline restored → 12/0. Each mutation asserted its anchor present before
      writing, and the restore was verified clean via `git diff --quiet`.
- [x] **4.8** AC8 — `SCOPE.` header names `apps/web-platform/infra/`.
- [x] **4.9** AC9 — **rc=0, `=== 267/267 suites passed ===`**, 0 `[FAIL]` lines,
      `[ok] scripts/lint-diagnosis-claims (1085ms)`. Preamble showed `siblings: 0` +
      `LOCK_ACQUIRED` (clean run, not a contention artifact); epilogue stated
      `apps/web-platform/infra/ is NOT covered above (diff does not touch it)`, which is
      correct here — the change scans that directory, it does not edit it.
      Full `bash scripts/test-all.sh`, launched detached under
      `setsid nohup` with `TMPDIR=/var/tmp` against a clean tree. Read the **rc file** plus
      the terminal `=== N/M suites passed ===` marker and the coverage epilogue — not the
      completion notification, which reports the wrapper's exit. Pre-launch contention
      check: `/tmp` at 28%, no sibling runs, load 1.6.

## Phase 5 — Follow-up

- [x] **5.1** AC10 — filed as **#7318** (`type/chore`, `domain/engineering`, `priority/p3-low`,
      milestone *Post-MVP / Later*). Body carries the measured delta (un-anchoring to
      `(?:^|\|\||&&|;)` moves the census 1 → 2, i.e. a red required check), names
      `.github/workflows/reusable-release.yml:1289`, and leads with the judgment question —
      the message is hedged (*"a plausible cause"*, *"if Sigstore/Fulcio is down"*) and the
      helper receives `"$?"`, so it may be a false positive rather than a defect.
      Net issue flow: closing 1 (#7310), filing 1 (#7318), net 0.
