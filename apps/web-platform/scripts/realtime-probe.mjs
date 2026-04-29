#!/usr/bin/env node
// Standalone reproducer + verification harness for issue #3052 (Phoenix JOIN
// handshake TIMED_OUT from local shell). Default mode (with polyfill) applies
// the documented workaround for supabase/supabase-js#1559 — set
// globalThis.WebSocket from the `ws` module BEFORE createClient. Diagnostic
// mode (--no-polyfill) skips the polyfill so operators can reproduce the
// underlying race for the learning-file baseline.
//
// Usage:
//   doppler run -p soleur -c dev -- node ./scripts/realtime-probe.mjs
//   doppler run -p soleur -c dev -- node ./scripts/realtime-probe.mjs --no-polyfill
//
// Exits 0 on SUBSCRIBED, 1 on CLOSED/CHANNEL_ERROR/TIMED_OUT, 2 on missing
// env, 3 on hard 30s timeout.

import WS from "ws";

const NO_POLYFILL = process.argv.includes("--no-polyfill");

if (!NO_POLYFILL && typeof globalThis.WebSocket === "undefined") {
  globalThis.WebSocket = WS;
  console.log("[probe] polyfill: applied (globalThis.WebSocket = ws)");
} else if (NO_POLYFILL) {
  console.log("[probe] polyfill: skipped (--no-polyfill, expect TIMED_OUT)");
} else {
  console.log("[probe] polyfill: not needed (native WebSocket present)");
}

const { createClient } = await import("@supabase/supabase-js");

const url = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const key =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
if (!url || !key) {
  console.error(
    "[probe] Set SUPABASE_URL + SUPABASE_ANON_KEY (or NEXT_PUBLIC_ variants).",
  );
  process.exit(2);
}

const client = createClient(url, key);
const channel = client.channel(`probe-${Date.now()}`);
const t0 = Date.now();

let resolved = false;
const finish = (code) => {
  if (resolved) return;
  resolved = true;
  client.removeAllChannels().then(() => process.exit(code));
};

channel.subscribe((status, err) => {
  const elapsed = Date.now() - t0;
  console.log(`[probe ${elapsed}ms]`, status, err ? `err=${err.message}` : "");
  if (status === "SUBSCRIBED") finish(0);
  else if (
    status === "CHANNEL_ERROR" ||
    status === "TIMED_OUT" ||
    status === "CLOSED"
  )
    finish(1);
});

setTimeout(() => {
  console.error("[probe] hard timeout after 30s");
  process.exit(3);
}, 30_000);
