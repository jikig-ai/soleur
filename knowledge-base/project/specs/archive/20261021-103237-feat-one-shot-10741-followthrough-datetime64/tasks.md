# Tasks — fix(followthrough): web2-plugin-seed-8743 probe can never grade (DateTime64)

Plan: `knowledge-base/project/plans/2026-10-21-fix-followthrough-web2-plugin-seed-datetime64-plan.md`
Issue: #10741 (closes). Tracker under verification: #8743.

## Phase 1 — Failing test first (RED)

- 1.1 In `scripts/followthroughs/web2-plugin-seed-8743.test.sh`, extend the `bsq` stub's `case "$*"` dispatch with a ClickHouse-strictness arm: when the SQL carries `toDateTime('<literal containing a fraction>')` (pattern matching `toDateTime(` directly followed by `'….'<digits>'` — the `toDateTime64(` spelling must NOT match), print the production-shaped rejection `Code: 6. DB::Exception: Cannot parse string '…' as DateTime: syntax error` and exit nonzero (mirroring the observed `curl: (22)` → `betterstack-query.sh` rc).
  - 1.1.1 Keep arm order: the `*first_marker_dt*` scan arm first (the scan query embeds the alias), the strictness arm before the `*` count fallthrough.
  - 1.1.2 Suggested glob: `*"toDateTime('"*"."[0-9][0-9][0-9][0-9][0-9][0-9]"'"*` (6-digit fraction — the rendered precision the production value carried).
- 1.2 Add the fractional-marker fixture case: `scan_row 9 2 1 4 "2026-10-19 05:12:33.456789" 1` + `count_row 0` → `run_case … 0` (PASS). On pre-fix code this must exit 2 — verify it drives RED before proceeding.
- 1.3 Add the SQL-shape pin: after a run with the fractional fixture, grep the `STUB_CALLS` log for `toDateTime64('2026-10-19 05:12:33.456789'` in the second `INVOCATION` block — pins fraction-preserving parse (a `${var%%.*}` strip-the-fraction equivalent must fail this pin; see decision-challenges.md).
- 1.4 Bump the anti-vacuity floor: `passes -lt 17` → `passes -lt 19` and `expected 17` → `expected 19` (17 existing + 2 new assertions).
- 1.5 Run `bash scripts/followthroughs/web2-plugin-seed-8743.test.sh` — expect the new fractional case to FAIL and all prior cases to still pass.

## Phase 2 — The fix (GREEN)

- 2.1 `scripts/followthroughs/web2-plugin-seed-8743.sh` ABSENCE_SQL: `toDateTime('${first_marker_dt}')` → `toDateTime64('${first_marker_dt}', 6, 'UTC')`.
- 2.2 Update the adjacent comment (probe:221-223) to name the `DateTime64` fractional rendering (e.g. `minIf` over `DateTime64` renders `…SS.ffffff`; `toDateTime64` keeps the sub-second floor).
- 2.3 Re-run `bash scripts/followthroughs/web2-plugin-seed-8743.test.sh` — all 19 assertions pass, exit 0.

## Phase 3 — Verification + sweep re-run

- 3.1 Mutation check: restore `toDateTime('${first_marker_dt}')` transiently, confirm the suite goes RED on the fractional case, revert back (never commit the revert). Record the result in the commit message.
- 3.2 Re-run the sibling census: `grep -rn "toDateTime" scripts/followthroughs/` — confirm matches are only the census-exempt sites in the plan's sweep table (plus the new test-side emulation pattern).
- 3.3 Run `bash scripts/test-all.sh` affected shards (the `scripts/web2-plugin-seed-8743` suite at test-all.sh:5869 runs in CI regardless).
- 3.4 Verify `test -x scripts/followthroughs/web2-plugin-seed-8743.sh` still holds.

## Phase 4 — Commit

- 4.1 Commit the two files: `fix(followthrough): parse DateTime64 marker literal in web2-plugin-seed-8743 absence query` — `Closes #10741` in the PR body (not title), `Refs #8743`.
