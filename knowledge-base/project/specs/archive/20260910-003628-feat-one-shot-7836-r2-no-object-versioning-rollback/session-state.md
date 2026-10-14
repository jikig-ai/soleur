# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-06-chore-r2-rollback-runbook-repair-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Two notes:
- `soleur:engineering:review:spec-flow-analyzer` does not exist under that namespace; relaunched as
  `soleur:product:spec-flow-analyzer`.
- MCP servers `plugin:github:github` and `playwright` failed to connect. Neither was needed — the
  `gh` CLI and the AWS CLI covered all verification.

### Decisions
- Adopted the existing on-`main` plan for #7836 rather than writing a second one; retargeted its
  `branch:` frontmatter to this branch and updated in place.
- Re-probed R2 live on 2026-09-09: `list-object-versions` rc=254 `NotImplemented`, control
  `list-objects-v2` rc=0. The vendor gap persists, so Option 1a is refuted by measurement.
- Technical fork decided, not escalated: Option 2 (make the docs true) ships now; capability work
  defers to a tracking issue. The issue's proposed "scheduled copy" is the wrong trigger — a
  schedule recovers only to the last tick, while the damage is written by an apply.
- The recovery model itself was wrong, not just its mechanism: `infra/github/` auto-applies on
  merge, so no operator is present for a pre-apply snapshot, and state rollback does not fix a
  live-resource failure (step 3 re-applies the same bad config). Rebuilt as a failure taxonomy with
  config-revert first.
- Caught the plan about to commit its own defect: the draft's ADR-006 correction asserted the state
  is "locked", also false (all five backends set `use_lockfile = false`). ADR-006 carries two false
  limbs.

### Components Invoked
- `Skill: soleur:plan` -> `Skill: soleur:deepen-plan`
- Live R2 probe via `aws s3api` + `doppler -p soleur -c prd_terraform`; `gh issue view`; repo greps
- Agents: architecture-strategist, code-simplicity-reviewer, product:spec-flow-analyzer,
  infra:terraform-architect, legal:legal-compliance-auditor, research:learnings-researcher
- deepen-plan gates 4.6 / 4.7 / 4.8 / 4.9 / 4.10 / 4.11 — all pass

### Session Errors (review phase, 2026-09-09)

- **A `grep --include=*.tf` filter silently did not apply, and I built a review finding on the
  contaminated result.** Enumerating the Terraform roots that share `soleur-terraform-state` with
  `grep -rn --include=*.tf -A6 'backend "s3"' .` returned `telegram-bridge/terraform.tfstate` and
  `projects/web-app/prod/terraform.tfstate`; both hits came from `.md` files, so the run reported
  six roots where the tree has five. On that basis I raised a P2 against
  `infra/github/README.md` §5d ("Five roots share `soleur-terraform-state`") for an off-by-one
  it does not have, inside the `-force` warning where an under-count would understate a
  data-destruction blast radius. `code-simplicity-reviewer` refuted it from the branch's own plan
  (`2026-09-06-chore-r2-rollback-runbook-repair-plan.md`: the bucket holds six OBJECTS but five
  ROOTS; `telegram-bridge` was deleted in `dccc56dee` (#1586) and its state object is an orphan).
  Finding withdrawn.
  - **Control that would have caught it, and did once run:** grep a string known to live ONLY in a
    non-matching extension and confirm zero hits. `grep -rln --include=*.tf 'projects/web-app/prod' .`
    returns a `.md` path — the filter is not applied. The authoritative form is
    `git grep -l 'soleur-terraform-state' -- '*.tf'`, which resolves to exactly five: cla-evidence,
    web-platform, web-platform/rung2-rehearsal, web-platform/sentry, github.
  - **Why it matters beyond this branch:** an object count and a root count are different
    quantities over the same bucket, and the review skill's own rule is that arithmetic is the most
    fragile claim in a correction PR. I applied that rule to the document and not to my own
    measurement. The instrument was never verified against a known control before its output was
    read — `2026-08-10-my-sweep-missed-two-red-suites-and-my-battery-certified-garbage-mutations.md`
    names exactly this class.
  - Disposition: no rule change proposed. `hr-verify-repo-capability-claim-before-assert` and the
    review skill's "verify the instrument before reading its output" guidance already cover it;
    this is an instance, not a gap. Captured here so the withdrawal is on the record rather than
    silently dropped.
