# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-17-chore-credential-persist-home-guard-plan.md
- Status: complete

### Errors
- Initial plan Write rejected because plan skill already wrote a complete plan at target path; adopted it and strengthened the Open Code-Review Overlap section. No content lost.
- One tasks.md Write required Read-before-overwrite; recovered.
- All deepen-plan hard gates (4.5-4.9, 4.55) passed with no halt.

### Decisions
- PR #6623 (DOCKER_CONFIG relocation) MERGED; #6565 OPEN but independent repair-and-soak issue — plan does not gate on it.
- Guard architecture: enumerate ProtectHome/ProtectSystem units → flat fail-closed `unit → {script|NONE}` map (resolves webhook→hooks.json→ci-deploy-wrapper→ci-deploy.sh indirection) → family-table cred scan → relocation-off-home check. Boot-time root logins excluded by construction.
- Collapsed to ONE test file (simplicity): M1-M8 are the guard's ordinary RED cases, inline beside GREEN per ci-deploy.test.sh.
- Two P0 anti-vacuity strengthenings: resolve one level of `${VAR:-default}` indirection (M7); in-guard non-empty-scan census (AC8) so green != "scanned nothing".
- Battery expanded to M1-M8 (+M3b/M3c/M5b/M7b) with per-mutation fresh copies and finding-text attribution.

### Components Invoked
- Skill: soleur:plan (#6633); soleur:deepen-plan
- Agents: 2x Explore, test-design-reviewer, code-simplicity-reviewer
- gh / git
