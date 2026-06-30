# Learning: PostToolUse(Skill) additionalContext is the autonomous-safe vehicle for per-phase context injection — UserPromptSubmit is not

## Problem

For L3 per-phase tool/skill scoping (#5768) we needed to inject a phase-relevant
hint into the agent's context at workflow-phase transitions (brainstorm → plan →
work → review → ship). The first design wrote a phase token from a PreToolUse
hook and injected the hint from a `UserPromptSubmit` hook keyed off that token.

Plan-review (spec-flow-analyzer) found the load-bearing defect: **`UserPromptSubmit`
never fires during `one-shot`** — the autonomous pipeline submits ONE user prompt,
then drives plan→work→review→ship internally via Skill calls with no further user
prompts. So the hint delivered ~zero surface reduction on the *primary* autonomous
flow, and the plan/deepen phases (run in a Task subagent) wrote the token under a
different `session_id` than the parent reader keyed on.

## Solution

Use a single **stateless PostToolUse hook on the `Skill` matcher**. It fires after
*every* skill call — interactive AND autonomous (`one-shot`) AND in subagents —
reads `tool_input.skill`, maps it to a phase, and emits the hint as
`hookSpecificOutput.additionalContext`. No token file, no session_id plumbing, no
sentinel (the skill call IS the phase signal at the moment it fires).

This dissolved five separate review findings at once (token-file, session-id split,
on-change sentinel, `.gitignore`, flock contention) and fixed the autonomous-flow
defect.

## Key Insight

**Match the injection vehicle to where the phase transition actually happens.**
- **PreToolUse** can gate (`permissionDecision`) but **cannot inject context**.
- **PostToolUse** CAN inject context (`hookSpecificOutput.additionalContext`) and
  fires on every tool call including in autonomous runs and subagents.
- **UserPromptSubmit / SessionStart** inject context but only at *user-turn* /
  *session* boundaries — which **do not exist inside the autonomous pipeline**.

So any "inject context when the agent does X" feature where X is a *tool call*
(not a user turn) must ride PostToolUse, or it silently no-ops in `one-shot`.

### Live-verified contract (CC 2.1.196, empirical probe)

Mirroring `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md`, a stub
PostToolUse(`Skill`) hook was wired and driven via a nested `claude --print` that
called a skill. Confirmed:
- PostToolUse **fires for the `Skill` tool** (`tool_name=Skill`,
  `hook_event_name=PostToolUse`, `tool_input.skill` present).
- Its `additionalContext` **reaches the model** as a `<system-reminder>`
  immediately after the skill call.

CC hook output gotchas (claude-code-guide, official docs): additionalContext is
capped at **10,000 chars**; `hookEventName` is required; **exit code matters** —
exit 2 = blocking error, any *other* non-zero = JSON output **silently skipped**.
So a fail-open hint hook MUST `exit 0` on every path: a non-zero exit doesn't just
"not block", it drops the hint with no signal.

### `tool_input.skill` is model-controlled, not config-trust

The skill name in the PostToolUse envelope is whatever the model emitted — a
prompt-injected model (e.g. mid-WebFetch) can craft it. So it is sharper than
AGENTS.md (operator-reviewed). Discipline: emit only **map-derived constant** hint
text (never echo the skill name), look it up via `jq --arg` (never interpolate
into a jq program / eval / path), build the envelope via `jq -n --arg`. An
adversarial test (`{"skill":"x\";$(touch /tmp/pwn)"}`) gates all three.

## Tags
category: workflow-patterns
module: claude-code, hooks, harness, agent-sdk

## Cross-References
- ADR-070 (`knowledge-base/engineering/architecture/decisions/ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md`)
- `.claude/hooks/phase-surface-hint.sh` (the hook) · `.claude/hooks/pencil-collapse-guard.sh` (PostToolUse additionalContext precedent)
- `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` (the empirical-probe method this mirrors)
- [GitHub #5768](https://github.com/jikig-ai/soleur/issues/5768) · PR #5769 · web parity #5772
- `2026-06-30-brainstorm-inventory-existing-scoping-before-no-scoping-premise.md` (sibling learning from the same feature)
- `2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools.md` (the web-side silent-fail mode that kept the web lever fail-open / deferred)

## Session Errors
- **0.1b (subagent context-reach) not live-probed.** The parent case (0.1a) was
  definitively confirmed; forcing a subagent Skill call in-sandbox is expensive/
  flaky, so the subagent-context-reach question was left to the design fallback
  (hook covers parent-run work/review/ship; skill-body delivery is the fallback for
  plan/deepen if needed). **Prevention:** recorded in the PR body as a known-
  unverified with the fallback, not silently assumed.
