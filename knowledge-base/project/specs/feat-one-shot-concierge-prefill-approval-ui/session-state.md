# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-02-fix-concierge-prefill-400-tool-approval-and-status-box-wrap-plan.md
- Status: complete

### Errors
- Task tool unavailable inside the planning subagent (nested Task); subagent compensated by researching directly and grounding claims against SDK type defs + live gh state. No blocking errors.

### Decisions
- Regression 1 root cause (SDK-grounded): the Agent SDK rebuilds the Anthropic messages array from the persisted session on `resume:`. The existing #3250/#3263 prefill guard has a false-negative — `getSessionMessages(resumeSessionId, { dir: workspacePath })` returns [] when `dir` doesn't byte-match the SDK's sanitized-cwd project dir, so the guard passes `resume:` through and claude-sonnet-4-6 400s. Dropping `dir` (SDK searches all projects) is a candidate smaller-blast-radius fix.
- #4824 (operator oauth) ruled out as active cause (gated to 2026-06-15 + flag + kill-switch; model stays claude-sonnet-4-6 today).
- "Every tool prompts" is partly working-as-designed: cited commands are genuinely not safe-bash and have prompted since #3344. Root-cause must distinguish inline-engineering Bash vs 400-retry re-prompting vs a genuine batched-cache regression. Do NOT loosen the allowlist.
- Regression 2 decoupled from #4838: fix is a CSS no-wrap/w-fit change in message-bubble.tsx (ToolStatusChip + header). Style tweak, wireframe gate SKIP.
- Threshold: single-user incident with requires_cpo_signoff: true (Concierge is the brand front door).

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Bash (git, rg/grep, gh, SDK grounding, commit/push), Read/Edit/Write
