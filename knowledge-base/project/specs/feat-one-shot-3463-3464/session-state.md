# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-07-feat-disconnect-race-and-incoming-types-capability-plan.md
- Status: complete

### Errors
The deepen-plan skill assumes the `Task` tool is available for spawning parallel review/research subagents (15+ engineering review agents and 4 research agents). The `Task` tool was not available in the nested skill-within-skill execution context. Mitigated by performing the equivalent reviewer-in-the-head verification work inline (live grep verification, three institutional-learning cross-references via Read, Context7 query for Supabase JS conditional UPDATE semantics, and AGENTS.md `cq-*` rule-walk). The deepen pass surfaced one load-bearing design flaw in the original plan (Insight 1: `expectMatch: true` contract collision) that would otherwise have been caught only at PR-review time.

### Decisions
- Bundled #3463 + #3464 in one plan — both are scope-outs from the same merged PRs (#3447, #3469) and touch the same WSMessage union and agent-runner abort/result branches; bundling avoids two near-simultaneous edits to the same surface.
- Issue #3463 — Path 1 (conditional UPDATE) chosen over Path 2 (in-flight flag) and Path 3 (state machine) — narrowest surface, multi-instance-safer than process-local state, defers the broader state-machine work tracked as a re-evaluation criterion.
- New helper `updateConversationStatusIfActive` introduced (deepen-pass discovery) instead of folding `onlyIfStatusIn` into the existing `updateConversationStatus` — the existing helper's `expectMatch: true` contract throws + Sentry-mirrors on 0-rows, which would fire on every clean disconnect-after-result (the intended success path).
- Issue #3464 — curated stable subset (`["abort_turn"]` only) chosen over full-union exposure or typed-tier-shape — mirrors the established `promptKinds` precedent without committing to broader contract evolution.
- Brand-survival threshold: `none` with explicit scope-out reason for the sensitive-path diff (per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`); failure modes are user-visible inconvenience, not single-user incident or aggregate exposure.
- Plan-time fix scope expanded to also emit `promptKinds` at both `session_started` sites — currently declared in schema but never reaches the wire (exact instance of the typed-optional-field-wire-drop pattern from the 2026-05-07 learning).

### Components Invoked
- soleur:plan skill
- soleur:deepen-plan skill
- mcp__plugin_soleur_context7__query-docs — Supabase JS UPDATE/PostgREST conditional filter semantics
- Direct file Reads: agent-runner.ts, ws-handler.ts, ws-zod-schemas.ts, lib/types.ts, conversation-writer.ts, abort-classifier.ts, ws-known-types.ts, three institutional learnings
- gh issue view — verified open status of #3463, #3464
- gh issue list --label code-review — overlap audit
- Live verification greps for: session_started emit/fixture sites, promptKinds canonical home, agent-runner line numbers, sensitive-path regex match
- Bash / Edit / Write / Read / ToolSearch
