# Tasks - create-arm live-fire reading rule (Ref #10550)

Plan: `knowledge-base/project/plans/2026-10-29-feat-create-arm-verdict-telemetry-plan.md`
Docs only. Touch nothing outside `knowledge-base/`. Do not fire the cron or run `soleur:trigger-cron`.

## Phase 1 - Runbook

- 1.1 Re-read `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` around "Create-arm marker fields" and `### Review checklist for a create draft`.
- 1.2 Insert `### Reading a live-fire row (model decline or gate refusal)` between them: the precise invariant (`no-pattern-qualifies` is always the model's; the ledger backstop alone ends `no_action`/`other`; one call, one verdict), the reading table (single home is the runbook subsection; includes the `all-owned` and `other` rows with offered>0, the `transport` row and a catch-all row), the "what the marker cannot show" note (instant versus deliberated needs `output_tokens`, blocked by the claude-cost-capture-dark incident). The brief's claim is not cited in the runbook (an operator document).
- 1.3 Do not add or alter rows of the "`create_detail` values by class" table.
- 1.4 Add one pointer sentence in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` after the create-arm field paragraph; add no jq column.

## Phase 2 - Verify

- 2.1 `git diff --name-only origin/main...HEAD | grep -v '^knowledge-base/'` prints nothing.
- 2.2 Every backticked token in the new subsection is a `create_*` field, a `CREATE_NO_ACTION_REASONS` / `CREATE_REFUSAL_CLASSES` member, a `create_outcome` value or an emitted `create_detail` token (command in plan AC2).
- 2.3 `cd apps/web-platform && npx vitest run test/server/compound-promote-runbook-parity.test.ts` passes.
- 2.4 `markdownlint` on the two runbooks (repo config) is clean.

## Phase 3 - Ship

- 3.1 PR body: "Ref #10550" (never "Closes"), documentation only, no behaviour change, effect unmeasured until an operator-authorised live-fire clears; render `decision-challenges.md` into the body.
- 3.2 Leave #8443, #11183, #10676, #11228, #10552, #10551, #8293 alone. Do not post to or close #10550.
