# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-concierge-tool-status-label/knowledge-base/project/plans/2026-05-05-fix-concierge-tool-status-verbose-label-plan.md
- Status: complete

### Errors
None. One in-flight self-correction during deepen: initial Risk #1 wording incorrectly framed the workspace-path resolution as a "relocation" of an existing call. Codebase verification (cc-dispatcher.ts:639-657 + realSdkQueryFactory cold-construction semantics) showed it's a NEW per-turn Supabase RTT on warm-Query turns. Plan corrected accordingly.

### Decisions

- **Root cause located server-side, not client-side.** Bug lives in `apps/web-platform/server/cc-dispatcher.ts:719-725` — `onToolUse` emits `label: block.name` (raw SDK name like `Read`) while the legacy `apps/web-platform/server/agent-runner.ts:1041-1052` correctly routes through `buildToolLabel(name, input, workspacePath)`. The "flash" the user sees is the agent's `text` block narration in `state: "streaming"` getting replaced when the bubble transitions to `state: "tool_use"` rendering the bare name.
- **Fix is symmetric with existing legacy path.** Route cc-dispatcher's `onToolUse` through `buildToolLabel` exactly like agent-runner does. Resolve `workspacePath` once via `fetchUserWorkspacePath(userId)` at the top of `dispatchSoleurGo` (already imported at line 64), with try/catch + `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`.
- **Threshold `none` with explicit scope-out** for sensitive-path regex hit (`apps/web-platform/server/`) — fix is a label-text routing change with zero credentials/auth/data surface; net direction is more conservative because sandbox-path scrub now applies to a path that previously bypassed it.
- **Single test file, additive only.** Extend `cc-dispatcher.test.ts` with two new tests (verbose label + workspace-resolve fallback). Existing `vi.hoisted` + `__resetDispatcherForTests` fixture pattern covers both. No conflicting test pins exist (`ws-streaming-state.test.ts:307` asserts the FALLBACK label, `tool-use-chip.test.tsx` uses synthetic verbose strings). `build-tool-label.test.ts` already protects ground truth.
- **Post-merge Sentry watch added** for `tool-label-fallback` (Bash verb allowlist gaps — `awk`/`sed`/`jq`/`head`/`tail` not yet covered) and `cc-dispatcher-workspace-resolve` (workspace-path resolution failures).

### Components Invoked

- skill: soleur:plan
- skill: soleur:deepen-plan
