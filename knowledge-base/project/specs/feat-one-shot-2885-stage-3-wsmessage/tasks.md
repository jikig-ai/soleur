---
date: 2026-04-27
issue: 2885
parent_pr: 2858
plan: knowledge-base/project/plans/2026-04-27-feat-stage-3-wsmessage-protocol-extension-plan.md
---

# Tasks: Stage 3 WSMessage protocol extension

## Phase 0 — Preflight

- [ ] 0.1 — `cd apps/web-platform && npm view zod@latest version` → record exact version. Pin in `package.json` with no `^`.
- [ ] 0.2 — `command -v rg` to confirm ripgrep available.
- [ ] 0.3 — Confirm Stage 3.8 greps recorded in plan §Test Strategy still match worktree HEAD.

## Phase 1 — RED (failing tests first)

- [ ] 1.1 — Add `zod` to `apps/web-platform/package.json`. Regenerate `package-lock.json` (`npm install` from `apps/web-platform/`).
- [ ] 1.2 — Write `apps/web-platform/test/branded-ids.test.ts`. Run via `./node_modules/.bin/vitest run test/branded-ids.test.ts` from `apps/web-platform/`. Confirm RED.
- [ ] 1.3 — Write `apps/web-platform/test/ws-zod-schemas.test.ts`. Confirm RED (imports unresolved).
- [ ] 1.4 — Extend `apps/web-platform/test/ws-protocol.test.ts` with new variant round-trips + Zod rejection cases. Confirm RED.
- [ ] 1.5 — Extend `apps/web-platform/test/chat-state-machine.test.ts` with inert pass-through cases for new event types + `_exhaustive: never` assertion test. Confirm RED.

## Phase 2 — GREEN: foundation (branded IDs + Zod schemas)

- [ ] 2.1 — Implement `apps/web-platform/lib/branded-ids.ts`. Run `vitest run test/branded-ids.test.ts` → GREEN.
- [ ] 2.2 — Implement `apps/web-platform/lib/ws-zod-schemas.ts` (against current Stage 2 `WSMessage` shape). Commit checkpoint.
- [ ] 2.3 — `tsc --noEmit` passes in `apps/web-platform/`.

## Phase 3 — GREEN: extend `WSMessage` discriminated union

- [ ] 3.1 — Inline `TodoItem` interface into `apps/web-platform/lib/types.ts`.
- [ ] 3.2 — Replace `WSMessage` `interactive_prompt` / `interactive_prompt_response` `unknown`-shape variants with the 14-variant discriminated sub-union (6 `interactive_prompt` kinds + 4 `interactive_prompt_response` shapes + 4 new event types: `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`).
- [ ] 3.3 — Add `WorkflowEndStatus` export + `WorkflowName` re-export in `lib/types.ts`.
- [ ] 3.4 — Port `_AssertKindsMatch` exhaustiveness check from the shim into `lib/types.ts`, retargeted at the new `WSMessage` `interactive_prompt` variants vs. `InteractivePromptKind` from `pending-prompt-registry.ts`.
- [ ] 3.5 — Extend `KNOWN_WS_MESSAGE_TYPES` set in `lib/ws-known-types.ts` with the 4 new entries. Confirm `_Exhaustive` proof passes `tsc --noEmit`.
- [ ] 3.6 — Extend `lib/ws-zod-schemas.ts` with the 14 new variants + `_SchemaCovers` bidirectional assertion. Run `vitest run test/ws-zod-schemas.test.ts test/ws-protocol.test.ts` → GREEN.
- [ ] 3.7 — `tsc --noEmit` passes (importer-side breakage at the 7 sites is expected; resolved in Phase 5).

## Phase 4 — GREEN: reducer + Zod parser at boundary

