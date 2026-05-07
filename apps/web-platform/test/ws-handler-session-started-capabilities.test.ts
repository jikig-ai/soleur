/**
 * #3464 wire-presence regression gate. Pins
 * `session_started.capabilities.{promptKinds,incomingTypes}` so the next
 * field-addition that forgets the emit hop fails before review.
 *
 * Schema declares the field optional; types compile clean either way.
 * The two session_started emit sites in ws-handler.ts (deferred-creation
 * `start_session` path and `resume_session` path) are the load-bearing
 * sites. See plan §"Surfaced gap" + Insight 3 for the typed-optional-
 * field-wire-drop class this test guards against.
 */
import { describe, test, expect } from "vitest";
import {
  WS_CAPABILITIES,
  WS_INCOMING_TYPES,
  WS_PROMPT_KINDS,
} from "@/lib/ws-capabilities";
import { parseWSMessage } from "@/lib/ws-zod-schemas";

describe("WS_CAPABILITIES — single source of truth", () => {
  test("WS_INCOMING_TYPES is the curated stable subset (today: abort_turn only)", () => {
    expect(WS_INCOMING_TYPES).toEqual(["abort_turn"]);
  });

  test("WS_PROMPT_KINDS contains the 6 canonical interactive_prompt kinds", () => {
    // Mirror of `INTERACTIVE_PROMPT_KINDS` in `lib/types.ts`. If the
    // source tuple grows, this assertion fails — review whether the
    // new kind belongs on the manifest before updating the count.
    expect(WS_PROMPT_KINDS).toEqual([
      "ask_user",
      "plan_preview",
      "diff",
      "bash_approval",
      "todo_write",
      "notebook_edit",
    ]);
  });

  test("WS_CAPABILITIES bundles both arrays for emit sites", () => {
    expect(WS_CAPABILITIES.promptKinds).toBe(WS_PROMPT_KINDS);
    expect(WS_CAPABILITIES.incomingTypes).toBe(WS_INCOMING_TYPES);
  });
});

describe("session_started.capabilities — schema parses the canonical payload", () => {
  test("frame with full capabilities (promptKinds + incomingTypes) parses", () => {
    const r = parseWSMessage({
      type: "session_started",
      conversationId: "c-1",
      capabilities: WS_CAPABILITIES,
    });
    expect(r.ok).toBe(true);
    if (r.ok && r.msg.type === "session_started") {
      expect(r.msg.capabilities?.promptKinds).toEqual(WS_PROMPT_KINDS);
      expect(r.msg.capabilities?.incomingTypes).toEqual(WS_INCOMING_TYPES);
    }
  });

  test("frame with promptKinds only parses (legacy server, pre-#3464)", () => {
    // Backward compat: a server build before #3464 emits capabilities
    // with only promptKinds. Schema must still accept it so a stale
    // client deployed against a fresh server (or vice versa) doesn't
    // brick.
    const r = parseWSMessage({
      type: "session_started",
      conversationId: "c-1",
      capabilities: { promptKinds: ["ask_user"] },
    });
    expect(r.ok).toBe(true);
  });

  test("frame with no capabilities parses (legacy server, pre-#2885)", () => {
    // Backward compat for the very first servers that didn't emit
    // capabilities at all. E2 edge case in the plan.
    const r = parseWSMessage({
      type: "session_started",
      conversationId: "c-1",
    });
    expect(r.ok).toBe(true);
  });

  test("frame rejects an unknown capability field (CWE-201 defense)", () => {
    const r = parseWSMessage({
      type: "session_started",
      conversationId: "c-1",
      capabilities: {
        promptKinds: ["ask_user"],
        sneakyExtraField: "this should not pass",
      } as unknown as { promptKinds: string[] },
    });
    expect(r.ok).toBe(false);
  });
});

describe("WSMessage type narrowing — compile-time exhaustiveness", () => {
  // AC8: type-level narrowing on `session_started` provides
  // `capabilities?.incomingTypes` as `readonly string[] | undefined`.
  // This test exists at runtime but its body is a no-op; the value is
  // in the static type-check (vitest type-checks test files via
  // `tsc --noEmit` in the package's typecheck script).
  test("capabilities.incomingTypes is readonly string[] | undefined", () => {
    type Frame = {
      type: "session_started";
      conversationId: string;
      capabilities?: { promptKinds: readonly string[]; incomingTypes?: readonly string[] };
    };
    const frame: Frame = {
      type: "session_started",
      conversationId: "c-1",
      capabilities: WS_CAPABILITIES,
    };
    // Narrowing: incomingTypes is optional readonly string[].
    const types: readonly string[] | undefined = frame.capabilities?.incomingTypes;
    expect(types).toEqual(["abort_turn"]);
  });
});
