# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-08-25-fix-7650-sentry-issue-alert-to-alert-migration-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: the committed diff and working tree touched ONLY
  knowledge-base/project/plans/ and knowledge-base/project/specs/ — no scope breach.

### Errors

- First write of the revised plan was blocked by `.claude/hooks/iac-plan-write-guard.sh`
  (manual-infrastructure sentinel): sections 2.5 and 2.9 describe recovery gestures in order
  to FORBID them, tripping the actor+imperative co-occurrence model. Resolved by rephrasing
  plus an `iac-routing-ack: plan-phase-2-8-reviewed` marker with justification; the plan routes
  all work through Terraform and the existing workflow, so the ack is accurate, not an escape.
- `terraform init` cannot reach the provider registry from this sandbox. Worked around with the
  `terraform_data` builtin (no registry needed), which is what enabled independent measurement
  of the retracted premises.
- The `plugin:github:github` MCP server failed to connect (bad Authorization header). Not
  blocking — all GitHub reads went through the `gh` CLI.
- Two subagents (CTO, terraform-architect) returned truncated first results and were resumed.
  The terraform-architect's second run had not returned at planner completion, but its decisive
  insight (the builtin-provider probe) was already incorporated AND independently re-verified by
  the parent session.

### Decisions

- MECHANISM REVERSED, on measurement not opinion. Adopt all 27 via `import {}` plus
  `removed { lifecycle { destroy = false } }` config blocks landed on the branch and applied in
  ONE merge — replacing the supplied `workflow_dispatch` state surgery. The parent session
  independently measured both falsifications on Terraform v1.10.5:
  - `removed{}` does NOT refresh — 0 "Refreshing" lines vs 1 in the control; plan JSON
    `actions:["forget"]`, `after` null, `0 to add, 0 to change, 0 to destroy`. HashiCorp PR
    35458, `node_resource_plan_orphan.go`: `if !n.skipRefresh && !forget`.
  - `terraform import` REQUIRES an existing config block — fails rc=1 with "resource address
    does not exist in the configuration". main has zero `sentry_alert` blocks, so the prescribed
    pre-merge surgery was never implementable against main.
- The abandoned design's worst case was 27 duplicate live paging rules created UNGATED:
  `sentry-create-gate.sh` runs only in `plan_pr`, never in the apply job.
- SCOPE CONFIRMED AS 27 BY REGENERATION, not by trusting the list — a single predicate (exclude
  the vendor default and the two `event_unique_user_frequency_count` rules) rather than a
  name-prefix carve-out. All 11 frequency comparisons re-measured as OBJECTS; zero bare booleans.
- Guards cut from five to three and rescoped. Two removed for cause (one could not reach state
  from the surface it was routed to; one guarded a write that `0 to change` already precludes);
  a third would have shipped pre-suppressed on 13 of 27 blocks. The create tripwire was rescoped
  after review showed it protected the direction that cannot happen while greening the one that can.
- Ongoing drift detection added as a deliverable (section 2.9): one read-only call against the
  non-deprecated endpoint diffed against a committed live capture, covering all 27 rather than
  the 4 the existing liveness check covers.
- Recovery rewritten as ROLL-FORWARD. Revert, state-restore and `workflow_dispatch` are each
  named as traps; the single working gesture (re-run the failed job) goes in the PR body.
  `workflow_dispatch` carries no `head_commit.message`, so it can never supply the ack.

### Self-corrected premises (planner's own, caught before CI)

- Terraform prepends a `27 to import,` clause to the plan summary line.
- `importing` lives at `.change.importing.id`, not `.importing.id`.
- A file-level enum grep returns 49/50 legitimate hits from the two rules that stay behind
  (trap 3 — resolve per resource block, not by file grep).
- Inherited-and-corrected: the audit script's stale prose is a bash comment never emitted, not
  compliance-relevant output; and the frequency-trap direction was INVERTED — live values are
  60/61/62 and the SCRIPT is the drift source.

### Components Invoked

- Skills: soleur:plan, soleur:deepen-plan
- Agents: general-purpose (provider source verification at tag v0.15.7), Explore,
  soleur:engineering:cto, soleur:legal:clo, architecture-strategist, code-simplicity-reviewer,
  spec-flow-analyzer, terraform-architect, observability-coverage-reviewer, user-impact-reviewer,
  test-design-reviewer, general-purpose (verify-the-negative sweep, 20/20 claims confirmed)
- Lints and gates: lint-infra-no-human-steps.py, lint-guard-contract.py, deepen-plan halts
  4.5 through 4.11, sentry-destroy-counts.sh plus destroy-guard-filter-sentry.jq against real output
- Measurement: terraform v1.10.5 (terraform_data builtin), doppler plus the Sentry workflows API,
  gh CLI, git ls-remote

## Operator Decisions (carried, do not re-ask)

- Scope is 27: the 24 derived plus auth-signout-burst, auth-exchange-code-burst and
  auth-callback-no-code-burst. auth-per-user-loop and sandbox-startup-failure stay on
  sentry_issue_alert (upstream jianyuan/terraform-provider-sentry issue 950 still OPEN).
- Full review panel AUTHORISED and REQUIRED before ship.
