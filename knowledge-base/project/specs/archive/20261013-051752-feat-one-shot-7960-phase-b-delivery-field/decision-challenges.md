# Decision challenges — feat-one-shot-7960-phase-b-delivery-field

Headless plan-review routing (ADR-084). Taste and user-challenge items from the 2026-09-18 panel,
persisted for `ship` to render into the PR body and file as an `action-required` issue.

## Recorded for visibility (mechanical, applied)

- **`BASELINE_AT_MERGE` deleted rather than re-scoped.** The brief asked to check whether the
  baseline and drift branches become dead code and delete dead code. With proof keyed on
  `err_redact_rev`, drift decides no verdict; the baseline's only residual job was a "not yet"
  heading that would be false on the current (already Phase-B) host and stale across any
  convergence reboot or multi-day P3 refusal. Every unproven reading is now one `exit 3`
  (CANNOT ESTABLISH) whose message names the delivering replace. The brief's required case
  "boot drift WITHOUT field -> CANNOT ESTABLISH" still holds. Revert path: re-scope instead of
  delete (the plan's first draft), at the cost of a pre-merge rebaseline dance.

## Taste (named-panel, CTO devex lens)

- **Applied:** collapse the probe header's prose restatement of branch conditions into a pointer
  at the decision-table comment (CTO #2). Operator may prefer the existing long-form header.
- **Applied:** a resume/idempotency check at the top of the post-merge sequence (CTO #5).
- **Not applied:** declare the 27-case harness + mutation-matrix format a "house pattern" for
  future positive-proof probes in ADR-211 (CTO #3). Kept the ADR amendment short; a pattern
  declaration belongs in a principle register if it recurs a third time (7440, #7960, ADR-218).
