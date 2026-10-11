# Hosted Bash approval prompts did not appear (SDK auto-allow pre-empted `canUseTool`) — 2026-10-11

Tracking: #10054 (P0). Detected by the real-SDK C9 probe of ADR-284 after #9977 shipped. Fixed on `feat-9776-c9-dev-probe`.

## What happened

In hosted workspaces the Claude Agent SDK never called `canUseTool` for sandboxed Bash. Two independent causes, each enough on its own:

1. `autoAllowBashIfSandboxed: true` (`server/agent-runner-sandbox-config.ts`) auto-allows a sandboxed Bash call before the callback.
2. The PreToolUse sandbox hook (`server/sandbox-hook.ts`) returned an explicit `allow` for every Bash command; a hook allow resolves the permission before `canUseTool`.

Everything in the Bash section of `createCanUseTool` was therefore inert: the safe-Bash allowlist, the #9977 must-ask lane (default-branch force-push/delete, `terraform destroy`, `gh` ref/repo delete), the autonomous-mode toggle's gate and the batch-approval cache. The sandbox, the blocklist and the GitHub token scope were the remaining controls.

## Window (bounds, not measured)

- Not bisected. #3252 (closed 2026-05-05) shows Command Center Bash prompting on SDK 0.2.85 with both causes already in the code, so
  the gate worked then; it was inert by the time of the probe on SDK 0.3.284. The start therefore lies between 2026-05-05 and the
  SDK 0.3.284 bump (#9236, merged 2026-09-29T22:02Z). The 0.3.x line arrived with #5849 on 2026-07-01, an untested candidate. A
  bisect of the SDK versions with the probe would settle it.
- The user-facing copy claiming an ask for destroy-family commands shipped with #9977 (merged 2026-10-11T10:25Z). The older line "with
  it off, it asks before every command" (from #4949, 2026-06-04) was false for as long as the gate was inert, and workspaces that chose
  "Ask me each time" also saw commands run without a prompt in that period.
- Still in force throughout: the sandbox (filesystem and network allowlists) and the GitHub token scope. NOT in force: every Bash check inside
  `canUseTool`, which includes the `BLOCKED_BASH_PATTERNS` blocklist (curl, wget, `sh -c`, sudo, eval) as well as the approval prompts.
- Terms: AUP 5.7 and T&C 3a.7 do not promise an ask, so they were accurate throughout.

## Gap in what we can say

Hosted `autonomous-bypass` lines are INFO and are not shipped to a queryable sink, so we cannot enumerate from telemetry whether any hosted destroy-family command ran in the window. The only record is each user's own repository history and infrastructure state.

## Fix

`autoAllowBashIfSandboxed: false` (sandbox stays on) and the hook returns `{ continue: true }` (no decision) for Bash; the sensitive-env deny is unchanged. The real-SDK probe (`apps/web-platform/scripts/dev-probe-destroy-ask.ts`) passes: three destroy forms reach the Approve/Reject card and leave the default branch unchanged; the control push reaches `canUseTool` and is not asked. The three user-facing Bash gates (review card, first-run disclosure, opt-out) now share one hold helper that fails closed on expiry and keeps the conversation status correct for stacked cards; they were unreachable code until now.

## Draft user notice (operator publishes; not published by the agent; fill the bracketed dates before use)

> Soleur's hosted Concierge is meant to pause for your approval before a default-branch force-push, `terraform destroy` or repository
> deletion, and the "ask before every command" setting is meant to prompt for each command outside a short read-only allowlist. For a
> period ending **[date the fix deployed]** (it began no later than **29 Sep 2026** and possibly earlier; we are determining the start)
> those prompts, and the command blocklist that sits beside them, did not apply in hosted workspaces, and commands ran without asking.
> The sandbox and your repository's GitHub token scope stayed in force. The prompts are restored as of **[deploy date]**. If you relied on
> them, review your repository's push and branch-deletion history (GitHub: repository Activity, or `git reflog` on any clone) and
> your infrastructure state for that period, and tell us if anything unexpected happened.

## Follow-ups

- Operator: publish or decline the notice above; add a breach-register row recording the decision (CLO). No Art. 33 clock is indicated (no personal-data compromise known).
- Re-run the probe after any SDK, CLI or sandbox-option bump.
- The legacy runner (`agent-runner.ts`, domain leaders) has no autonomous toggle or batch cache by design: every non-safe Bash there now asks, where before it ran unprompted. Wiring those deps into the legacy runner is the follow-up if that proves too noisy.
- The scheduled `soleur-eval` crons and the sandbox canary are not affected (they use their own permission setup).
