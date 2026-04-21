---
title: LLM-SDK security tests need deterministic invocation, not natural-language prompts
category: best-practices
module: testing
date: 2026-04-19
tags: [testing, security, claude-agent-sdk, sandbox, plan-review]
related_issues: ["#1450"]
related_prs: ["#2610"]
---

# Learning: LLM-SDK security tests need deterministic invocation, not natural-language prompts

## Problem

When planning the #1450 MU3 cross-workspace isolation test suite, the
initial plan scaffolded the harness as:

```typescript
query({
  prompt: "Run this bash command: cat /workspaces/B/secret.md",
  options: { allowedTools: ["Bash"], permissionMode: "bypassPermissions", ... },
})
```

The idea was to drive tier-4 (bwrap) assertions by asking the model to
execute a specific shell command via the Bash tool. Kieran plan-review
(C1) flagged this as a security-gate blocker:

- The model may **refuse** the command on safety grounds.
- The model may **introspect first** (run `ls` or `stat` before `cat`).
- The model may **reword** the command (escape the path, add flags).
- The model may **emit the command as text** without invoking the tool.
- The model may **stall** while reasoning, exceeding the test budget.

Every assertion therefore has a hidden precondition: "…and the model
complied with the prompt exactly." For an MU3 security gate blocking
founder recruitment, this non-determinism is unacceptable — a green
suite would not actually prove OS-level isolation, only that the model
chose to comply on that run.

## Solution

Pick a deterministic invocation path that short-circuits the model:

1. **SDK direct tool-invocation entry** (preferred, if exposed) — call the
   Bash tool's input handler with a structured `{ command }` object,
   skipping the conversation layer entirely.
2. **Spawn bwrap with captured argv** — run the SDK once in an
   instrumented mode to capture the exact `bwrap` argv it produces,
   then in tests use `child_process.spawn("bwrap", capturedArgv,
   "bash", "-c", attackCommand)`. Deterministic; no model involved;
   SDK minor bumps force re-capture.
3. **`query()` with prompt** (last resort, document the caveat) — if
   the SDK has no direct entry and argv capture isn't feasible, accept
   the model-compliance risk but surface it explicitly in test comments
   and monitor flake rate.

For the #1450 plan, Phase 1 of the implementation is a spike that
picks between (1)–(3) before any test code lands. The plan's other
phases branch on the spike output — if the SDK has no direct entry,
the harness shape changes from `query()`-based to `spawn()`-based, and
the scaffolding notes in Phases 3–6 are amended inline.

A secondary issue surfaced during Context7 research: the production
`agent-runner.ts:941-958` config uses a nested `permissions.allow`
field that reads like an SDK option but is actually a wrapper around
the SDK added by our app code. The SDK-level option is
`allowedTools: string[]`. A spec carry-forward paraphrased the wrapper
as if it were the SDK option, and the plan had to reconcile it
explicitly. Plan authors must distinguish SDK-level options (authoritative
from Context7 / SDK docs) from app-level wrapper options (authoritative
from the specific file that wraps `query()`).

## Key Insight

**Any test that wants to prove a security invariant of an LLM-mediated
tool must remove the LLM from the assertion path.** The model is the
least deterministic component in the stack; a test whose pass condition
depends on the model choosing to execute a specific command is testing
model compliance, not the security invariant. This generalizes beyond
bwrap — any SDK-routed tool call, any agent-mediated API action, any
MCP server driven by natural-language input is subject to the same
trap.

The corollary: **security tests against LLM-mediated infrastructure
should be architected to fail closed**, meaning the test design assumes
the model will be uncooperative and still produces a meaningful
assertion. If the test only passes when the model cooperates, it will
flake in CI and silently pass in prod when the model drifts.

## Session Errors

- **Initial plan prescribed natural-language-prompt-based tier-4 assertions**
  — caught by plan-review before any code shipped. Recovery: refocused
  the Phase 1 spike on picking a deterministic invocation path; amended
  all assertion scaffolding to branch on spike output. Prevention: see
  the plan-skill route below (Sharp Edges entry about LLM-mediated tests).
- **Spec TR4 paraphrased `agent-runner.ts` wrapper options (`permissions.allow`) as if they were SDK options** — caught by Context7 query during plan research. Recovery: added `## Research Reconciliation — Spec vs. Codebase` section to the plan. Prevention: plan skill's existing "Research Reconciliation" mechanism catches these if the repo-research-analyst flags gaps; no change needed.

## Related

- Plan: `knowledge-base/project/plans/2026-04-18-test-cross-workspace-isolation-mu3-plan.md`
- Spec: `knowledge-base/project/specs/feat-verify-workspace-isolation/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-18-verify-workspace-isolation-brainstorm.md`
- Learning (four-tier defense model): `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- PR: #2610
- Issue: #1450
