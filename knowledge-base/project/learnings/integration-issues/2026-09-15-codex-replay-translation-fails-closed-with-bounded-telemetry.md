---
date: 2026-09-15
category: integration_issue
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

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-217-pluggable-web-agent-engine-boundary.md`
- `knowledge-base/project/specs/feat-pluggable-web-agent-engines/codex-qualification-record.md`

## Tags

category: integration-issues
module: apps/web-platform/server/codex-app-server-lifecycle-source.ts
