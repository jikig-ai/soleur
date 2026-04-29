// Workaround for the Node-without-native-WebSocket path in
// @supabase/realtime-js (originally tracked as supabase/supabase-js#1559).
//
// On Node <22 with no `globalThis.WebSocket`, realtime-js's WebSocket factory
// returns `{ type: 'unsupported' }` and the connect path errors out — surfacing
// to callers as a 10s `phx_join` timeout followed by `CLOSED`. Setting
// `globalThis.WebSocket` BEFORE createClient() forces the factory into its
// `type: 'native'` branch (same path the browser native WebSocket takes), so
// the client subscribes deterministically.
//
// No-op when WebSocket is already defined (browsers, jsdom, Node 22+ behind
// `--experimental-websocket`). Idempotent so multiple test files / beforeAll
// hooks can call it without conflict.
import WS from "ws";

export function ensureNodeWebSocketPolyfill(): void {
  if (typeof globalThis.WebSocket === "undefined") {
    (globalThis as { WebSocket?: unknown }).WebSocket = WS;
  }
}
