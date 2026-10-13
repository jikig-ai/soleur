# Tasks — feat-one-shot-9066-git-data-lock-no-subject-id

Plan: knowledge-base/project/plans/2026-10-09-fix-git-data-lock-no-subject-id-9066-plan.md
No hash-bound file, no evidence file, no `.github/workflows`, no production write.

## 1. Verify (read-only)
- 1.1 Re-run AC1/AC2 (bound-file intersection empty; evidence hash current).
- 1.2 Collect content-anchored claims for the PR-body "Verified on main" block (wrapper lock names, no other id writer, counter predicates, purge count-only + exclusions).

## 2. Guard (tests only)
- 2.1 Write the failing guard first: `subject_id_leaks` predicate + committed negative control (M1-M3 fixtures, must-PASS root) in both suites.
- 2.2 Remove suite: remove-present and remove-absent arms (rc=0, `.init.lock` exists, predicate empty); provision suite: provision-new and provision-again.
- 2.3 Raise floors (66, 50) to the measured totals.
- 2.4 Wrapper-copy runs M1, M3, M4 (restore `WRAPPER`); paste results for the PR body.
- 2.5 Re-run `fixture-relative-assert.test.sh` and `fixture-dir-operand-assert.test.sh`; regenerate baselines only for the new rows.

## 3. Docs (requirement 3)
- 3.1 ADR-239 dated amendment (via soleur:architecture): retention rule, no wipe implementation on main, three re-ruling states, alternatives rejected.
- 3.2 Runbook: intro retention end, record-template `not covered:` addendum, step (d) one-sentence qualifier. Leave the verdict map untouched.
- 3.3 Art. 30 PA-36 (f): append-only Superseded marker (CLO agent).
- 3.4 Lint: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.

## 4. Ship
- 4.1 CLO attestation file under knowledge-base/legal/audits/.
- 4.2 PR body: Refs only (#9066 #5914 #8211 #9377 #8609), verification block, DC-1, slip rule, drafted #5914 addendum for the owner. Push; CI runs the heavy battery.
