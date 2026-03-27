# Learning: Tag-and-Route Multi-Leader Chat Architecture

## Problem

The web platform's chat system was locked to single-leader conversations at every layer: DB schema (NOT NULL constraint + CHECK), WebSocket protocol (start_session required leaderId), agent runner (single-leader system prompt), and UI (8-card dashboard grid). This prevented multi-domain conversations and forced users to know which department to visit before asking.

## Solution

Implemented the Meta-Router Pattern across 5 phases:

1. **Schema migration**: Made `domain_leader` nullable, added `leader_id` to messages for attribution
2. **Domain router**: Ported brainstorm domain-config assessment questions to server-side routing. Uses Claude Haiku via `fetch` for classification. @-mention parsing overrides auto-detection.
3. **Agent runner**: `dispatchToLeaders()` runs parallel sessions via `Promise.allSettled`. Per-leader stream lifecycle (`stream_start`/`stream`/`stream_end`) prevents interleaved output.
4. **WebSocket client**: Replaced single `streamIndexRef` with `Map<DomainLeaderId, number>` for multiplexing parallel leader streams into separate bubbles.
5. **UI**: Leader-attributed message bubbles with domain colors. Dashboard transformed to "Command Center" with primary auto-routed entry point.

Key review simplification: dropped `conversation_leaders` junction table (DISTINCT query on messages suffices), `routing_info` message type (leader attribution on bubbles is sufficient), `context_path`/`context_type` DB columns (context passed transiently via WebSocket).

## Key Insight

When porting a routing pattern from one platform to another (CLI plugin brainstorm domain-config → web platform), the assessment questions are the reusable asset, not the orchestration code. The web platform needed a completely different dispatch mechanism (parallel agent sessions vs sequential skill invocation) but the same classification logic.

For multi-stream multiplexing, a single tracking index (streamIndexRef) is fundamentally broken — it conflates "which message am I appending to" across all concurrent streams. A Map keyed by stream identifier is the minimum viable architecture.

## Session Errors

1. **Background agent NDJSON extraction** — Multiple failed read attempts on agent output files before discovering the correct Python JSON parsing approach. **Prevention:** Agent output files use NDJSON format — always use Python `json.loads` per line, not direct file reads.

2. **git add from wrong cwd** — Ran `git add` from `apps/web-platform/` instead of worktree root, causing pathspec mismatch. **Prevention:** Always `cd` to worktree root before git operations, or use absolute paths. The `pwd` check before writes (AGENTS.md rule) should extend to git commands.

3. **Markdown lint on plan file** — Missing blank lines around fenced code blocks and lists. **Prevention:** Run `markdownlint` mentally before committing plan files with embedded code blocks.

4. **Wrong SDK import** — Imported `@anthropic-ai/sdk` (not a project dependency) instead of using `fetch` for a single API call. **Prevention:** Check `package.json` dependencies before importing new packages. For single API calls, `fetch` is simpler than adding SDK dependencies.

## Tags

category: architecture
module: web-platform
