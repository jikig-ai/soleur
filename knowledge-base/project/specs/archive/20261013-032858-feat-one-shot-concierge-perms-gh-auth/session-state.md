# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-concierge-perms-gh-auth/knowledge-base/project/plans/2026-06-03-fix-concierge-gh-auth-and-bash-permissions-plan.md
- Status: complete

### Errors
None blocking. Two pipeline-context constraints handled explicitly (not silently):
- Task/Explore subagent fan-out and Pencil/ux-design-lead tooling unavailable in this one-shot context; deepen gates 4.4/4.6/4.7/4.8/4.9 executed inline against the live codebase.
- Deepen gate 4.9 (UI-wireframe) is a genuine HARD-BLOCK (plan touches UI) — recorded as a deferred hard-block to /work Phase 2.5 (the producer phase where Pencil tooling exists), NOT a silent skip.

### Decisions
- Issue A premise corrected: do NOT reuse mintInstallationToken() (hardcoded to jikig-ai/soleur). Concierge must use membership-checked resolveInstallationId(userId) (ADR-044) then generateInstallationToken (token-cache-memoized).
- GH_TOKEN != GITHUB_TOKEN: provider envVar is GITHUB_TOKEN (lower gh precedence); GH_TOKEN in no allowlist. Inject GH_TOKEN via new typed buildAgentEnv(..., opts?: { ghToken }) param, NOT the BYOK-clobberable serviceTokens map.
- Issue B part 1 conservative: read-only gh verbs only; &&-decomposition with per-segment re-application of intact denylists; 2>/dev/null + 2>&1 carve-out only (no file-redirect); blocklist authoritative-first. worktree-manager.sh has only create/cleanup-merged (both destructive) — AC8 allowlist likely empty; /work must confirm or drop.
- Issue B part 2 (autonomous toggle): off-by-default workspaces.bash_autonomous column; owner-only SECURITY DEFINER write RPC; fail-closed read; blocklist still authoritative under autonomy; risk-interstitial UI; agent-native MCP tool pair on the legacy agent-runner.ts surface (cc-router wires platformToolNames: [], so tool cannot live there).
- Threshold: single-user incident; requires_cpo_signoff: true (toggle is an approval-bypass on a code-executing surface). 6 logically-separated commits, phased by dependency direction (schema/contract before consumer).

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Inline verification (Bash/Read/Edit) for premise validation, precedent-diff gate, deepen gates 4.4/4.6/4.7/4.8/4.9, rule-ID/citation checks.
