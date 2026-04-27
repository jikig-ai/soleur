import { vi } from "vitest";
import type { useWebSocket } from "@/lib/ws-client";

type WebSocketState = ReturnType<typeof useWebSocket>;

/**
 * Shared factory for mocking `useWebSocket` across chat-sidebar tests.
 *
 * Mirrors `test/mocks/use-team-names.ts`. Drift-resistant via both the
 * `ReturnType<typeof useWebSocket>` return-type annotation AND a `satisfies`
 * check on the base literal: a field addition to the hook fails compile here,
 * not at N test-runtime errors across 7 consumers.
 *
 * Usage:
 *
 *   import { createWebSocketMock } from "./mocks/use-websocket";
 *
 *   let wsReturn = createWebSocketMock();
 *   vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }));
 *
 *   // Per-test override:
 *   wsReturn = createWebSocketMock({ status: "connecting" });
 */
export function createWebSocketMock(
  overrides: Partial<WebSocketState> = {},
): WebSocketState {
  const base = {
    messages: [],
    startSession: vi.fn(),
    resumeSession: vi.fn(),
    sendMessage: vi.fn(),
    sendReviewGateResponse: vi.fn(),
    sendInteractivePromptResponse: vi.fn(),
    resolveInteractivePrompt: vi.fn(),
    status: "connected",
    sessionConfirmed: true,
    disconnectReason: undefined,
    lastError: null,
    reconnect: vi.fn(),
    routeSource: null,
    activeLeaderIds: [],
    usageData: null,
    realConversationId: null,
    resumedFrom: null,
    workflow: { state: "idle" } as const,
  } satisfies WebSocketState;
  return { ...base, ...overrides };
}
