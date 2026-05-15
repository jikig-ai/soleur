// PR-A (#2939) Stage 6 smoke regression net.
//
// Intercepts the cc-soleur-go WebSocket at `**/ws` (path verified against
// lib/ws-client.ts:496 — `${proto}://${window.location.host}/ws`) and lets
// tests inject `StreamEvent` frames as if they came from the server.
//
// We do NOT call `connectToServer()` — the Playwright `authenticated`
// project boots a real Next.js dev server, but its `/ws` handler tries to
// authenticate against the mocked Supabase which won't honor real socket
// upgrades. Full intercept keeps the test surface hermetic.

import type { Page, WebSocketRoute } from "@playwright/test";
import type { StreamEvent } from "@/lib/chat-state-machine";
import type { WSErrorCode } from "@/lib/types";

/** Control frames the page expects from the server but that live outside the
 *  reducer-visible `StreamEvent` subset (`chat-state-machine.ts:244`).
 *  `session_started` (PR-A) lets the WS hook resolve a session before the
 *  reducer accepts follow-up events. `usage_update` (PR-B #3774) is handled
 *  by an out-of-reducer `setUsageData` setState in `ws-client.ts:791-806`;
 *  threaded into the lifecycle bar via a chat-surface prop merge. `error`
 *  (PR-C #2939) is handled in `ws-client.ts:655-700` via `setLastError`,
 *  out-of-reducer; required by FR3.4 rate-limit smoke. Widen this union
 *  when a future test needs another out-of-reducer frame. */
export type WsControlEvent =
  | {
      type: "session_started";
      conversationId: string;
      capabilities?: { promptKinds: readonly string[]; incomingTypes?: readonly string[] };
    }
  | {
      type: "usage_update";
      conversationId: string;
      totalCostUsd: number;
      inputTokens: number;
      outputTokens: number;
      cacheReadInputTokens?: number;
      cacheCreationInputTokens?: number;
    }
  | {
      type: "error";
      message: string;
      errorCode?: WSErrorCode;
      gateId?: string;
      // Shape mirrors lib/types.ts:303-316 — fields optional, FR3.4 only
      // needs `errorCode: "rate_limited"`. Carrying the full optional set
      // keeps the union forward-compatible with runner-runaway diagnostics.
      runnerRunawayReason?: "idle_window" | "max_turn_duration";
      runnerRunawayLastBlockKind?: "text" | "tool_use" | null;
      runnerRunawayLastBlockToolName?: string | null;
    };

export interface WsInjector {
  /** Resolves once the page has opened the intercepted `/ws` connection. */
  ready: Promise<void>;
  /** Push a reducer-visible `StreamEvent` to the page as if the server emitted it. */
  send: (event: StreamEvent) => void;
  /** Push a non-reducer control frame (e.g. `session_started`). Keeps the typed
   *  `send` boundary tight while still letting tests drive the lifecycle. */
  sendControl: (event: WsControlEvent) => void;
  /** Uncaught page errors captured since `attachWsInjector` was called. Owned
   *  by the injector so tests don't have to smuggle an array onto the object. */
  readonly pageErrors: readonly Error[];
}

export async function attachWsInjector(page: Page): Promise<WsInjector> {
  let routeRef: WebSocketRoute | undefined;
  let readyResolve: () => void = () => {};
  const ready = new Promise<void>((resolve) => {
    readyResolve = resolve;
  });

  const pageErrors: Error[] = [];
  page.on("pageerror", (err) => pageErrors.push(err));

  await page.routeWebSocket("**/ws", (ws) => {
    routeRef = ws;
    readyResolve();
  });

  const sendRaw = (frame: StreamEvent | WsControlEvent) => {
    if (!routeRef) {
      throw new Error(
        "WS route not yet established — await injector.ready before send()",
      );
    }
    routeRef.send(JSON.stringify(frame));
  };

  return {
    ready,
    send: (event: StreamEvent) => sendRaw(event),
    sendControl: (event: WsControlEvent) => sendRaw(event),
    get pageErrors() {
      return pageErrors;
    },
  };
}
