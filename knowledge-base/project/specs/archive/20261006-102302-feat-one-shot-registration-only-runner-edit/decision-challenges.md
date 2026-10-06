# Decision challenges: registration-only runner edits (plan-review, headless, 2026-10-05)

Persisted by plan-review for `ship` Phase 6 to render. The operator's stated direction is the default in every row.

## User-Challenge 1 - cut the index-declaration slice (Phase 2b)

- Operator direction: "a new AFFECTED_*_PATHS array" is a registration-only shape (named in the brief).
- Reviewers (DHH, code-simplicity): cut it. Measured since 2026-06-01: 5 of 142 registration-only runner commits (3.5%) touched the index (4 array blocks, 1 entry); Phase 2a alone serves ~96% of the measured demand and removes the label-to-array injectivity machinery, matrix rows 5/6/14 and the narrowing-by-data risk.
- Default kept: implement Phase 2b as a separate, droppable commit after 2a. Say "drop 2b" to skip it; no 2a line changes.

## Taste 2 - "measure before building"; the saving is 36%

- A registration-only run is still about 58.6 min at manifest weights (vs 91.4 full). The banner-and-help slice (Phase 1) is independent and ships first; the classifier follows. If the operator prefers to stop after Phase 1 and gather real PR-level hit-rate data, Phases 2a/2b are separable.

## Taste 3 - drop blank/comment admission (shrinks the anchor rule)

- Measured: 115 of 137 runner-only registration commits carry a comment or blank line beside the registration (only 22 do not), so dropping them would cut the hit rate by about 84%. Default: keep, with the anchor rule binding every added line.

## Taste 4 - matrix size (15 rows + 5 harness rows) and anchor-rule simplicity

- Default: keep; the Guard Contract requires design-derived rows and each row answers a named slip. Rows may merge during work if two prove to share one code path.

## Taste 5 - SUITE_GLOBS auto-discovery of root `scripts/*.test.sh`

- Cut in the plan (162 explicit registrations; the glob edit is itself a semantic runner edit; removes the reviewed-registration property). Surfaced because it would remove the need for most runner edits at all.
