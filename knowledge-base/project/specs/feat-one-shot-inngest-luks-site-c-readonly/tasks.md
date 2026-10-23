# Tasks — fix: Inngest generation anchor reads the read-only Hetzner token only (Site C)

Plan: `knowledge-base/project/plans/2026-10-23-fix-inngest-luks-site-c-readonly-only-anchor-plan.md`.
Branch `feat-one-shot-inngest-luks-site-c-readonly`, draft PR #10891, `Ref #10664` (never `Closes`).
Stage by explicit path; never `git add -A`. No infra, workflow, `.tf` or flip-guard file is touched.

## Phase 0 — RED first

- 0.1 Write `tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh` per the plan's Guard 1
  (live rows L1/L2, table-driven matrix M1-M10, controls C1-C3, seams `HCLOUD_SCAN_ROOT` and
  `HCLOUD_SCAN_TODAY`, floors: 20 reads inspected and the allowlisted line found once).
  - 0.1.1 Run it on the unmodified tree: RED with exactly one F-literal finding (~l.568). Save the output.
  - 0.1.2 Re-run the two non-literal arms against `git ls-files`; if either hits an unrelated site, fall
    back to the same-line arm only and record the blind spot in the suite header.
- 0.2 Rewrite the assertions in `apps/web-platform/infra/cutover-inngest-workflow.test.sh` (stub bait,
  l.1437-1439, l.1448-1456, l.1499-1513, `http401 both`); run: RED.
- 0.3 Update `tests/scripts/test-argv-bearer-sweep.sh` l.2525 and the l.2554 `warning-dropped` mutant
  (from-text and to-text); run the `lead (a1)` rows: RED.

## Phase 1 — GREEN: the script

- 1.1 Rewrite the comment block l.547-561 (facts as of 2026-10-23; leave l.477 and l.562 alone).
- 1.2 Remove `tokvar`, the fallback read and both notices; literal variable name in the shape and
  401/403 warnings; the empty-token warning names `HCLOUD_TOKEN_READONLY` and step O5.
- 1.3 `bash -n` and the shell lint for `scripts/cutover-inngest.sh`.

## Phase 2 — tests green

- 2.1 `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` green.
- 2.2 `lead (a1)` and `bk` rows of `tests/scripts/test-argv-bearer-sweep.sh` green.
- 2.3 The new scan suite green on the live tree (L1) and RED on the pre-change shape (L2).

## Phase 3 — documentation

- 3.1 `runbooks/inngest-server.md` l.133 and l.139-146.
- 3.2 ADR-225 item 4 in place with the dated "Amended" sentence.
- 3.3 ADR-241: bracketed pointer on the "Left open" bullet and a new dated 2026-10-23 entry.
- 3.4 `runbooks/infra-credential-tiers-8209.md`: generation-anchor row, step 4, one pointer sentence.
- 3.5 `model.c4` l.739 clause; commit through the hook so `model.likec4.json` regenerates (never
  hand-edit; if the hook cannot run, stop and report); run the two C4 tests.
- 3.6 Run the plan's sweep command; classify every hit; record the fixed ones for the PR body.

## Phase 4 — register and verify

- 4.1 `run_suite` line in `scripts/test-all.sh`.
- 4.2 `ALWAYS_ON_SUITES` entry in `scripts/lib/test-affected-paths.sh`; run
  `scripts/lint-orphan-test-suites.sh` and `scripts/test-all-affected.test.sh`.
- 4.3 Shard-manifest verdict (`regenerate-shard-manifest.py --incremental`, then `--write` only if
  required); record which applied.
- 4.4 Time the suite; keep it under 10 s or move the fixture battery behind a flag.
- 4.5 Markdownlint on the touched docs; confirm the diff-scope AC (no `.tf`, workflow, action, flip-guard
  or migration path).

## Ship hand-off

- 5.1 PR body: `Ref #10664`, RED output of 0.1.1, fixed sweep hits, open items (flip-guard retention
  comment, `op=backup`), ends with the `Generated with Claude Code` line; commits carry the
  `Co-Authored-By: Claude Sonnet 5.5` trailer.
- 5.2 After merge: split the Site C checkbox on #10664 with `gh issue edit` so the flip-guard
  retention-comment sub-item stays open.
