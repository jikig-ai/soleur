---
date: 2026-04-27
issue: 2885
parent_pr: 2858
plan: knowledge-base/project/plans/2026-04-27-feat-stage-3-wsmessage-protocol-extension-plan.md
---

# Tasks: Stage 3 WSMessage protocol extension

## Phase 0 — Preflight

- [x] 0.1 — `cd apps/web-platform && npm view zod@latest version` → record exact version. Pin in `package.json` with no `^`.
- [x] 0.2 — `command -v rg` to confirm ripgrep available.
- [x] 0.3 — Confirm Stage 3.8 greps recorded in plan §Test Strategy still match worktree HEAD.

## Phase 1 — RED (failing tests first)

- [x] 1.1 — Add `"zod": "4.3.6"` (exact pin, no `^`) to `apps/web-platform/package.json` `dependencies`. Run `cd apps/web-platform && npm install` to regenerate `package-lock.json`. Verified at deepen time: zod 4.3.6 already in `node_modules` transitively, so install is a promotion-only no-op at the lock level.
- [x] 1.2 — Write `apps/web-platform/test/branded-ids.test.ts`. Run via `./node_modules/.bin/vitest run test/branded-ids.test.ts` from `apps/web-platform/`. Confirm RED.
- [x] 1.3 — Write `apps/web-platform/test/ws-zod-schemas.test.ts`. Confirm RED (imports unresolved).
- [x] 1.4 — Extend `apps/web-platform/test/ws-protocol.test.ts` with new variant round-trips + Zod rejection cases. Confirm RED.
- [x] 1.5 — Extend `apps/web-platform/test/chat-state-machine.test.ts` with inert pass-through cases for new event types + `_exhaustive: never` assertion test. Confirm RED.

## Phase 2 — GREEN: foundation (branded IDs + Zod schemas)

- [x] 2.1 — Implement `apps/web-platform/lib/branded-ids.ts`. Run `vitest run test/branded-ids.test.ts` → GREEN.
- [x] 2.2 — Implement `apps/web-platform/lib/ws-zod-schemas.ts` (against current Stage 2 `WSMessage` shape). Commit checkpoint.
- [x] 2.3 — `tsc --noEmit` passes in `apps/web-platform/`.

## Phase 3 — GREEN: extend `WSMessage` discriminated union

- [x] 3.1 — Inline `TodoItem` interface into `apps/web-platform/lib/types.ts`.
- [x] 3.2 — Replace `WSMessage` `interactive_prompt` / `interactive_prompt_response` `unknown`-shape variants with the 14-variant discriminated sub-union (6 `interactive_prompt` kinds + 4 `interactive_prompt_response` shapes + 4 new event types: `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`).
- [x] 3.3 — Add `WorkflowEndStatus` export + `WorkflowName` re-export in `lib/types.ts`.
- [x] 3.4 — Port `_AssertKindsMatch` exhaustiveness check from the shim into `lib/types.ts`, retargeted at the new `WSMessage` `interactive_prompt` variants vs. `InteractivePromptKind` from `pending-prompt-registry.ts`.
- [x] 3.5 — Extend `KNOWN_WS_MESSAGE_TYPES` set in `lib/ws-known-types.ts` with the 4 new entries. Confirm `_Exhaustive` proof passes `tsc --noEmit`.
- [x] 3.6 — Extend `lib/ws-zod-schemas.ts` with the 14 new variants + `_SchemaCovers` bidirectional assertion. Run `vitest run test/ws-zod-schemas.test.ts test/ws-protocol.test.ts` → GREEN.
- [x] 3.7 — `tsc --noEmit` passes (importer-side breakage at the 7 sites is expected; resolved in Phase 5).

## Phase 4 — GREEN: reducer + Zod parser at boundary

