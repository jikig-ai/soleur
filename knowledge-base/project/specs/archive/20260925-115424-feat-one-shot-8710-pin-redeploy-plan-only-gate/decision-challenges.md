# Decision challenges — feat-one-shot-8710-pin-redeploy-plan-only-gate

Recorded headless by `soleur:plan` (plan review, 2026-09-24). Plan:
`knowledge-base/project/plans/2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md`.

## Taste — applied in plan v2, operator may revert

Each came from the named devex panel (`soleur:engineering:cto`). None changes scope, money or a
user-visible surface; all were applied to the plan and are listed so the operator can see them.

1. **Replace-job warning after a green apply names the runbook's recovery section.** When the
   source replace job is red but its apply step succeeded, the gate's warning points at
   `git-data-luks-cutover-5274.md` §"If the fresh host fails a boot check after step 3" and says
   to start with a read and not to replace again. Default if reverted: today's wording (dispatch the
   follower with no `source_run_id`).
2. **Read-only run against four real source runs before merge (AC5).** The rewritten gate is run
   with `SOURCE_RUN_ID` set to runs 35979044625, 35979304442, 34822248580 and 34836141887; it only
   calls `gh run view <id> --json jobs`. No workflow is dispatched. Default if reverted: fixtures
   only.
3. **Decision table in the gate's header comment, and a follower-lookup command in the runbook
   check (T-R1).** Default if reverted: the plan is the only place the table lives.

## Rejected — recorded for the operator

- **Split `terraform apply` into its own job** (Step 4.5 advisor consult). Rejected: it would ship
  the saved plan file (which embeds the git-data host private key) as a public artifact or apply an
  ungraded re-plan, and split the birth job's reviewer gate and the `git-data-state` lock across two
  jobs.
