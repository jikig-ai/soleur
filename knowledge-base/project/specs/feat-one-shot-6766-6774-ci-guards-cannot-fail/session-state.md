# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-fix-ci-guards-that-cannot-fail-plan.md
- Status: complete
- Scope verified: `git diff origin/main...HEAD --name-only` listed only
  `knowledge-base/project/{plans,specs}/` paths — planning subagent stayed in mandate.

### Errors
None blocking. Two issues found *in the inputs*, both resolved in the plan:

1. **The issue's prescribed ordering is inverted** (DC-1). #6766 part 1 calls "add
   `deploy-script-tests` as a required context" the lowest-risk action. It is the
   highest-risk one available: `infra-validation.yml` is `pull_request`-path-filtered
   with no `merge_group:`, so a path-filtered workflow posts no status context at all
   on PRs it does not match — a required context there sits at "Expected — Waiting for
   status" forever, wedging every PR in the repo. Documented in the workflow's own
   comment and the entire subject of open issue #6480 ("Do not simply add the context
   to the ruleset"). Recorded for operator confirmation; `/ship` files it as
   `action-required`.
2. **Plan v1 reproduced the target defect class** (DC-2). Its aggregator would have
   shipped green on #6766's own headline case: the existing gate step opens with
   `if [[ "$DIRS" == "[]" ]]; then exit 0`, and v1's acceptance criterion only checked
   that a string *appeared* in the step — which unreachable code after `exit 0`
   satisfies. Caught by the review panel; fixed in v2 by extracting the verdict to a
   unit-tested fail-closed allow-list script.

No `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain`
(TR2 fail-closed).

### Decisions
- **Two PRs, workflow-first, not one.** PR A = workflow routing + all of #6774;
  PR B = the ruleset flip, gated on empirically observing the context post on a live
  PR. Reverses v1's atomicity choice — the "required-but-unposted window" argument
  only rules out the *reverse* split, and at `single-user incident` threshold
  empirical verification beats a string-membership test.
- **`infra-validate-required` becomes the required context, not `deploy-script-tests`.**
  The latter is a 12-minute docker build; both existing `-required` precedents are
  cheap always-run aggregators. Its result folds into the aggregator, preserving the
  issue's intent without putting the build on every PR's critical path.
- **Direction 2 chosen for #6774** (`discoverability_test.kind`), with seven
  fail-closed guardrails. Direction 1 rejected on a ground the issue did not state:
  the blocker is not the pipe, it is that `<run-id>` has no subject at preflight time.
  Direction 3 rejected because it degrades toward "any command we cannot run → SKIP" —
  the exact silent downgrade the issue forbids.
- **Fold in #6480** — its scope is a superset of #6766 parts 1 and 3; leaving it open
  after doing its work would itself be a stale-guard defect.
- **`detect-changes` gains `suite_relevant` as a second output.** Gating on
  `directories` alone would silently disable the cross-file drift guards, since the
  `paths:` union deliberately exceeds the terraform-root set.

### Components Invoked
- `Skill: soleur:plan` → `Skill: soleur:deepen-plan`
- `Explore` x3 (ruleset/required-checks surface; preflight Check 10 surface;
  verify-the-negative sweep)
- `soleur:engineering:review:architecture-strategist`,
  `soleur:product:spec-flow-analyzer` (escalated panel per single-user-incident
  threshold)
- Deepen-plan gates 4.4, 4.5, 4.55, 4.6, 4.7, 4.8, 4.9 — all pass
- `gh` CLI for live issue/PR/label/ruleset probes; `git grep` / `git ls-tree
  origin/main` for attribution and ADR-ordinal verification
