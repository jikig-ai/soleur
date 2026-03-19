# Tasks: Remove Stale Bypass Actor 262318

## Phase 1: Execute Removal

- [x] 1.1 Read current ruleset state via `gh api GET /repos/jikig-ai/soleur/rulesets/13304872` and confirm 262318 is still present
- [x] 1.2 Execute `gh api PUT /repos/jikig-ai/soleur/rulesets/13304872` with complete payload (262318 removed from bypass_actors, all other fields preserved)
- [x] 1.3 Read back ruleset via GET and verify:
  - [x] 1.3.1 bypass_actors contains exactly 3 entries (OrganizationAdmin null, RepositoryRole 5, Integration 1236702)
  - [x] 1.3.2 rules unchanged (cla-check with integration_id 15368)
  - [x] 1.3.3 enforcement is "active"
  - [x] 1.3.4 conditions target ~DEFAULT_BRANCH

## Phase 2: Verification

- [ ] 2.1 Verify bot workflow still works: check a recent bot PR or trigger a bot workflow to confirm auto-merge succeeds with synthetic cla-check status
- [x] 2.2 Verify human PR flow: confirm the CLA check is still required on the current PR (this feature branch PR itself serves as the test)

## Phase 3: Cleanup

- [x] 3.1 Update the todo file `todos/027-complete-p2-investigate-bypass-actor-262318.md` status to completed
- [ ] 3.2 Add a learning documenting the stale bypass actor pattern and prevention guidance
- [ ] 3.3 Commit plan, tasks, learning, and todo update
