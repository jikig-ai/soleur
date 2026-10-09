# Decision challenges: feat-one-shot-9512-skip-duplicate-push-ci

## 2026-10-09 plan phase (headless)

### User-Challenge 1: ADR-276 Status forbids merging S2 while the file reads `proposed`

- Operator direction (default, kept): "Append a dated ADR-276 S2 amendment BEFORE the stage takes effect (ADR stays "proposed")."
- Conflict: ADR-276 Status says no stage PR that changes CI behaviour (S2, S3, S4) may merge while `status:` reads `proposed`; the flip to `adopting` needs the CTO's approval comment on a PR that edits the line.
- Reading taken in the plan: the PR merges dark under `proposed` because, with `CI_PUSH_DEDUPE` unset, no verdict moves (one extra non-verdict job on push runs); the behaviour change is the activation, which is gated on the file reading `adopting` and on an explicit operator go. The amendment states this reading so it can be challenged.
- Decision needed from the operator/CTO: accept that reading, or approve ADR-276 (`adopting`) before this PR merges.

### Taste 1: accept losing the push run's second sample

- Measured 2026-10-09: 8 of 94 completed push runs were red on SHAs that had a green `merge_group` run (e2e 3, test-scripts (5/8) 2, test 2, one unattributed). Each blocked that SHA's deploy. After activation those SHAs deploy instead.
- Plan default: accept, record as a named residual after classifying the 8 as flake or escape in Phase 1, and leave "a scheduled full run on main" to S5 (#9730).
- Alternative: keep one scheduled or dispatch full battery run per day on `main` as a detective control, at roughly the cost of one push run per day.

### Mechanical notes (applied in the plan)

- The S1 `S1 live` line is appended by a docs-only follow-up after the post-merge census (the brief makes the census a post-merge task), not inside the S2 amendment.
- Activation (`gh variable set CI_PUSH_DEDUPE --body on`) is an agent action taken only on the operator's explicit go; plan approval is not authorization.

## 2026-10-09 plan review (headless)

### Taste 2: keep the soak probe and the PM-2 operator go (DHH and simplicity argued to cut)

- Plan default: keep. A soak-gated close needs an enrolled probe, and the PM-2 go is the only explicit authorization before the deploy trigger changes. The probe is shrunk, not removed.

### Taste 3: classify the 8 push-only reds (DHH and simplicity argued to skip; the CTO and Kieran asked for a gate)

- Plan default: classify with one read each, use the result in the ADR residual and at the PM-2 go; a reproducible push-only red blocks activation until Taste 1 is answered.

### Mechanical applied (not challenged)

- Gate the `test` aggregator instead of adding a tolerance arm; prove coverage from the `merge_group` run's `test` job; release-workflow CI budget and B9 added to the work; probe elision observed from job conclusions; `run_attempt == 1`.
