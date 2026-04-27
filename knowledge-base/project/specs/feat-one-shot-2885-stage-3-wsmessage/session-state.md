# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2885-stage-3-wsmessage/knowledge-base/project/plans/2026-04-27-feat-stage-3-wsmessage-protocol-extension-plan.md
- Status: complete

### Errors
None — both plan and deepen-plan executed successfully. Deepen-pass caught two material errors in the initial draft (zod version assumption + snake_case wire-field assumption) before they reached implementation.

### Decisions
- **Wire-field convention is camelCase, not snake_case.** Source plan in `2026-04-23-feat-cc-route-via-soleur-go-plan.md` Stage 3 prescribed snake_case (`prompt_id`, `conversation_id`, etc.). Direct grep of `lib/types.ts` confirmed the existing `WSMessage` convention is camelCase (`session_started.conversationId`, `usage_update.totalCostUsd`); this plan corrects the source plan and eliminates the rename burden across 7 importers / 63 test references.
- **Zod 4.3.6 is the target, not Zod 3.** Verified via `apps/web-platform/node_modules/zod/package.json` — already transitively installed; promote to direct dep in `package.json`. Plan adapts to Zod 4 API: `.brand()` modes (in/out/inout) and the non-generic `discriminatedUnion` discriminator (Zod 4 caveat); makes the bidirectional `_SchemaCovers` compile-time assertion load-bearing rather than optional.
- **Stage 3 reducer cases are inert pass-throughs.** Land the type rail + `: never` exhaustiveness in this PR; defer actual rendering and composite `(parentId, leaderId)` re-keying to Stage 4 of source plan. Files a follow-through tracking issue.
- **Fold in #2225, acknowledge #2191.** #2225 (`activeStreams` key tightening + `useMemo` derivation) overlaps directly; PR uses `Closes #2225`. #2191 (session-lifecycle refactor) is orthogonal — annotate via `gh issue comment`.
- **Defer source-plan task 3.10 (server-side text-delta coalescing).** Server-emit perf change orthogonal to type-protocol refactor; tracking issue filed in Phase 7.2.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- WebSearch (Zod 4 API verification)
- Direct codebase grep for verification (zod presence, useMemo state, wire-field convention, importer counts)
