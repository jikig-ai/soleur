# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-command-center-qa-fixes/knowledge-base/project/plans/2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md
- Status: complete
- Draft PR: https://github.com/jikig-ai/soleur/pull/3020

### Errors
None. Context7 MCP returned "Monthly quota exceeded" for SDK doc lookups; mitigated by reading the installed `@anthropic-ai/claude-agent-sdk/sdk.d.ts` directly.

### Decisions
- Rejected `--dangerously-skip-permissions` (SDK `bypassPermissions`). Confirmed via `sdk.d.ts:1101-1111` it bypasses `canUseTool`, `BLOCKED_BASH_PATTERNS`, `FILE_TOOLS` sandbox-path check, and plugin MCP allowlist — unsafe in a multi-tenant web app where the LLM consumes prompt-injection-vulnerable user input. Replaced with a narrow `SAFE_BASH_PATTERNS` allowlist (read-only file/git/cwd commands only) plus shell-metacharacter denylist.
- Root-caused `runner_runaway` P1. `soleur-go-runner.ts:578-587` arms a 30s wall-clock timer on first `tool_use` and only clears on `SDKResultMessage`. While a Bash review-gate awaits the user's click, no result arrives → timer fires. Fix: `notifyAwaitingUser(conversationId, boolean)` plumbed through `cc-dispatcher.ts updateConversationStatus` (already toggles `waiting_for_user`/`active`).
- Rename target: "Soleur Concierge" (brand-voice match); fall back to user's "Soleur System Agent" if blocked at copywriter review. Internal id `cc_router` unchanged (would ripple into 8 test files + state-machine narrowing).
- Compact resolved interactive-prompt cards across all 6 variants — matches `ReviewGateCard:40-49` pattern; shared `<ResolvedCardRow>` subcomponent.
- Bonus AC18: replace "Workflow ended (runner_runaway) — retry to continue" with typed `WORKFLOW_END_USER_MESSAGES` map and compile-time exhaustiveness rail.

### Components Invoked
- `skill: soleur:plan` (Phase 2.6 user-brand-impact authored; engineering domain only)
- `skill: soleur:deepen-plan` (Phase 4.6 user-brand-impact halt passed; SDK contract verified via direct sdk.d.ts read; learning #840 cross-referenced)
- Direct file research: `apps/web-platform/server/{soleur-go-runner,permission-callback,cc-dispatcher,agent-runner-query-options,domain-leaders}.ts`, `components/chat/{interactive-prompt-card,review-gate-card}.tsx`, `lib/types.ts`
- Git: plan + tasks committed (99839ab4)
