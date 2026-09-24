# Decision challenges: feat-one-shot-release-false-deploy-skip

Decisions from plan review that go against a reviewer's recommendation, or that the operator's
brief did not settle. They are recorded here under ADR-084 so they can be audited outside this
session. `ship` renders this file into the PR body and files the `action-required` issue.
Source plan: `knowledge-base/project/plans/2026-09-24-fix-release-resolve-target-false-deploy-skip-plan.md`
§Plan Review Revisions.

---

## DC-1: keep the 4×20 s retry that two reviewers recommended cutting

**Date:** 2026-09-24
**Classification:** User-Challenge (a reviewer argued for dropping operator-specified scope)
**Status:** open. The operator's direction stands by default, so the retry ships.

- **Operator direction:** "retry the lookup with backoff (e.g. 3 x 20 s)".
- **Challenge (DHH, code-simplicity):** the unfiltered-list fallback is what would have deployed
  the incident SHA. The measured filtered-search lag was at least 13 minutes, so a 60 s retry
  alone could not have recovered it. Cutting the retry removes up to 60 s from every docs-only
  deploy-arm run, the `sleep` stub, one test row and one mutation.
- **Why it stays:** the operator specified it. It still covers a short lag on *both* reads, a
  case nobody has observed but that is plausible, and it costs only runner seconds on runs that
  deploy nothing.
- **What would change it:** the operator saying so. If it is cut later, remove row L2, S1's
  sleep-count assertion, the `sleep` stub and Guard 2 mutation 1 together.

## DC-2: read order, filtered search first versus the unfiltered list first

**Date:** 2026-09-24
**Classification:** Taste
**Status:** open. The plan keeps the filtered search first.

- **DHH P2:** read the reliable unfiltered list first, and fall back to the filtered search only
  for months-old re-runs.
- **Kept as planned:** the order makes no difference to correctness. Keeping the primary read
  byte-identical keeps X1 and G7 pinned without edits.

## DC-3: YAML anchor instead of a copied pathspec

**Date:** 2026-09-24
**Classification:** Taste
**Status:** open.

- **CTO P2:** `path_filter: &release_paths "…"` with `RELEASE_PATH_FILTER: *release_paths`
  would make the pathspec a single source within the file.
- **Not adopted yet:** it was not verified at plan time that actionlint and every PyYAML
  extractor in the repo accept anchors. The copy plus the P1 parity row is the verified path.

## DC-4: a dedicated release-outcome email arm for `release_run_missing`

**Date:** 2026-09-24
**Classification:** Taste (operator-facing copy), deferred
**Status:** open.

- **CTO P1:** the email names only the generic "Working out which build should go to production —
  failure". The non-technical reader would benefit from a plain-language cause, as
  `ci_not_green` already gets.
- **Blocked:** G9's extractor
  (`plugins/soleur/test/workflow-run-deploy-invariants.test.sh`, the skipset.py `clean` set)
  counts any `release-outcome` case arm that names a produced reason as a clean skip. A dedicated
  arm would therefore red the disjointness check until the extractor learns to tell a paging arm
  from a clean one.
- **Candidate for PRs 2–4 of this sequence**, together with the CTO's two deferrals: an
  automatic delayed re-run on `release_run_missing`, and de-duplicating the drift alerter's page
  against this alert for the same SHA.
