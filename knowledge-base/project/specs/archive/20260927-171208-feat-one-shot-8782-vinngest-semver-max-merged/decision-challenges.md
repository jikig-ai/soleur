# Decision challenges — feat-one-shot-8782-vinngest-semver-max-merged

Recorded in headless mode by plan / plan-review (ADR-084). These are taste and devex calls the pipeline resolved without an operator. `ship` renders this file.

## Taste — anchor ref for the AC6 checker (`HEAD` vs `origin/main`)

- **Raised by:** the scoped advisor consult at plan Step 4.5.
- **Challenge:** on a `pull_request` run, `HEAD` is the synthetic merge of main and the PR branch. A tag cut on the PR's own commit therefore stays a candidate on that PR's AC6 run.
- **Decision:** keep `HEAD`. This keeps one pipeline, byte-identical between writer and checker. The PR-own-tag case is the #8747 incident shape. AC6 already prints the delete-the-tag diagnostic for it, and `deploy-script-tests` is advisory, not a required check.
- **Reversal cost:** low. Switch the checker to `origin/${GITHUB_BASE_REF:-main}`, and drop byte-equality in favour of a behavioural parity harness.

## Taste — a shared sourced selector helper instead of two copies

- **Raised by:** the advisor consult.
- **Decision:** declined. A helper adds a cross-tree `source` edge. It also needs a new `infra-validation.yml` `paths:` entry (a workflow edit) and a new test-affected mapping. Byte-equality of the two shipped blocks gives the same parity property.

## Taste — sub-cause tokens on `ancestry` refusals (CTO devex lens)

- **Suggestion:** prefix each `::error::ancestry:` message with `(shallow)`, `(moved)`, `(label)` and so on, so a Slack skim can tell the causes apart.
- **Decision:** deferred and listed in the plan's Non-Goals. After this change, the runbook's step 2 lists every stage's meaning. Revisit if operators misroute an `ancestry` failure.

## Taste — keep a notice (plus step-summary line) when the signed tag is not merged (CTO devex lens)

- **Decision:** cut at plan-review by the simplicity panel (DHH and code-simplicity) and by Kieran. `target=<tag>` plus `result=noop` and the existing noop summary already explain the outcome.

## Taste — keep the old-literal-absent parity row (CTO devex lens)

- **Decision:** cut. It is superseded by the byte-equality row, which catches a one-sided revert. A revert on both sides reds B1, B2, B3 and B8.
