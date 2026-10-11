# Decision challenges (plan-review, headless)

Both are Taste calls surfaced for the PR body; neither contradicts an operator-stated direction.

1. ADR placement. The plan amends ADR-232 (same decision extended to a second workflow). One reviewer would write a short new ADR or an ADR-241 decision entry instead, because ADR-232 is titled for the inngest pin bumps. Default taken: amendment plus a one-line ADR-241 log entry.
2. Input shape. The plan adds a `pr-token` input to the composite (explicit, guard-able, with an empty/equality refusal). One reviewer would instead pass the App token as the existing `gh-token` and have the check-run step read `github.token` itself, which avoids a breaking input. Default taken: `pr-token`, because it keeps the synthetic-check identity visible at the call site.
3. Guard size. Four reviewers called a new standalone suite oversized for one caller; the plan folded the guard into `tests/scripts/test-weakness-miner.sh` with a short mutation battery (operator asked for a guard "where feasible").