- [ ] 4.1 — Extend `apps/web-platform/lib/chat-state-machine.ts:applyStreamEvent` switch with inert pass-through cases for `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`, `interactive_prompt`. Append `default: const _exhaustive: never = event; void _exhaustive; return { messages: prev, activeStreams };` rail. Update `StreamEvent` type alias.
- [ ] 4.2 — Re-key `activeStreams` from `Map<string, number>` to `Map<DomainLeaderId, number>` end-to-end (`chat-state-machine.ts:applyStreamEvent`, `applyTimeout`, `StreamEventResult`, `ws-client.ts:ChatState`, all reducer paths). Drop `as DomainLeaderId[]` cast on the `useMemo` derivation in `ws-client.ts`.
- [ ] 4.3 — Replace `JSON.parse(...) as WSMessage` cast in `ws-client.ts:onmessage` with `parseWSMessage(parsed)`. On failure: `reportSilentFallback(parseResult.error, { feature: "command-center", op: "ws-zod-parse-failure", extra: { rawType } })`. Keep `isKnownWSMessageType` fast-path before the Zod parse.
- [ ] 4.4 — Add `case "interactive_prompt"` + four new event types to the outer `switch (msg.type)` in `ws-client.ts:onmessage`, dispatching to the reducer (`dispatch({ type: "stream_event", msg })`).
- [ ] 4.5 — Run `vitest run test/chat-state-machine.test.ts test/ws-protocol.test.ts` → GREEN.
- [ ] 4.6 — `tsc --noEmit` passes from `apps/web-platform/`.

## Phase 5 — Delete shim + rewrite importers

- [ ] 5.1 — Rewrite test importers (leaf nodes first):
  - `test/cc-dispatcher.test.ts` — `import type { WSMessage } from "@/lib/types"` + alias `type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>`. Sweep all camelCase wire fields → snake_case.
  - `test/cc-interactive-prompt-response.test.ts` — same.
  - `test/soleur-go-runner-interactive-prompt.test.ts` — same with `InteractivePromptEvent` aliased to `Extract<WSMessage, { type: "interactive_prompt" }>`.
- [ ] 5.2 — Rewrite production importers:
  - `server/cc-dispatcher.ts`, `server/ws-handler.ts`, `server/cc-interactive-prompt-response.ts`, `server/soleur-go-runner.ts` — same alias pattern; sweep camelCase → snake_case wire fields.
- [ ] 5.3 — `git rm apps/web-platform/server/cc-interactive-prompt-types.ts`.
- [ ] 5.4 — `tsc --noEmit` passes.
- [ ] 5.5 — Full `vitest run` passes from `apps/web-platform/`.
- [ ] 5.6 — `rg "cc-interactive-prompt-types" apps/web-platform/` returns zero hits.
- [ ] 5.7 — `rg "InteractivePromptEvent\|InteractivePromptResponse" apps/web-platform/server/` shows no straggler imports from the deleted file.
- [ ] 5.8 — `rg "\.promptId|\.conversationId" apps/web-platform/` reviewed manually to ensure unrelated `Conversation.id` / `session_started.conversationId` references are NOT renamed.

## Phase 6 — REFACTOR / Sweep

- [ ] 6.1 — Re-run Stage 3.8 greps; record output in PR body. Confirm no new widening sites surfaced.
- [ ] 6.2 — Verify `lib/ws-known-types.ts:_Exhaustive` proof + `lib/types.ts:_AssertKindsMatch` both compile.
- [ ] 6.3 — Run `vitest run` from `apps/web-platform/` once more — no regression.
- [ ] 6.4 — `next lint` passes.

## Phase 7 — Lifecycle

- [ ] 7.1 — Update `server/cc-interactive-prompt-response.ts` header comment: replace "Stage 2.14" marker with Stage 3 PR reference.
- [ ] 7.2 — File two follow-through tracking issues:
  - **Server-side text-delta coalescing** (source plan task 3.10) — milestoned per `roadmap.md`.
  - **Composite `(parent_id, leader_id)` re-keying of `activeStreams`** — Stage 4 dependency.
- [ ] 7.3 — Comment on #2191 with cross-link to this PR explaining acknowledge-not-fold disposition.
- [ ] 7.4 — Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`.
- [ ] 7.5 — `skill: soleur:ship` — PR body uses `Closes #2885` and `Closes #2225`. Stage 3.8 grep output documented in PR description.
