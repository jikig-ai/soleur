# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-08-fix-cron-bash-sandbox-bwrap-userns-failure-plan.md
- Status: complete

### Errors
None. CWD verified at start. All deepen-plan hard gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped, 4.9 UI-wireframe) passed. Task tool unavailable in subagent; Phase 1 research + review fan-out done via direct first-hand investigation.

### Decisions
- Premise correction: #5000/#5004 are the #4978/#4988 handler-level fallback working as designed (FAILED self-reports, not silent). Bug to fix is the underlying bwrap user-namespace failure.
- The "settings.json" the issue body names is the wrong file. The cron-governing config is the runtime-written DEFAULT_CLAUDE_SETTINGS overlay in _cron-claude-eval-substrate.ts:113 (single sandbox-config write site across all 41 inngest functions), NOT repo .claude/settings.json (governs dev sessions — must stay untouched).
- `sandbox.enabled: false` alone breaks every cron (removes autoAllowBashIfSandboxed). Fix MUST pair it with `permissions.defaultMode: "bypassPermissions"` (valid in pinned claude-code@2.1.142). Both keys colocated in shared overlay → fleet-wide fix for all 21 producers in one file.
- Host-independent over host-dependent: #4932 sysctl/systemd fix recurred 4 days later; durable fix removes cron's dependency on kernel sysctl. #4932/#4944 stay as defense-in-depth for non-cron consumers.
- Brand-survival threshold = single-user incident (requires_cpo_signoff: true); security trade-off bounded by verified env-allowlist, scoped short-lived token, throwaway workspace, trusted first-party prompt.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- mcp__plugin_soleur_context7 (Claude Code sandbox/permissions/settings docs)
- Bash, Read, Edit, Write, ToolSearch

## Work + Review Phase
- Status: HALTED at review — P1 block, operator chose re-plan (2026-06-08)
- Implementation landed (sandbox-off + bypassPermissions overlay, tests GREEN: substrate 12/12, inngest 1429, webplat shard 8950) and committed (73890e6af), pushed to draft PR #5018.
- Review: 3 agents (security-sentinel, user-impact-reviewer, architecture-strategist) UNANIMOUS P1 block. The plan's "trusted prompt / 5-key env" premise is factually false for content-ingesting producers (community-monitor: HN/Discord ingest + 11 social write-tokens; bug-fixer: public issue bodies). Sandbox-off + bypassPermissions → injected bash exfiltrates creds.
- Findings + fix-option analysis: `review-findings-P1-block.md` (this dir).
- PR #5018 commented with the block. Issues #5000/#5004 remain OPEN.
- DO NOT merge this branch as-is. Re-scope via `/soleur:plan` before further work.
