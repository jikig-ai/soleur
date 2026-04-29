// Workaround for supabase/supabase-js#1559 — Node.js race condition where the
// ws-fallback constructor inside @supabase/realtime-js loses the `phx_reply`
// frame before the response handlers are attached, surfacing as a 10s
// `TIMED_OUT` followed by `CLOSED`. Polyfilling globalThis.WebSocket BEFORE
// createClient() eliminates the racy fallback path entirely — the client uses
// the polyfilled global the same way it uses the native browser WebSocket.
//
// No-op when WebSocket is already defined (browsers, jsdom). Idempotent so
// multiple test files / beforeAll hooks can call it without conflict.
import WS from "ws";

export function ensureNodeWebSocketPolyfill(): void {
  if (typeof globalThis.WebSocket === "undefined") {
    (globalThis as unknown as { WebSocket: typeof globalThis.WebSocket })
      .WebSocket = WS as unknown as typeof globalThis.WebSocket;
  }
}
