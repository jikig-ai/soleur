# Decision challenges: feat-one-shot-8616-hook-suite-missing-dep-unresolved

Plan-review findings recorded in a headless run. They are **Taste**: the plan went one way and a
reviewer argued the other. `ship` Phase 6 renders them into the PR body.

## 1. Test the missing-dependency case behaviorally, or with a static lint only? (Taste)

- **Plan (kept):** `.claude/hooks/hook-suite-dep-unresolved.test.sh` runs each guarded hook suite
  again with the guarded tool removed from PATH. It requires a non-zero exit and an
  `UNRESOLVED: <tool> missing` line. A static `SKIP … exit 0` sweep backs this up.
- **Challenge (DHH review):** drop the PATH farm and keep only the static rule, "every guard line
  carries `UNRESOLVED:` and `exit 3`". That removes the farm, the floor, the `PROMOTED_FILES` ledger
  entry and the self-tests.
- **Why the plan kept it:**
  - Issue #8616's third acceptance item asks that "a dependency-less environment produces a not-green
    verdict", and only a run without the tool shows that.
  - The two partial-arm suites (`hookeventname-coverage` via `fail=1`, `pre-merge-rebase-parity` via
    its case floor) produce their verdict somewhere a line rule cannot see.
  - The cost is measured at seconds.
- **Other lead guidance:** the one-shot lead expected "a sweep/lint over the hook suites is the likely
  shape". The plan's static sweep covers the file-under-test arms; it is the behavioral layer that
  goes beyond that expectation.
- **To reverse:** delete the behavioral layer and keep the static sweep plus a per-line canonical-form
  check. Rows M3 and M4 then become one-time manual checks.

## 2. Exit code for grep-rewrite and settings-hook-exec-bit when jq is missing (Taste)

- **Plan:** move both suites from exit 1 to exit 3, the same as every other hook suite whose required
  tool is missing.
- **Challenge (code-simplicity review):** leave them at exit 1 and only reword the message. Both are
  already not-green, so the change is invisible upstream.
- **Why the plan changes them:** acceptance item 2 asks for uniform application, and the edit already
  touches that line.
