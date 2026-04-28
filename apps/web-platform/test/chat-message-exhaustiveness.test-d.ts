/**
 * Stage 4 (#2886) — TS-level exhaustiveness gate for the `ChatMessage`
 * discriminated union.
 *
 * This file does not run at vitest time (no `.test.ts` suffix). It compiles
 * under `tsc --noEmit` as part of the apps/web-platform tsc pass. If any
 * future variant is added to `ChatMessage` and an `assertExhaustive` switch
 * is missing the case, this file fails the build.
 *
 * Per `cq-union-widening-grep-three-patterns`, the union has TWO complementary
 * gates:
 *   1. This compile-time `: never` rail (catches missing branch).
 *   2. The `chat-surface.tsx` render-switch `: never` rail (catches missing
 *      render branch — different file, same pattern).
 *
 * Adding a variant requires adding a case here AND updating the render
 * switch in `chat-surface.tsx`. A grep on the `_exhaustive: never` constant
 * name lists every consumer.
 */

import type { ChatMessage } from "@/lib/chat-state-machine";

function assertExhaustive(msg: ChatMessage): string {
  switch (msg.type) {
    case "text":
      return msg.content;
    case "review_gate":
      return msg.gateId;
    case "subagent_group":
      return msg.parentSpawnId;
    case "interactive_prompt":
      return msg.promptId;
    case "workflow_ended":
      return msg.workflow;
    case "tool_use_chip":
      return msg.toolName;
    default: {
      const _exhaustive: never = msg;
      void _exhaustive;
      return "";
    }
  }
}

void assertExhaustive;
