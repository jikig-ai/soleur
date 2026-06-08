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

## Re-plan Phase (2026-06-08)
- Status: COMPLETE. Re-scoped plan `knowledge-base/project/plans/2026-06-08-fix-cron-sandbox-dontask-allowlist-tiered-plan.md` (v2) supersedes the BLOCKED bypassPermissions plan.
- Approach: host-independent LAYERED containment (Tier-1, this PR, no infra) — L1 per-producer scoped `--allowedTools` (daily-triage model), L2 shared `Read(/proc/**)`+secret-file + egress/interpreter deny, L3 PreToolUse secret-scan hook, sandbox:false. Tier-2 follow-up issue = network-egress firewall (Terraform) + least-priv token, restores #5000 + broad/raw-bash crons. Operator chose two-PR scoping.
- 5-agent plan-review panel (security-sentinel + architecture-strategist + spec-flow-analyzer + CTO + CPO) found the v1 "scoped bash allowlist severs the chain" thesis FALSE (cat /proc/self/environ reads secrets as a file; gh issue create --body is an allow-only exfil sink on the public repo); all P0/P1 folded into v2. CPO: APPROVE-WITH-CONDITIONS (C1 community-monitor read-auth, C2 no-silent-degradation, C3 defer-tracking).
- Key corrections: blast radius is 12 (not 19/21); 3 crons spawn("bash") outside claude-code (Tier-2-only); roadmap-review WebSearch/WebFetch vestigial but its issue-body ingest is an injection surface; `dontAsk` settings.json acceptance is a Phase-0 gate.
- #5004 (roadmap-review) resolved by Tier-1; #5000 (growth-audit, broad) deferred to Tier-2 (fail-closed/contained, never exposed). PR body uses `Ref` not `Closes`.
- NEXT: `/clear` then `/soleur:work <plan-path>`. The BLOCKED implementation on this branch (commit 73890e6af bypassPermissions) must be REVERTED/REPLACED by the v2 approach during /work.

## Work + Review Phase (BLOCKED — superseded)
- Status: HALTED at review — P1 block, operator chose re-plan (2026-06-08)
- Implementation landed (sandbox-off + bypassPermissions overlay, tests GREEN: substrate 12/12, inngest 1429, webplat shard 8950) and committed (73890e6af), pushed to draft PR #5018.
- Review: 3 agents (security-sentinel, user-impact-reviewer, architecture-strategist) UNANIMOUS P1 block. The plan's "trusted prompt / 5-key env" premise is factually false for content-ingesting producers (community-monitor: HN/Discord ingest + 11 social write-tokens; bug-fixer: public issue bodies). Sandbox-off + bypassPermissions → injected bash exfiltrates creds.
- Findings + fix-option analysis: `review-findings-P1-block.md` (this dir).
- PR #5018 commented with the block. Issues #5000/#5004 remain OPEN.
- DO NOT merge this branch as-is. Re-scope via `/soleur:plan` before further work.
