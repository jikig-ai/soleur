# Learning: the SDK allowlist pre-approved the gated tier, and the fixes reopened the holes they closed

## Problem

In the hosted legacy agent runner the SDK `allowedTools` list contained every platform tool. The SDK approves a bare `allowedTools` entry before it consults `canUseTool`, so the `gated` tier (Approve/Reject card) never ran for 24 gated or default-gated tools. Exposure started 2026-04-06 (`create_pull_request`), not 2026-06-15, and spans GitHub writes, KB shares, CRM, workstream, account and email tools. A real-SDK probe (SDK 0.3.284) measured it; the SDK prints `CAN_USE_TOOL_SHADOWED` for these names.

## Solution

`buildAllowedTools` (pure, in `server/tool-tiers.ts`) keeps only auto-approve names and validated plugin wildcards; `buildAgentQueryOptions` asserts the allowlist form (rejects gated FQNs, `mcp__*`, non-default `permissionMode`, the Bash family). The gated branch of `canUseTool` fails closed on timeout/abort and restores status with a compare-and-set. Email cards show the whole send or deny. ADR-305 records the invariant.

## Key Insight

1. A fix that makes a dead path live (the gated card now reachable) exposes every defect on that path at once: card fidelity, reconnect replay, headless callers, status races. Review the newly reachable path, not only the filter.
2. The hardening reopened what it closed. The card sanitizer deleted angle brackets, truncated the recipient and omitted `replyTo`, so the human could approve a send that differed from the card. Widening the abort finalize to `waiting_for_user` (a binding CTO ruling) re-opened the #3463 disconnect-after-result race, and the rewritten test pinned the widened set.
3. Plan prose asserted unmeasured things: exposure start date, "no headless legacy caller", "the reaper flips it". Each fell to one `git log -S` or `grep`.

## Session Errors

1. **Resume brief named #4671 as the unstarted next link; it already had two merged PRs.** Recovery: `gh` verification, CTO re-ruling. **Prevention:** brief authors verify "next" and "unstarted" with `gh`; already in the go skill.
2. **`worktree-manager.sh` exceeded the 120 s tool timeout; gitleaks blocked a commit over a `.pen` `fileToken`, voiding bundled steps.** Recovery: background hydration, scrub, separate stage and commit calls. **Prevention:** `ux-design-lead` Step 3 now drops `fileToken`; stage and commit in separate calls.
3. **Plan Phase 0.4 premise (probe header: string prompts skip `canUseTool`) was wrong.** Recovery: one measured probe. **Prevention:** measure premises that a header comment asserts before building on them.
4. **Affected-tests gate returned rc=6 deferred; no tests ran for ~55 minutes.** Recovery: ran touched suites directly, CI as authority. **Prevention:** none new; known shared-queue behaviour.
5. **A binding CTO ruling (accept `waiting_for_user` in the abort finalize) contradicted #3463 and was implemented, with its test rewritten to match.** Recovery: security fix-round found it, CTO re-ruled, reverted to active-only. **Prevention:** a ruling that widens a status or permission guard is briefed with `git log -S` of the guard and the tests that pin it (routed into technical-ruling-delegation.md section 3).
6. **The card sanitizer made the approval card unfaithful (deleted delimiters, truncated recipient, hid `replyTo`, collapsed newlines in the UI).** Recovery: parse-once ASCII recipient, full body or deny, wrapping classes. **Prevention:** for any human-approval card, the review prompt asks "can the human approve something other than what executes", per field the schema accepts.
7. **Plan claims were unmeasured (exposure date, headless caller, reaper).** Recovery: git-history and user-impact seats. **Prevention:** existing rule on falsifying causal claims; no new rule.
8. **The edit tools turned `\uXXXX` escapes into literal characters in agent-written source.** Recovery: re-escaped and grepped for raw separators. **Prevention:** after any edit touching regex classes, grep the changed files for raw separators (already in `cq-regex-unicode-separators-escape-only`).
9. **The Stop hook caught a closing line that promised QA without running it.** Recovery: ran the next step. **Prevention:** none; the hook did its job.
10. **EDQUOT on the Claude temp volume briefly broke Bash during deepen-plan.** Recovery: cleared on its own. **Prevention:** one-off.

## Tags
category: security-issues
module: agent-runner, permission-callback, tool-tiers
