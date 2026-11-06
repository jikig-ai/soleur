# Tasks — feat-one-shot-11771-ratchet-baseline

Plan: `knowledge-base/project/plans/2026-11-01-ci-affected-index-ratchet-baseline-repair-plan.md`
Issue: #11771

- [x] Step 1 — Correct stale accept row `25a129edb2d6 → 538ede2b0768` (`:518 → :599`)
       in `scripts/ci-pr-affected-audit.accept.tsv`
- [ ] Step 2 — Declare `AFFECTED_APPS_WEB_PLATFORM_SCRIPTS_HOME_CENSUS_TRIGGER_TEST_SH_PATHS`
       in `scripts/lib/test-affected-paths.sh` (pending CTO ruling R1)
- [ ] Step 3 — `ratchet` exit=0; `--print-baseline` diff == baseline.tsv (prune only if it differs)
- [ ] `Closes #11771` on PR body; review/qa/compound/ship per one-shot
