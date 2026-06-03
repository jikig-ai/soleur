# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-concierge-git-askpass-plumbing/knowledge-base/project/plans/2026-06-03-feat-concierge-git-askpass-in-sandbox-plumbing-plan.md
- Status: complete

### Errors
- `iac-plan-write-guard` PreToolUse hook blocked the first two Write attempts on the phrase "out-of-band" (operator-driven/manual-infra framing) despite the `<!-- iac-routing-ack -->` comment. Resolved by removing the "out-of-band" wording (plan introduces zero infra). No other errors.
- SDK type-defs (`@anthropic-ai/claude-agent-sdk`) not installed in this worktree's node_modules, so the managed-domain source-read was deferred to /work — but Outcome-A premise is settled by the empirical prod signal, so non-blocking.

### Decisions
- Item 1 (PRIMARY) committed to Outcome A (sandbox reaches github.com); no B-branch carried. Askpass script MUST be written under `workspacePath` (verified sandbox-readable); `$HOME`/`/tmp` unverifiable. New `writeAskpassScriptTo(dir)` in `git-auth.ts`; token reuses cold-path `ghToken` riding `GIT_INSTALLATION_TOKEN` env.
- Reconciliation finding (item 3): ARGUMENTS says "two `log.info({userId})` breadcrumbs" but codebase has exactly ONE (`ensure-workspace-repo.ts:91`). The two `reportSilentFallback` sites are guard-allowlisted (hash via `hashExtraUserId`) and must NOT be touched.
- Optional `github_*` MCP-tool wiring DEFERRED to existing #3722 (OPEN: "promote read-only MCP tools to cc-router via CC_MCP_ALLOWLIST"). Outcome A makes in-sandbox git the working path; CPO-gated robustness add, not required.
- Cold-start mock obligation: if item 1 adds a `git-auth` import to `cc-dispatcher.ts`, it MUST be `vi.mock`'d in BOTH `cc-dispatcher-real-factory.test.ts` AND `cc-dispatcher-prefill-guard.test.ts`. A new `buildAgentEnv` parameter alone needs no new mock.
- Threshold `single-user incident` → `requires_cpo_signoff: true` retained (installation-token leak / cross-tenant askpass-read is the brand-survival surface).

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash, Read, Write, Edit

## Collision Gate Note
- #4868/#4890 MERGED (contextual predecessors, not work targets). #3698 CLOSED (contextual citation — the userId-emission guard whose resolution is already in main; item 3 complies with it, does not duplicate). Operator pre-acknowledged; continued.
