# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-08-fix-concierge-clone-consumes-self-healed-installation-plan.md
- Status: complete

### Errors
None. CWD verified equal to the worktree on first tool call. All deepen-plan gates passed.

### Decisions
- Root cause confirmed verbatim against current main (post-#5031): cc-dispatcher.ts:1333 passes the bare stored installationId to ensureWorkspaceRepoCloned; effectiveInstallationId is computed at :1394-1459 (after the clone) and consumed only by the mint (:1464) and C4 write tool (:1523). The clone is the one consumer still on the wrong install → 403 → no .git → "No Git Repository in Workspace."
- Fix is ORDERING, not new logic: hoist the connectedOwner/connectedRepo parse (:1354-1368) + the self-heal block (:1394-1459) to before the clone, then pass effectiveInstallationId into ensureWorkspaceRepoCloned. Verify-the-negative grep proved the intervening region (:1283-1329) reads none of the clone/self-heal symbols.
- Fail-closed security invariant preserved: effectiveInstallationId === installationId in every non-promotion branch, so the clone can never gain access beyond the PR #4946 entitlement gate.
- Test home: extend the existing "installation self-heal" describe block in cc-dispatcher-real-factory.test.ts; hoist the inline ensureWorkspaceRepoCloned mock (:152) to a named top-level spy to make AC1 assertable.
- Gates: 4.6 (User-Brand Impact, single-user incident, requires_cpo_signoff:true), 4.7 (Observability, 5 fields no SSH), 4.8 (no PAT vars), 4.9 (no UI) all pass.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan; Bash, Read, Write, Edit
