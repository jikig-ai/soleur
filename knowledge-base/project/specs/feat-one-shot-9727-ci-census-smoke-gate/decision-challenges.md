# Decision challenges: feat-one-shot-9727-ci-census-smoke-gate

Taste items from plan review, none of which argues the operator's stated scope should change. Each records the default taken.

## Declined: a `--last <N>h` window option on the census (CTO devex lens)

- Finding: typing two ISO timestamps is the most error-prone step; a `--last 6h` option is about five lines of `date -u`.
- Default taken: not built. The script header documents the `date -u` recipe for a closed window. The issue asks for a small script, and the option
  can be added by the first stage that finds the recipe tiresome.

## Accepted risk: no `.head.sha` freshness guard on the PR file list (Kieran)

- Finding: `pulls/N/files` may lag right after a `synchronize` push, and the gate is fail-open on error, not on a stale non-empty list.
- Default taken: no extra API call. A wrong skip costs one PR a non-required self-test while the five required scanners still run, and the next push or
  the merge-queue candidate re-reads the list. Listed under Dependencies & Risks in the plan.

## Declined: a label or `workflow_dispatch` that forces the smoke matrix (CTO devex lens)

- Default taken: not built. Touching a subject file is the documented way to force smoke, and the ADR amendment states the rollback.

## Adopted in part: widen `SUBJECT_RE` and keep a small step-body test (CTO devex lens, DHH)

- Adopted: the test is reduced to a named list, an operand anchor and five fail-open rows. Not adopted: widening `.gitleaks.toml` to a `.gitleaks*`
  prefix, because `.gitleaksignore` is named explicitly and a prefix would also match unrelated future files.
