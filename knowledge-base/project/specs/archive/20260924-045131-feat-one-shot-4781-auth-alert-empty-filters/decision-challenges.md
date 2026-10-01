# Decision challenges — feat-one-shot-4781-auth-alert-empty-filters

Recorded by plan-review in headless mode. `ship` renders these into the PR body.

## Taste (named panel, CTO): scope additions applied to the plan

- **Add `FROZEN RULE LEFT SCOPE` to the drift-issue guide's FROZEN bullet**
  (`.github/workflows/scheduled-sentry-alert-drift.yml` L200). Applied. Without it, a reader
  who matches findings to bullets by exact class name falls through to the UNMANAGED
  bullet ("delete it") or the GAINED bullet. The cost is one printf line.
- **Rewrite the stale sentence in `apply-sentry-infra.yml` L38-41** ("the 4 AUTH
  issue-alert resources … are import-only"). Applied, comment-only. This is the same
  #4781-era lore, in a file operators read.
- **Post-merge #4781 comment citing the green push-to-main apply run and the limits**
  (detection only for `auth-per-user-loop`; native restore waits on #7985). Applied. The
  code-simplicity review preferred relying on the PR body alone. The CTO's version was kept
  because the lead asked to "close #4781 with evidence".
- **Deferred: a parity check between the probe's finding classes and the drift guide's
  bullets.** This needs a tracking issue, filed during /work.

## Taste (simplification): scope trimmed from the first draft

- Two learnings dropped from the correction list, because neither frames the email as a
  red herring: `2026-05-17-sentry-issue-alert-create-dedup-…` and
  `2026-08-19-i-proposed-deleting-a-control-…`. The operator asked for the
  "red herring / coincidental" framing to be corrected, so this is inside the stated scope.
