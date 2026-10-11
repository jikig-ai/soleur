# Hosted Bash approval prompts did not appear (SDK auto-allow pre-empted `canUseTool`) — 2026-10-11

Tracking: #10054 (P0). Detected by the real-SDK C9 probe of ADR-284 after #9977 shipped. Fixed on `feat-9776-c9-dev-probe`.

## What happened

In hosted workspaces the Claude Agent SDK never called `canUseTool` for sandboxed Bash. Two independent causes, each enough on its own:

1. `autoAllowBashIfSandboxed: true` (`server/agent-runner-sandbox-config.ts`) auto-allows a sandboxed Bash call before the callback.
2. The PreToolUse sandbox hook (`server/sandbox-hook.ts`) returned an explicit `allow` for every Bash command; a hook allow resolves the permission before `canUseTool`.

Everything in the Bash section of `createCanUseTool` was therefore inert: the safe-Bash allowlist, the #9977 must-ask lane (default-branch force-push/delete, `terraform destroy`, `gh` ref/repo delete), the autonomous-mode toggle's gate and the batch-approval cache. The sandbox, the blocklist and the GitHub token scope were the remaining controls.

## Window (bounds, not measured)

- Latest start of the inert gate: the SDK 0.3.x pin (#9236, merged 2026-09-29T22:02Z). Not bisected against the previous SDK, so the true start may be earlier or the same.
- The user-facing copy claiming an ask for destroy-family commands shipped with #9977 (merged 2026-10-11T10:25Z).
- The settings line "with it off, it asks before every command" predates #9977 and was false for the same reason; workspaces that chose "Ask me each time" also saw commands run without a prompt.
- Terms: AUP 5.7 and T&C 3a.7 do not promise an ask, so they were accurate throughout.

## Gap in what we can say

Hosted `autonomous-bypass` lines are INFO and are not shipped to a queryable sink, so we cannot enumerate from telemetry whether any hosted destroy-family command ran in the window. The only record is each user's own repository history and infrastructure state.

## Fix

`autoAllowBashIfSandboxed: false` (sandbox stays on) and the hook returns `{ continue: true }` (no decision) for Bash; the sensitive-env deny is unchanged. The real-SDK probe (`apps/web-platform/scripts/dev-probe-destroy-ask.ts`) passes: three destroy forms reach the Approve/Reject card and leave the default branch unchanged; the control push reaches `canUseTool` and is not asked. The generic Bash gate also fails closed on expiry (it was unreachable code until now).

## Draft user notice (operator publishes; not published by the agent)

> Between 30 Sep and 11 Oct 2026, Concierge approval prompts did not appear in hosted workspaces. This includes the pause before a default-branch force-push, `terraform destroy` or repository deletion, and the "ask before every command" setting: commands ran as if autonomous mode were on. This is fixed. If you rely on those prompts, review your repository history and infrastructure state from that period.

## Follow-ups

- Operator: publish or decline the notice above; add a breach-register row recording the decision (CLO). No Art. 33 clock is indicated (no personal-data compromise known).
- Re-run the probe after any SDK, CLI or sandbox-option bump.
- Legacy runner (`agent-runner.ts`) has no autonomous toggle or batch cache by design (ADR-284 AC-5): every non-safe Bash there now asks.
