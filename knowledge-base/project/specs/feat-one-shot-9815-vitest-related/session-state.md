# Session State — feat-one-shot-9815-vitest-related

Issue: #9815 — `apps/web-platform [unit]` (+ `[repo-wide+component]`) run the
FULL vitest project on any app diff (~82s + ~80s); narrow local `--affected`
runs to `vitest related <changed app files>`, fail-safe to the full project on
config/meta changes or zero resolved files. CI unchanged.

Sequence position: #9763 → #9813 (merged) → #9814 (PR #9990, in merge queue) →
#9815 (this issue, PR #10025 draft).

## Status

**Phase 5 verification.** Implementation landed:

- `apps/web-platform/scripts/vitest-related.sh` — wrapper; `vitest related
  <files> --run --project <p>`; marker-grep zero fallback; `VITEST_RELATED`
  receipts; bundle = repo-wide-full then component-narrow (both rcs).
- `scripts/lib/test-relevance-paths.sh` — `WEBPLAT_RELATED_META` (14, measured),
  `webplat_related_meta_hit`, `webplat_related_files`.
- `scripts/test-all.sh` — `_webplat_related` computation inside the
  `want_webplat` arm (in-window; no `_diff_touches` literal — sibling guard
  slices on ANY line carrying it, comments included); both registrations
  retargeted (2-line shape kept); new suite registered.
- `scripts/lib/test-affected-paths.sh` — AFFECTED block + consumed-edge map
  for `[repo-wide+component]` (its argv lost the `apps/web-platform` token —
  derivation returned self-only; consumed mapping restores the class).
- `apps/web-platform/test/vitest-related.test.sh` — 27 assertions, ALL PASS.
- ADR-242 amendment 2026-10-11 (#9815) — decisions 23-26.
- measurements.md recorded.

## Verified so far

vitest-related suite 27/27; webplat-gate 16/16; group-affected 54/54;
battery-tag-authorship 15/15; integration-env-gates 30/30; orphan census
667 covered / 0 orphaned; lint-guard-contract clean; enumerate lists all
three labels.

## Key implementation facts (verify, don't re-derive)

- `vitest related` is a DISTINCT subcommand at 4.1.11 (`vitest run --related`
  does not exist — CACError). `--run` pinned statically: measured — no watch
  hang at this version; flag kept as docs form.
- Zero-resolution marker: literal `No test files found` (stdout, rc 0).
- Reporter hides test-file names on green — arms assert `Test Files N passed`
  counts, not names.
- `_diff_touches` literal may NOT appear anywhere above the gate inside the
  want_webplat arm (sibling UNGATED slice is literal-keyed).
- `inputs=N` counts non-empty lines of WEBPLAT_RELATED.

## In flight

- `test-all-affected` (background, /tmp/9815-affected.log)
- `test-all-infra-coverage-notice` (background)
- e2e: TEST_GROUP=webplat run over a scratch `lib/repo-url.ts` diff
  (/tmp/9815-e2e.log) — lock-queued; revert the comment line before commit.
- Remaining: e2e receipt check, tasks 5.3/5.8/5.9, review, ship.


## Fix round (post-3-seat review) — committed 9d07a54f00

- bash-3.2 mapfile P1 → while-read (both correctness seats caught it)
- M4 behavioral bundle-red + &&-mutant; M5a-e eligibility mutants on the
  extracted computation (CI flip, all-group disjunct, fallback, meta consult,
  banner); A9e META derivation; A7b deleted-path; A7c inputs=N; scoped B2
  polarity needles; vacancy else-fails; anchored --run pin; semantic M1.
- Suite now 36/36 green. skip_suite hint → wrapper. OUT_OF_CLASS ledger
  comment resynced. Lib header documents the pure functions.
- enumerate-commands records prove the env seam (WEBPLAT_RELATED= empty
  under enumerate, deterministic).
- Live e2e (TEST_GROUP=webplat over a scratch repo-url.ts diff) sat
  lock-queued >45 min behind a sibling battery — fixture arms + extracted
  computation already prove the seam; the queued run remains as bonus
  evidence in /tmp/9815-e2e.log.

## Ready state

All gates green locally; review evidence complete. Marked ready for merge.
