# Learning: dir-scoped session lookup silently returns [] and leaks the very error the guard prevents

## Problem

The web Dashboard Concierge intermittently rendered a raw Anthropic
`API Error: 400 invalid_request_error "This model does not support assistant
message prefill. The conversation must end with a user message."` into the
response bubble on a resumed turn (PR #4852, after the chat-persistence
hardening #4831/#4848 made mid-turn INSERTs throw → more
assistant-terminated persisted sessions).

The `#3250` prefill guard (`apps/web-platform/server/agent-prefill-guard.ts`)
exists precisely to prevent this: it probes the persisted SDK session and
drops `resume:` when the session ends on an `assistant` turn (which
`claude-sonnet-4-6` 400s on). Yet the 400 still leaked.

## Root cause

The guard probed `getSessionMessages(resumeSessionId, { dir: workspacePath })`.
The Agent SDK persists sessions under `~/.claude/projects/<sanitized-cwd>/<id>.jsonl`
and re-derives that path from the `dir` argument. When the SDK persisted the
session under a **different cwd-encoding** than `workspacePath` (e.g. the
container's `process.cwd()` rather than the workspace path), the dir-scoped
lookup returned `[]` (file-not-found). The guard's empty-history branch then
**passed `resume:` through unchanged** → the SDK forwarded the
assistant-terminated thread → 400.

The session **existed** (it carried the assistant tail that caused the 400);
the probe just couldn't find it under the wrong dir. So the empty-history
"defensive passthrough" was firing on a false negative, in exactly the case
the guard was built to catch.

## Solution

Drop the `dir` argument entirely: `getSessionMessages(resumeSessionId)`. Per
the SDK (`sdk.d.ts:524`, "If omitted, searches all projects"), this searches
all project dirs. `resumeSessionId` is a globally-unique SDK-minted UUID, so
an all-projects search resolves the exact session regardless of cwd encoding
and is immune to the drift. The assistant-terminated tail is then found and
`resume:` is dropped correctly. One-line logic change; `workspacePath` kept on
the args for Sentry attribution only.

Chosen over the plan's two alternatives (flip empty-history→drop-resume (2a);
thread `dir==cwd` (2b-i)) because it is the smallest blast radius, directly
addresses the root cause regardless of *which* side's cwd was "wrong", and
does not break the dispatcher tests that mock `getSessionMessages → []` and
rely on empty→passthrough.

## Key Insight

**A scoped lookup that silently returns empty on a scope miss is indistinguishable
from a genuine absence — and if the empty branch is the "safe" default, the scope
miss defeats the guard in exactly its target case.** When a recovery primitive
probes for state by a key that is itself globally unique (a UUID), prefer the
*unscoped* lookup over a scoped one: the scope is a false constraint that can only
produce false negatives, never improve correctness. Ask "what does an empty result
actually mean here — absence, or a lookup miss?" before treating empty as safe.

## Session Errors

1. **[forwarded] Task tool unavailable inside the planning subagent (nested Task).** — Recovery: subagent grounded claims directly against `sdk.d.ts` + live `gh` instead of fanning out sub-agents. — Prevention: known nesting limitation; plan/deepen subagents should self-research rather than spawn (already documented in one-shot).
2. **Playwright `browser_navigate` first call returned "Target page, context or browser has been closed".** — Recovery: retried; succeeded. — Prevention: transient browser-launch race; a single retry (or `browser_close` then re-navigate) is the standard recovery (already in qa SKILL.md).
3. **Playwright `file:` protocol blocked.** — Recovery: served the static harness over `python3 -m http.server` and navigated to `http://localhost:<port>/`. — Prevention: Playwright MCP blocks `file:`; serve local HTML fixtures over HTTP.
4. **Playwright screenshot resolved to the bare-repo root, not the worktree CWD.** — Recovery: `find` located it at `<bare-root>/<name>.png`. — Prevention: already covered by `hr-mcp-tools-playwright-etc-resolve-paths`; pass an absolute in-worktree path or expect bare-root resolution.
5. **Visual harness failed to reproduce the flex min-content collapse (both before/after rendered single-line in a 900px column).** — Recovery: relied on unit className assertions + the nowrap mechanism (whitespace-nowrap forces min-content==max-content so a shrink-to-fit box can't collapse to longest-word width). — Prevention: a synthetic before/after harness for a flex *collapse* bug must reproduce the **exact** constraining nesting (nested shrink-to-fit with `min-w-0`), not just a generic wide container — otherwise the "before" doesn't wrap and the demo proves nothing. For component CSS that jsdom can't measure, the durable gate is the className unit assertion; treat a browser harness as a no-clip sanity check, not as the wrap repro unless the collapse condition is faithfully recreated.
6. **Cleanup Bash chain exited 144 (`pkill -f http.server` job interaction).** — Recovery: harmless; cleanup completed, verified via follow-up `ls`. — Prevention: terminate background helper servers with a captured PID (`kill "$PID"`) rather than `pkill -f <pattern>` which can self-match the running shell/job and surface a signal exit code.

## Tags
category: bug-fixes
module: apps/web-platform/server/agent-prefill-guard.ts
issue: 4852
related: 3250, 3263, 4831
