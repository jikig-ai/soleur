# Decision challenges: web-host-reboot workflow (#9372, Ref only)

Headless plan run, 2026-10-07. Each item is a Taste or User-Challenge finding from the six-reviewer plan review. The plan keeps the direction the brief stated; the owner may reverse any item. Nothing here was applied silently.

## 1. Keep the `observe` job (User-Challenge)

- Reviewers (DHH, code-simplicity, CTO devex lens) proposed one job: reboot, one single-read grade, a summary, and local re-grading afterwards.
- The brief says the workflow itself polls Better Stack and reports PASS/FAIL/NOT YET. The plan keeps two jobs so the poll holds no Tier-B credential and does not hold the `web-1-swap` mutex for about 45 minutes.
- Default: keep (the stated direction). Reversal cost: delete one job, two cross-job outputs, the `observe` structural rows (about 70 test lines) and Guard 4 row 4.

## 2. Keep the `host` input and the explicit allow-list (User-Challenge)

- DHH proposed dropping the `host` input and the allow-list refusal because the script already pins `soleur-web-2` by constant.
- The brief says "allow only web-2 initially via an explicit allowlist", so the plan keeps it, with a test row that the script, the workflow options and the suite agree.
- Default: keep.

## 3. Keep input validation inside the gated job (Taste)

- Validation runs after the reviewer approval, so a typo in `confirm` spends one approval (spec-flow and Kieran noted the earlier sibling learning about approvals spent on a run that could not work).
- Option: add a credential-free `validate` job ahead of the gate (format checks only). It would make the job list three and Guard 4's "exactly two jobs" row three.
- Default: keep in-job. The refusals that need live state print the live id and the corrected `confirm`, and the runbook takes the id from a read-only Hetzner GET.

## 4. Keep the C4 and ADR records (Taste)

- The CTO devex lens suggested skipping the C4 edge-prose edits and the regeneration, and keeping only a two-line ADR addendum, because the capability retires within weeks.
- The plan keeps two half-sentence edge edits and a short ADR-263 addendum (plus a one-line ADR-241 entry), because `wg-architecture-decision-is-a-plan-deliverable` and the C4 completeness mandate treat a new Tier-B consumer as a recorded change, and the retirement row removes them.
- Default: keep, minimal.

## 5. Keep `credentials_required` in the discoverability test (Taste)

- The CTO devex lens suggested omitting `credentials_required` to avoid the `BASELINE_DECLARED_PROBES` collision with sibling PRs.
- Omitting it would make preflight Check 10 execute a probe that cannot read Better Stack without credentials, verifying nothing about the property. Siblings (#9372's own plans) declared it.
- Default: declare it and bump the baseline in the same PR.

## 6. Mutation-battery volume (Taste)

- DHH asked for about 8 to 10 mutation rows in total; the plan keeps 24 across four guards (Guard 1: 9, Guard 2: 6, Guard 3: 3, Guard 4: 6), down from 29.
- Every row corresponds to a property in the Property List; the REORDER and second-write-site rows are the ones DHH also kept.
- Default: keep at 24; the owner may cut Guard 2 rows 3 and 6 and Guard 4 rows 3 and 6 first.

## 7. A `PASS (row presence only)` label (Taste, applied)

- CLO suggested not using the word PASS at all; the brief asks for PASS/FAIL/NOT YET. Applied as `PASS (row presence only)` with the fixed footer. Recorded here because it softens a requested word.
