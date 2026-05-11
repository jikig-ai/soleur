# bot-pr-with-synthetic-checks — changelog

Composite-action behavior log. No test runner exists for composites in this
repo, so backward-compat is asserted by reading existing callers and verifying
their input set is unchanged. See `action.yml` for the live contract.

## v2 (2026-05-11)

Issue: #2720. Plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`.

Adds 3 optional inputs needed by the compound-promotion-loop cron (which
opens draft PRs, labels them `self-healing/auto`, and skips auto-merge so a
human operator confirms before merge). All three default to behavior
identical to v1.

- `draft` (default `'false'`): when normalized-true, passes `--draft` to
  `gh pr create`.
- `skip-auto-merge` (default `'false'`): when normalized-true, omits the
  closing `gh pr merge --squash --auto` step.
- `labels` (default `''`): newline-separated label names applied via
  `gh pr edit --add-label` after PR creation. Caller is responsible for
  label existence; the action does not create labels.

**Boundary normalization.** `draft` and `skip-auto-merge` are lowercased and
hard-validated against the literal `true|false` set so callers passing
`'True'`, `'TRUE'`, `'1'`, or any other approximation fail loud, not silent.
GitHub Actions composite-input booleans-as-strings are an evergreen footgun;
the normalization step is the load-bearing defense.

**Shell flags unchanged.** Run block keeps `set -eo pipefail` (NOT `-euo`).
Several existing inputs (`add-paths`, `change-summary` default) rely on
unset-permissive semantics; upgrading to `-u` would break the v1 callers
this changelog promises not to break.

**Backward compatibility.** Existing callers (`scheduled-rule-prune.yml`,
`rule-metrics-aggregate.yml`) omit the new inputs, so defaults
`'false'`/`'false'`/`''` make the action open a non-draft PR, label nothing,
and queue auto-merge — exactly the v1 behavior.

## v1 (pre-2026-05-11)

Original surface. Opens a non-draft bot PR from `${BRANCH_PREFIX}<date>` →
`main`, posts 4 synthetic check-runs (`test`, `dependency-review`, `e2e`,
`skill-security-scan PR gate`) plus `cla-check`, queues `gh pr merge
--squash --auto`. Inputs: `add-paths`, `branch-prefix`, `commit-message`,
`pr-title-prefix`, `pr-body`, `change-summary`, `gh-token`.
