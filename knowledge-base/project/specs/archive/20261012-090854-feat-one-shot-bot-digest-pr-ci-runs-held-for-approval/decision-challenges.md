# Decision challenges (plan-review, headless)

Both are Taste calls surfaced for the PR body; neither contradicts an operator-stated direction.

1. ADR placement. Resolved at deepen-plan: a new ADR (two reviewers asked for it) plus an ADR-241 log line and a one-line ADR-232 pointer. Recorded here because the first draft chose an ADR-232 amendment.
2. Input shape. The plan adds a `pr-token` input to the composite (explicit, guard-able, with an empty/equality refusal). One reviewer would instead pass the App token as the existing `gh-token` and have the check-run step read `github.token` itself, which avoids a breaking input. Default taken: `pr-token`, because it keeps the synthetic-check identity visible at the call site.
3. Guard size. Four reviewers called a new standalone suite oversized for one caller; the plan folded the guard into `tests/scripts/test-weakness-miner.sh` with a short mutation battery (operator asked for a guard "where feasible").
4. Job split. Deepen-plan (security review) added a three-job split of weakness-miner.yml so the miner never shares a job with the credential; a simplicity-minded reviewer may call that heavier than the pin-bump precedent, which has no content-producing step before its mint. Default taken: split, because the ordering claim is otherwise not true.
