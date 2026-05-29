# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-29-chore-twi-migrate-off-shared-org-targeted-plan.md
- Status: complete

### Errors
None. (CWD verified as the worktree before any work; all deepen-plan halt gates passed.)

### Decisions
- The issue's "tooling already supports this" premise is stale for steps 2-3. Step 1 (provision `team-workspace-invite-orgs` + add member orgs) is tooled by `flip.sh --org`; no verb exists to detach a feature from the shared `org-targeted` segment. D1-a (recommended): add a minimal, dry-run-gated, WORM-audited `flip.sh --detach-shared` mode reusing existing version-POST plumbing + eval-verify.
- Ordering is load-bearing; live mutations are post-merge. Provision+verify new segment BEFORE detaching the shared one; verify zero attachments BEFORE retiring `org-targeted`. PR ships tooling + tests + ADR-043 doc note; live prd flips + segment DELETE are ordered post-merge operator steps. `Ref #4617` (not `Closes`).
- Brand-survival threshold = `single-user incident` (inherited from #4581/PR-2); `requires_cpo_signoff: true`; user-impact-reviewer at review time. Use a real sibling org as `--control-org`.
- Precedent-diff confirmed the detach pattern is thin reuse (`segment_ids_to_delete_overrides` field already in every version-POST body). Verify-the-negative confirmed `server.ts:160` eval path is transparent to which segment carries the override — no app code change.
- Test runner verified live as `bash scripts/test-all.sh scripts` (CI `test-scripts` job, ci.yml:360).

### Components Invoked
- Skill: soleur:plan (#4617)
- Skill: soleur:deepen-plan (on the plan file)
- Halt gates 4.4/4.45/4.5/4.6/4.7/4.8 run inline; live gh citation checks for #4581 (CLOSED), #4612 (MERGED), #4616 (MERGED), #4617 (OPEN).
