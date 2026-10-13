# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-15-fix-workspace-reprovision-ensure-dir-plan.md
- Status: complete

### Errors
None. CWD verified on first tool call. All deepen-plan mandatory gates passed (4.6 User-Brand Impact PRESENT single-user incident; 4.7 Observability PRESENT; 4.8 PAT-shaped CLEAN; 4.9 UI-wireframe skipped — no UI; 4.5 network-outage skipped).

### Decisions
- Root cause confirmed: realGraftRepoClone (ensure-workspace-repo.ts:159) clones into <workspacePath>/.ensure-repo-tmp-<uuid>; git clone creates only the leaf, so a missing workspacePath parent fails the clone. CWE-22 PR (merged 2026-06-15) only added UUID-shape guard, never creates the dir.
- Fix = one production line: `await mkdir(workspacePath, { recursive: true })` as first statement of realGraftRepoClone, before `const tmp`. Shared chokepoint for both leader (agent-runner.ts:1067) and Concierge (cc-reprovision.ts:52) callers.
- Do NOT export private ensureDir from workspace.ts (carries symlink-rejection semantics irrelevant here); inline mkdir captures only operative behavior. Resolver UUID validation upstream and untouched.
- TDD seam: failing-test-first in ensure-workspace-repo-graft-race.test.ts (mocks node:fs/promises), asserts mkdir(WS,{recursive:true}) runs before clone via invocationCallOrder. Hazard: mkdir mock must be added to suite's mock factory or all 5 existing tests break.
- Deepen improvements folded: collapsed AC1+AC2 into one test, added placement rationale, precedent diff, concurrency note (racing mkdirs idempotent).

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agent: code-simplicity-reviewer
- Agent: general-purpose (verify-the-negative grep)
