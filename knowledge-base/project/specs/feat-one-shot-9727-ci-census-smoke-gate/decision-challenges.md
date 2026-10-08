# Decision challenges: feat-one-shot-9727-ci-census-smoke-gate

Taste items from plan review, none of which argues the operator's stated scope should change. Each records the default taken.

## Declined: a `--last <N>h` window option on the census (CTO devex lens)

- Finding: typing two ISO timestamps is the most error-prone step; a `--last 6h` option is about five lines of `date -u`.
- Default taken: not built. The script header documents the `date -u` recipe for a closed window. The issue asks for a small script, and the option
  can be added by the first stage that finds the recipe tiresome.

## Adopted in a different form: list freshness (Kieran, security-sentinel, architecture-strategist, spec-flow-analyzer)

- Finding: `pulls/N/files` may lag a `synchronize` push, and a re-run reads the current PR rather than the run's SHA.
- First default (plan review): accept the risk. Reversed at deepen-plan because three reviewers independently rated it and `smoke-tests` never runs on `merge_group`, so nothing
  re-reads the list later. Adopted: compare the listed entry count with the event's own `changed_files` (no extra API call) and emit `true` on any mismatch. A `.head.sha`
  comparison was not adopted; a stale list with an equal count remains an accepted residual.

## Declined: a label or `workflow_dispatch` that forces the smoke matrix (CTO devex lens)

- Default taken: not built. Touching a subject file is the documented way to force smoke, and the ADR amendment states the rollback.

## Adopted in part: widen `SUBJECT_RE` and keep a small step-body test (CTO devex lens, DHH)

- Adopted: the test is reduced to a named list, an operand anchor and five fail-open rows. Not adopted: widening `.gitleaks.toml` to a `.gitleaks*`
  prefix, because `.gitleaksignore` is named explicitly and a prefix would also match unrelated future files.