- [x] 4.1 — Extend `apps/web-platform/lib/chat-state-machine.ts:applyStreamEvent` switch with inert pass-through cases for `subagent_spawn`, `subagent_complete`, `workflow_started`, `workflow_ended`, `interactive_prompt`. Append `default: const _exhaustive: never = event; void _exhaustive; return { messages: prev, activeStreams };` rail. Update `StreamEvent` type alias.
- [x] 4.2 — Re-key `activeStreams` from `Map<string, number>` to `Map<DomainLeaderId, number>` end-to-end (`chat-state-machine.ts:applyStreamEvent`, `applyTimeout`, `StreamEventResult`, `ws-client.ts:ChatState`, all reducer paths). Drop `as DomainLeaderId[]` cast on the `useMemo` derivation in `ws-client.ts`.
- [x] 4.3 — Replace `JSON.parse(...) as WSMessage` cast in `ws-client.ts:onmessage` with `parseWSMessage(parsed)`. On failure: `reportSilentFallback(parseResult.error, { feature: "command-center", op: "ws-zod-parse-failure", extra: { rawType } })`. Keep `isKnownWSMessageType` fast-path before the Zod parse.
- [x] 4.4 — Add `case "interactive_prompt"` + four new event types to the outer `switch (msg.type)` in `ws-client.ts:onmessage`, dispatching to the reducer (`dispatch({ type: "stream_event", msg })`).
- [x] 4.5 — Run `vitest run test/chat-state-machine.test.ts test/ws-protocol.test.ts` → GREEN.
- [x] 4.6 — `tsc --noEmit` passes from `apps/web-platform/`.

## Phase 5 — Delete shim + rewrite importers

- [x] 5.1 — Rewrite test importers (leaf nodes first). Wire fields stay **camelCase** per deepen-pass field-naming correction — only the import source path changes:
  - `test/cc-dispatcher.test.ts` — `import type { WSMessage } from "@/lib/types"` + alias `type InteractivePromptResponse = Extract<WSMessage, { type: "interactive_prompt_response" }>`. The 12 existing `promptId`/`conversationId` references stay as-is.
  - `test/cc-interactive-prompt-response.test.ts` — same. The 44 references stay as-is.
  - `test/soleur-go-runner-interactive-prompt.test.ts` — same with `InteractivePromptEvent` aliased to `Extract<WSMessage, { type: "interactive_prompt" }>`. The 7 references stay as-is.
- [x] 5.2 — Rewrite production importers (import source path + alias only; camelCase fields preserved):
  - `server/cc-dispatcher.ts`, `server/ws-handler.ts`, `server/cc-interactive-prompt-response.ts`, `server/soleur-go-runner.ts` — same alias pattern.
- [x] 5.3 — `git rm apps/web-platform/server/cc-interactive-prompt-types.ts`.
- [x] 5.4 — `tsc --noEmit` passes.
- [x] 5.5 — Full `vitest run` passes from `apps/web-platform/`.
- [x] 5.6 — `rg "cc-interactive-prompt-types" apps/web-platform/` returns zero hits.
- [x] 5.7 — `rg "InteractivePromptEvent\|InteractivePromptResponse" apps/web-platform/server/` shows no straggler imports from the deleted file.
- [x] 5.8 — Skipped per deepen-pass field-naming correction (no field renames; existing camelCase preserved end-to-end).

## Phase 6 — REFACTOR / Sweep

- [x] 6.1 — Re-run Stage 3.8 greps; record output in PR body. Confirm no new widening sites surfaced.
- [x] 6.2 — Verify `lib/ws-known-types.ts:_Exhaustive` proof + `lib/types.ts:_AssertKindsMatch` both compile.
- [x] 6.3 — Run `vitest run` from `apps/web-platform/` once more — no regression.
- [x] 6.4 — `next lint` passes.

## Phase 7 — Lifecycle

- [x] 7.1 — Update `server/cc-interactive-prompt-response.ts` header comment: replace "Stage 2.14" marker with Stage 3 PR reference.
- [x] 7.2 — File two follow-through tracking issues:
  - **Server-side text-delta coalescing** (source plan task 3.10) — milestoned per `roadmap.md`.
  - **Composite `(parent_id, leader_id)` re-keying of `activeStreams`** — Stage 4 dependency.
- [x] 7.3 — Comment on #2191 with cross-link to this PR explaining acknowledge-not-fold disposition.
- [x] 7.4 — Run `skill: soleur:compound` per `wg-before-every-commit-run-compound-skill`.
- [x] 7.5 — `skill: soleur:ship` — PR body uses `Closes #2885` and `Closes #2225`. Stage 3.8 grep output documented in PR description.
