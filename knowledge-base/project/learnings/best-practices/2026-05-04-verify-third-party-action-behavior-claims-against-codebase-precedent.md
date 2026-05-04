---
title: Verify third-party-action behavior claims against codebase precedent before relying on them
date: 2026-05-04
category: best-practices
module: plan-skill, deepen-plan-skill, schedule-skill
tags: [planning, verification, third-party-actions, codebase-precedent, claude-code-action]
source_session: one-shot fix for #3153 (PR #3155)
synced_to: [plan]
related:
  - ../2026-04-22-verification-claims-in-plans-decay-silently.md
  - ../2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying.md
  - ../../integration-issues/2026-05-04-claude-code-action-app-token-lacks-actions-write.md
---

# Verify third-party-action behavior claims against codebase precedent

## Problem

PR #3155 replaced the schedule plugin's `--once` template D4 self-disable (`gh workflow disable`) with a YAML-edit-and-push neutralization primitive. The plan, deepen-plan, and work phases all asserted:

> "Use the `claude[bot]` identity that `claude-code-action` already configures (no separate `git config user.*` step needed)."

This claim was unverified. The deepen-plan agent did substantial upstream research on `claude-code-action`'s permission scope (correctly identifying the App's installation manifest caps `actions:*` at READ) but treated the git-identity claim as background knowledge.

Multi-agent review caught it as a P1 blocker. The architecture-strategist agent grep'd the repo and found that **all 10 sibling Soleur scheduled-*.yml workflows** that push from inside `claude-code-action` explicitly run:

```yaml
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
```

before any `git commit`. Without this step, `git commit` aborts with "Author identity unknown" and the entire D4 path silently fails — the exact regression #3153 was supposed to fix.

The bug class: **claim about third-party-action behavior, accepted from research output without grepping the repo for prior usage.**

This is distinct from `2026-04-22-verification-claims-in-plans-decay-silently.md` (claim true at write-time, decayed by env mutation) — here the claim was never verified at all. It's also distinct from `2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying.md` (review agent prescribes a CLI flag) — here the planning agent asserts an action's behavior.

## Solution

Two additions in plan/deepen-plan workflow:

1. **Codebase-precedent check for third-party-action behavior claims.** When a plan asserts "action X already does Y" or "Y is auto-injected by Z", grep the same repo for prior usage of X/Z and verify the claim against precedent. Cheap: `grep -rn "X" .github/workflows/`.
2. **Anti-regression test.** When a sharp behavior of a third-party tool is load-bearing (commit succeeds, push succeeds, OIDC handshake completes, etc.), assert the precondition's presence in test code, not just in prose.

Applied in PR #3155 via:

- Explicit `git config user.name/email` in step 4 of the neutralization primitive (matching the canonical sibling pattern).
- Two new TS1 assertions enforcing both `git config` lines are present in the generated workflow template.

## Key Insight

Plan-time research is good at "what does this third-party action *claim* to do" (docs, manifest files, GitHub issues). Plan-time research is bad at "what does this third-party action *actually need from the surrounding workflow* to do that thing reliably." The codebase has the second answer in the form of working precedent — every Soleur workflow that already does what the plan is proposing.

**Heuristic:** Before relying on any claim about third-party-action behavior, ask "does this exact pattern already exist in our `.github/workflows/`?" If yes, copy the canonical version. If no, the claim is unverified and you owe a precondition test.

## Prevention

- **Plan-skill Sharp Edge:** When a plan asserts behavior of a third-party action, grep the repo for prior usage and reconcile the claim against precedent in the same step. (Routed to `plan/SKILL.md` Sharp Edges.)
- **Test-design rule:** When a load-bearing precondition lives in the surrounding workflow (not in the action itself), the TS suite must assert the precondition's textual presence — not "the action does X" but "the workflow runs Y before X".
- **Multi-agent review remains the load-bearing safety net** for this class. Architecture-strategist's grep-and-compare pattern caught it in seconds. The lesson is not "write better plans" — it is "the plan-time gate cannot be the only gate; codebase-precedent reconciliation must run somewhere".

## Session Errors

- **First plan+deepen subagent hit a usage limit and produced no artifacts** — Recovery: spawned a fresh agent with the issue body pre-summarized so it could skip re-fetching. Prevention: not workflow-preventable (env rate limit).
- **Initial RED test rewrite broke TS2 (date-guard ordering anchor) and TS3 (idempotency anchor)** — Recovery: caught by next test run; switched anchors to the `## Final step` heading and the `already neutralized` substring. Prevention: when a test rewrite removes a string referenced as an anchor by other tests, grep all tests for that anchor before declaring the rewrite complete.
- **P1 git-config-not-auto-configured claim accepted from plan output without verification** — the main learning above. Recovery: architecture-strategist grep, fix-inline. Prevention: codebase-precedent check before relying on third-party-action behavior claims.

## Related

- `2026-04-22-verification-claims-in-plans-decay-silently.md` — claim-true-at-write-time, decayed
- `2026-04-19-verify-reviewer-prescribed-cli-flags-before-applying.md` — review-agent prescribes wrong flag
- `../../integration-issues/2026-05-04-claude-code-action-app-token-lacks-actions-write.md` — the technical fix this session shipped
