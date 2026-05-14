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

/** Control frames the page expects from the server but that live outside the
 *  reducer-visible `StreamEvent` subset (`chat-state-machine.ts:244`).
 *  `session_started` is the only one PR-A tests need; widen this if PR-B/PR-C
 *  inject more control frames. */
export type WsControlEvent = {
  type: "session_started";
  conversationId: string;
  capabilities?: { promptKinds: readonly string[]; incomingTypes?: readonly string[] };
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
