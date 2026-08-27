# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-26-fix-7652-fixture-dir-assert-and-boundary-scope-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
Two non-blocking findings, handled in-plan rather than fixed during planning:
- `gdpr-gate.sh` refuses before scanning (`rules 108 days stale`, `POSTURE_FAIL`) — a pre-existing
  repo condition with no open tracker. Recorded in the plan's Compliance Gate section; Phase 3
  files the issue.
- `lint-guard-contract.py` initially failed the rewrite (0 matrix rows across all three guards)
  because the tables lacked the literal `**Mutation matrix**` field label the lint scopes on.
  Fixed during planning; lint now green.

### Decisions
- The primary mechanism changed from v1. Rather than asserting the operand at every call site, the
  class dies at one chokepoint: running each suite with its working directory outside any git
  repository, so `git -C ""` fails outright (`fatal: not in a git directory`) instead of silently
  targeting CWD. This also kills the 2026-08-20 lost-`cd` class. 358 of 373 suites already resolve
  their root from `BASH_SOURCE`; only 29 are CWD-dependent. The assertion sweep is now the
  residual, not the plan.
- The property was split by measurement: only `git -C` widens on an empty operand (`rm -rf ""` is a
  silent no-op, `mv a ""` errors). P1a (empty operand) is swept now; P1b (relative operand) is a
  named deferral with a tracking issue rather than a silent exemption.
- Instance 2 is ADR-166 compliance, not a new architectural decision — a message naming a cause the
  job did not measure. The proposed ADR-197, the `${CI:-}` severity tier, the `.git/hooks/`
  dimension and an ADR-177 cross-reference were all cut.
- A composition hole that no single-dimension review saw was closed: a blanket `branch.*` config cut
  combined with a refs REPORT class made `git -C "" checkout -b probe origin/main` invisible in both
  dimensions at once. The carve-out is narrowed to `vscode-merge-base` and a permanent composition
  row was added to the mutation matrix.
- Five factual claims in v1 were falsified by measurement and corrected in Research Reconciliation —
  most consequentially that `exit 2` is NOT subshell-safe (it behaves identically to `${1:?}`, which
  also turned out to have ~10 repo precedents, contrary to v1).

### Decision Challenges
- UC-1 (split #7652 into two PRs) — resolved by the pipeline runner as **one PR, boundary-first**.
  Technical fork under `hr-technical-fork-is-not-an-operator-question`; rationale recorded in
  `decision-challenges.md` §UC-1. Not escalated to the operator.

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `functional-discovery`, `cto` (fork
  ruling), `cto` (devex lens), `cpo`, `dhh-rails-reviewer`, `kieran-rails-reviewer`,
  `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, scoped strong-model
  advisor (`fable`)
- Scripts: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `gdpr-gate.sh`,
  `lint-diagnosis-claims.sh` (identified as a required Phase 4 gate)

## Work Phase
- Status: starting
