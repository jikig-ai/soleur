// Feature-local WS message types for the Command Center `/soleur:go`
// interactive-prompt bridge.
//
// Stage 2 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md. The
// canonical Stage 3 extension to `lib/types.ts:WSMessage` adds these as
// full discriminated sub-unions with branded PromptId / ConversationId
// and Zod parsing at the WS boundary (plan §"Stage 3 — WebSocket
// Protocol Extension"). Until that lands, this module provides a
// narrower interim shape so Stage 2 wiring can compile end-to-end.
//
// TODO(#2853-stage-3): delete this file when `WSMessage` absorbs the
// structured `interactive_prompt` / `interactive_prompt_response`
// sub-union. Replace every import of `InteractivePromptEvent` /
// `InteractivePromptResponse` with the equivalent `WSMessage` variant.
// The runner + ws-handler should then emit via the canonical
// `sendToClient(userId, { type: "interactive_prompt", ... })` rather
// than a separate emitter.
//
// The six kinds mirror `server/pending-prompt-registry.ts`
// `InteractivePromptKind` verbatim. Payload shapes mirror the plan's
// Stage 3 `interactive_prompt` variants (grep the plan for
// `type: "interactive_prompt"`). Keep both files in sync until
// migration.

import type { InteractivePromptKind } from "./pending-prompt-registry";

export interface TodoItem {
  id: string;
  content: string;
  status: "pending" | "in_progress" | "completed";
}

export type InteractivePromptPayload =
  | { kind: "ask_user"; payload: { question: string; options: string[]; multiSelect: boolean } }
  | { kind: "plan_preview"; payload: { markdown: string } }
  | { kind: "diff"; payload: { path: string; additions: number; deletions: number } }
  | { kind: "bash_approval"; payload: { command: string; cwd: string; gated: boolean } }
  | { kind: "todo_write"; payload: { items: TodoItem[] } }
  | { kind: "notebook_edit"; payload: { notebookPath: string; cellIds: string[] } };

export type InteractivePromptEvent = {
  type: "interactive_prompt";
  promptId: string;
  conversationId: string;
} & InteractivePromptPayload;

export type InteractivePromptResponse =
  | { type: "interactive_prompt_response"; promptId: string; conversationId: string; kind: "ask_user"; response: string | string[] }
  | { type: "interactive_prompt_response"; promptId: string; conversationId: string; kind: "plan_preview"; response: "accept" | "iterate" }
  | { type: "interactive_prompt_response"; promptId: string; conversationId: string; kind: "bash_approval"; response: "approve" | "deny" }
  | { type: "interactive_prompt_response"; promptId: string; conversationId: string; kind: "diff" | "todo_write" | "notebook_edit"; response: "ack" };

// Bidirectional exhaustiveness assertion against the registry's own
// kind union (pattern-recognition HIGH: 4-way drift risk). Both
// directions must compile — the payload union must cover every kind
// in the registry AND every registry kind must be reachable from the
// payload union. A 7th kind added to either side fails compilation
// here and surfaces the drift immediately.
type _AssertKindsMatch =
  InteractivePromptKind extends InteractivePromptPayload["kind"]
    ? InteractivePromptPayload["kind"] extends InteractivePromptKind
      ? true
      : never
    : never;
const _exhaustiveKindCheck: _AssertKindsMatch = true;
void _exhaustiveKindCheck;
