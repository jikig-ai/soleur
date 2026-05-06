# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-concierge-pdf-and-issue-link-fix/knowledge-base/project/plans/2026-05-06-fix-cc-pdf-idle-reaper-and-issue-link-org-plan.md
- Status: complete
- Draft PR: #3326

### Errors
None. (One transient `gh pr view` error on issue numbers #3287/#3253 — they are *issues* not PRs; re-verified via `gh issue view`. Plan citations updated to disambiguate.)

### Decisions
- Two bugs bundled in one plan/PR: runner idle-reaper fix (Bug 1) + GitHub-org-slug fix in `message-bubble.tsx:251` (Bug 2). Same component for error-state branch, same trigger, Bug 2 is a one-character literal swap.
- Bug 1 root cause: `consumeStream` at `apps/web-platform/server/soleur-go-runner.ts:1043-1075` only handles `msg.type === "assistant"` and `msg.type === "result"`. SDK-emitted `user`-role messages with `tool_use_result` fall through, so the 90s idle timer fires while Anthropic processes the 10MB PDF. Fix: arm only `armRunaway` (preserving defense-pair invariant from PR #3225 / learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`).
- Detection field: `SDKUserMessage.tool_use_result?: unknown` (sdk.d.ts:2528) — cleaner than scanning `message.content`.
- KB-vs-Anthropic ceiling mismatch: `MAX_BINARY_SIZE = 50 MB` vs Anthropic PDF beta 32 MB. Sharp Edge entry + follow-up issue (post-merge); out of scope for this PR.
- Threshold: `single-user incident` (carried from #3253/#3287/#3294 chain); `requires_cpo_signoff: true` preserved.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
