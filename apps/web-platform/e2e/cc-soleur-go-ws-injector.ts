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

export interface WsInjector {
  /** Resolves once the page has opened the intercepted `/ws` connection. */
  ready: Promise<void>;
  /** Push a `StreamEvent` to the page as if the server emitted it. */
  send: (event: StreamEvent) => void;
}

export async function attachWsInjector(page: Page): Promise<WsInjector> {
  let routeRef: WebSocketRoute | undefined;
  let readyResolve: () => void;
  const ready = new Promise<void>((resolve) => {
    readyResolve = resolve;
  });

  await page.routeWebSocket("**/ws", (ws) => {
    routeRef = ws;
    readyResolve();
  });

  return {
    ready,
    send: (event: StreamEvent) => {
      if (!routeRef) {
        throw new Error(
          "WS route not yet established — await injector.ready before send()",
        );
      }
      routeRef.send(JSON.stringify(event));
    },
  };
}
