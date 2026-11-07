# Tasks — feat-one-shot-retire-10865-window-probe

Plan: `knowledge-base/project/plans/2026-11-07-chore-retire-ratchet-observation-window-probe-plan.md`
Ref: #10865 (CLOSED tracker — retirement of its probe; no `Closes` in the PR body, it is already closed).

## 1. Deletion + census re-pins (one commit)

- [x] 1.1 `git rm scripts/followthroughs/ratchet-observation-window-10865.sh`.
- [x] 1.2 In `plugins/soleur/test/ci-pr-affected-replay.test.sh`: delete the contiguous
      "ratchet observation window" block (~lines 3020–3947 — the `# ---- the
      observation-window probe` header through the last `chk … row_ow_parity` line,
      stopping before the `# == glob-rate` banner), which covers the E2BIG (3297)
      and merged-PR-resolution (3536) sub-sections, every `ow_*`/`OW_*` helper and
      all 129 `ow_mutate` call sites.
- [x] 1.3 Same file: delete `row_ow_parity()` (~line 2810 — orphaned by 1.2) and the
      `$BIN/nosleep` stub creation + comment (~lines 202–204). Keep the shared
      stub-`gh` scaffolding (`fx`, `GH_FIX`, `GH_LOG`, SLOW_/HANG_ handlers).
- [x] 1.4 Same file: set `DECLARED_TOTAL` to the post-deletion `grep -c '^mutate '`
      count (expected 473) and update its comment; remove `OW_SITES` and the OW
      terms in the epilogue reconciliation (`MUT_RUN != EXECUTED`,
      `SITES_MUTATE != DECLARED_TOTAL`, delete the `OW_SITES < 126` floor block).
- [x] 1.5 Same file: run the full suite once, set `FLOOR_ASSERTIONS` to the measured
      pass count, and rewrite its arithmetic comment dropping the OW terms.
- [x] 1.6 Re-split the three `--rows` arm ranges to tile `1..DECLARED_TOTAL`
      contiguously, identical values in `scripts/test-all.sh` (run_suite arms) and
      `scripts/ci-oracle-lane-suites.txt` — same commit as the DECLARED_TOTAL bump.
- [x] 1.7 Remove `"scripts/followthroughs/ratchet-observation-window-10865.sh"` from
      `AFFECTED_PLUGINS_SOLEUR_TEST_CI_PR_AFFECTED_REPLAY_{A,B,C}_PATHS` in
      `scripts/lib/test-affected-paths.sh` and rewrite the "EXECUTE the
      observation-window probe" comment above them.
- [x] 1.8 Enumerate stale accept rows via `python3 -I scripts/ci-pr-affected-replay.py audit`
      `stale` lines (or `ratchet --report` `stale-accept` rows); delete exactly those in
      `scripts/ci-pr-affected-audit.accept.tsv` (the 12 name-citing rows are a floor, not
      the set); re-run to clean, `--print-baseline` exit 0 as the end-state check.
      Iterate until exit 0.
- [x] 1.9 In `.github/workflows/scheduled-followthrough-sweeper.yml`: keep
      `pull-requests: read` (surviving probes need it — see decision-challenges
      row 1); rewrite the `(#10865)` comment to attribute the surviving consumers
      (e.g. `ci-push-dedupe-soak-9512.sh`'s mixed `issues?labels=follow-through`
      read and the `/pulls` readers) and drop "Retire this line with the probe".
- [x] 1.10 In `scripts/sweep-followthroughs.test.sh`: keep the PERM-1 pin; update the
      `#10865` comment on `wf_pr_read` to name a surviving consumer.

## 2. Doc reconciliation (same PR)

- [x] 2.1 `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
      ~line 253: convert "is enforced by the follow-through probe" to past tense
      and add a dated retirement note naming this PR; keep the rules text as the
      window's record.
- [x] 2.2 Confirm ADR-276 needs no edit (no literal script path; append-only
      historical narrative — decision row 2).

## 3. Verification

- [x] 3.1 `grep -c '^ow_mutate ' plugins/soleur/test/ci-pr-affected-replay.test.sh`
      → 0; `grep -c '^mutate '` equals `DECLARED_TOTAL`.
- [x] 3.2 `rg -n 'ratchet-observation-window-10865' scripts/ plugins/soleur/test/
      .claude/hooks/ .github/workflows/` → zero hits.
- [x] 3.3 `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` full run passes
      (not a `--rows` slice — see the section-runner learning).
- [x] 3.4 `bash plugins/soleur/test/scripts-shard-totality.test.sh`,
      `bash scripts/sweep-followthroughs.test.sh`,
      `bash scripts/lint-followthrough-varq-ban.sh`,
      `bash scripts/lint-orphan-test-suites.sh` — all pass.
- [x] 3.5 `python3 -I scripts/ci-pr-affected-replay.py audit` reports no `stale` rows and
      `--print-baseline` exits 0.
- [x] 3.6 PR body: `## Changelog` section (chore/test-deletion → `semver:patch`);
      reference #10865 without `Closes`.
