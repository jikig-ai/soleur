---
date: 2026-09-15
category: integration-issues
module: web-platform-codex-replay
severity: high
tags: [codex, replay, observability, privacy, fail-closed]
---

# Codex replay translation must fail closed while making drift discoverable

## Problem

The Codex App Server can return persisted turns and item kinds that the neutral
web event contract does not understand. Silently skipping an item makes a
reconnect look complete when the transcript is incomplete; accepting the raw
provider object leaks protocol payloads across the adapter boundary. Malformed
history pages and recognized items also need to stop before dispatch persists a
partial replay.

## Solution

Keep translation pure and allowlist only payloads the neutral contract can
represent. The lifecycle source validates page, turn, and recognized-item
shapes, then throws a stable `codex_replay_invalid` error for malformed input.
Unsupported item kinds are dropped with a structured
`engine_replay_item_dropped` event carrying only a bounded item type and reason.
Malformed pages and items emit `engine_replay_failed` with a stable failure
class before throwing. The observability sink accepts narrow metadata and
swallows sink failures so telemetry cannot change provider behavior. Provider
payloads and native identities never enter those events.

## Key Insight

Replay compatibility is a data-loss boundary, not a best-effort parser. The
safe shape is a pure translator plus a lifecycle-owned validator and a
privacy-bounded signal for every discard or hard failure. Tests must cover both
the supported mapping and the unsupported/malformed branches; a green happy
path alone cannot show that replay drift is visible.

## Prevention

- Add a translator test before admitting each provider item kind.
- Bound and sanitize every field copied into telemetry; never include provider
  payloads, prompts, credentials, or native handles.
- Keep replay failure classes stable so dashboards and alerts survive provider
  vocabulary changes.
- Run the focused engine gate after each replay mapping change.

## Session Errors

1. The first review classification dump exceeded the context budget. **Prevention:** emit only bounded counts and cap path listings.
2. An inline shell environment assignment expanded before the command and produced `No such file or directory`. **Prevention:** export the variable in a prior command or use a literal absolute path; the companion shell learning records the reusable form.
3. Review subagents returned usage-limit errors. **Prevention:** emit explicit review coverage and use the documented inline fallback instead of claiming independent panel results.
4. A malformed JavaScript orchestration snippet failed before running its shell probe. **Prevention:** keep `functions.exec` snippets minimal and syntax-check the promise/brace structure before invoking tools.
5. A shell probe using `rm -f` was rejected by the command guard. **Prevention:** use Python or a safe temporary-file lifecycle instead of destructive shell cleanup patterns.
6. A preflight shell probe accidentally used command substitution despite the no-substitution ship/preflight contract. **Prevention:** pass values through per-worktree files and `read`, then run a separate bounded parser step.
7. A follow-up tool call assumed a shell variable persisted across calls and opened the wrong absolute path. **Prevention:** re-derive or pass the literal per-worktree path in every independent command invocation.
8. A merge-resync probe used a non-existent worktree path and failed before inspection. **Prevention:** copy the absolute worktree path from the session context and verify it with `test -d` before running dependent commands.
9. A broad generated-JSON diff emitted more than a megabyte and was truncated by the tool boundary. **Prevention:** inspect generated artifacts with bounded metadata (`wc`, `jq`, `head`) and prefer the source-of-truth regeneration script over raw diff output.
10. Worktree cleanup encountered an unregistered root-owned directory and could not remove it. **Prevention:** inspect ownership after cleanup, report the exact environment limitation, and do not claim orphan cleanup completed when permissions prevent it.
11. A post-resync Vitest/TypeScript probe ran from the repository root, where the app config and compiler are not installed. **Prevention:** derive the app working directory from the test package location before invoking project-local tooling.
12. A duplicate full-gate run waited on the repository-wide advisory lock behind several sibling gates and was interrupted after twelve minutes. **Prevention:** reuse a completed full-gate result when the diff is unchanged, and treat a contended rerun as blocked evidence rather than launching another interleaved run.
13. A local legal-lockstep probe compared only committed files (`origin/main...HEAD`) while the legal edits were still unstaged, so it reported a false missing-file result. **Prevention:** use the working-tree diff while validating before commit, then repeat against the pushed commit.
14. A migration-lint probe used a root-level script path that does not exist; the canonical script is under `apps/web-platform/scripts/`. **Prevention:** resolve plan paths with `rg --files` before invoking them.
15. A GitHub CLI job inspection requested an unsupported `steps` JSON field and failed before returning job state. **Prevention:** query the documented `gh` fields first, or use the Actions REST endpoint for step-level details.
16. A bounded `gh pr checks` probe yielded no captured output after its timeout even though the process had exited. **Prevention:** avoid chaining a sleep to a status probe at the yield boundary; run the status command directly and print its exit code.
17. A 30-second sleep used as a polling delay also yielded an undefined result at the tool timeout boundary. **Prevention:** use short direct status probes instead of timeout-length sleeps.
18. The first local constraint-gate invocation yielded before returning its session identifier, making its result unrecoverable from that tool call. **Prevention:** always print and retain the session ID when `yield_time_ms` can be reached, then resume with `write_stdin`.
19. The legal mirror-ratchet gate caught canonical-only additions to the three published legal mirrors. **Prevention:** every legal disclosure amendment must update canonical and Eleventy mirror surfaces together, then rerun the ratchet before pushing.
20. A combined PR-status probe (`git status`, remote SHA, PR JSON, and all checks) exceeded the tool context and was truncated before its result could be reviewed. **Prevention:** run bounded status, remote, PR, and check probes separately with explicit output caps.

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-217-pluggable-web-agent-engine-boundary.md`
- `knowledge-base/project/specs/feat-pluggable-web-agent-engines/codex-qualification-record.md`

## Tags

category: integration-issues
module: apps/web-platform/server/codex-app-server-lifecycle-source.ts
