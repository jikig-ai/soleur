# Decision challenges - #8016 plan

## User-Challenge 1 - close at merge versus a 14-day acceptance read

- Operator direction (default): fix the root cause, then close #8016 via `Closes #8016` in the PR
  body once the fix is verified.
- Challenge (CTO plan review): add a roughly 14-day acceptance read after merge (zero `rc=137`
  `DEPLOY_ROLLBACK` rows, steady `SANDBOX_PROBE_OK` rows) because the prod failure rate (11% over the
  last 7 days) is higher than the local reproduction rate (3.0%).
- Why the plan keeps the default: the fix is verified at the mechanism level (A/B on the real argv:
  3.0% versus 0 of 7500, plus a bwrap-free reproduction and a timing-delay control), the failure
  signature matches 19 of 19 production rows, and any recurrence self-reports on the same line and
  emails on release failure.
- Cost of taking the challenge: #8016 stays open under the existing sweeper (arm b needs 20 OK rows
  and zero rollbacks over 7 days) and the PR uses `Ref` instead of `Closes`.

## Taste 2 - ADR-079 addendum (CTO) versus none (DHH, code-simplicity)

- CTO suggested a one-paragraph ADR-079 addendum recording that docker-exec'd bwrap probes must not
  use `--die-with-parent`.
- Plan review cut it: the plan's own Architecture gate concludes no architectural decision is made and
  ADR-079 does not specify the probe argv; the constraint lives in the learning file and the runbook.
- Cost of taking the CTO suggestion: one `soleur:architecture` run and one more prose sink.
