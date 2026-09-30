import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  createMockQueryScripted as createMockQuery,
  makeAssistant,
  makeResult,
  makeRecordingEvents,
  flushMicrotasks,
} from "./helpers/soleur-go-fixtures";

// Mock observability BEFORE importing the runner so `warnSilentFallback` resolves
// to the spy (cq-silent-fallback-must-mirror-to-sentry).
const { mockWarnSilentFallback } = vi.hoisted(() => ({
  mockWarnSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: mockWarnSilentFallback,
  mirrorWithDebounce: vi.fn(),
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

import { createSoleurGoRunner } from "@/server/soleur-go-runner";

// Incident replay: the Concierge composed a CRM question list, then the operator
// Stop hook drove a second assistant message that was ONLY the stop tag, which
// replaced the list in the chat bubble (text is replaced per block, W8).
const QUESTION_LIST =
  "To enter the lead I need:\n- **lastContact**\n- **amount**, with **currency**\n- **expectedCloseDate**\n\nPaste everything in one message.";
const STOP_TAG =
  "<stop>OPERATOR-GATE: I need the lead's details (at minimum a name) from you. The review and save happen only after you send them, so there is nothing more I can do yet.</stop>";

async function replay(blocks: string[]) {
  const mock = createMockQuery();
  const runner = createSoleurGoRunner({ queryFactory: () => mock.query });
  const texts: string[] = [];
  let turnEnds = 0;
  const events = {
    ...makeRecordingEvents(),
    onText: (t: string) => {
      texts.push(t);
    },
    onTextTurnEnd: () => {
      turnEnds += 1;
    },
  };
  await runner.dispatch({
    persona: "command_center",
    conversationId: "conv-stop-gate",
    userId: "u1",
    userMessage: "I want to enter a new CRM lead",
    currentRouting: { kind: "soleur_go_pending" },
    events,
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
  });
  for (const text of blocks) {
    mock.emit(makeAssistant({ content: [{ type: "text", text }] }));
    await flushMicrotasks();
  }
  mock.emit(makeResult(0.1887));
  await flushMicrotasks();
  return { texts, turnEnds };
}

describe("soleur-go-runner stop-gate markup boundary", () => {
  beforeEach(() => {
    mockWarnSilentFallback.mockClear();
  });

  it("incident: list then stop-tag-only block -> onText once with the list, never a <stop", async () => {
    const { texts, turnEnds } = await replay([QUESTION_LIST, STOP_TAG]);
    expect(texts).toEqual([QUESTION_LIST]);
    expect(texts.some((t) => t.includes("<stop"))).toBe(false);
    expect(turnEnds).toBe(1);
  });

  it("markup embedded in a prose block: onText receives the prose without the tag", async () => {
    const { texts } = await replay([`${QUESTION_LIST}\n\n${STOP_TAG}`]);
    expect(texts).toEqual([QUESTION_LIST]);
  });

  it("markup-only FIRST block: onText is not called (no empty bubble)", async () => {
    const { texts, turnEnds } = await replay([STOP_TAG]);
    expect(texts).toEqual([]);
    expect(turnEnds).toBe(1);
  });

  it("emits a body-free Sentry warning when markup is stripped", async () => {
    await replay([QUESTION_LIST, STOP_TAG]);
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = mockWarnSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({
      feature: "soleur-go-runner",
      op: "stop-gate-markup-stripped",
    });
    expect(Object.keys(opts.extra).sort()).toEqual(
      ["conversationId", "markupOnly", "strippedBytes"].sort(),
    );
    expect(opts.extra.markupOnly).toBe(true);
    expect(JSON.stringify(opts)).not.toContain("OPERATOR-GATE");
  });

  it("no markup: no Sentry warning, text passes through unchanged", async () => {
    const { texts } = await replay([QUESTION_LIST]);
    expect(texts).toEqual([QUESTION_LIST]);
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  it("accepted limit (negative control): a later PROSE block still replaces the list (W8)", async () => {
    const { texts } = await replay([QUESTION_LIST, "Different prose."]);
    expect(texts).toEqual([QUESTION_LIST, "Different prose."]);
  });
});
