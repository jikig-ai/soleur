// session-proxy.ts — the b2 transparent host↔host WS relay (epic #5274 Phase 3
// Sub-PR 3.B, ADR-068 amendment 2026-07-01, CTO ruling b2).
//
// Under user-sticky routing a WS session that lands on a NON-owning web host is
// transparently relayed to the host holding that user's worktree lease, with NO
// client-visible reconnect (the fly-replay invariant: never upgrade-then-REDIRECT).
// The relay is one-way TLS over the private net: the OWNER runs a wss server
// presenting the 3.A self-signed cert; the PROXYING host dials it pinning that
// same cert as its CA (rejectUnauthorized:true, NEVER false — proxy-tls.ts).
//
// Wire format on the private-net leg (JSON control frame, then a raw bidirectional
// byte pipe):
//   proxying host → owner : {type:"proxy_hello", userId, workspaceId, ts, nonce, mac} — HMAC-signed
//                           under PROXY_HELLO_HMAC_KEY (proxy-hello.ts; #12289, ADR-323)
//   owner → proxying host : {type:"proxy_ready"}  (after size/shape/MAC/skew/replay AND AP-2 membership)
//                         | close(ROUTING_UNAVAILABLE, "relay refused") (any verifier refusal; one uniform reason,
//                           then terminate() after REFUSE_LINGER_MS). The hello deadline and the pre-hello byte guard
//                           drop the socket without a close frame (abnormal close, 1006); a protocol error is terminated
//                           right after `ws` queues its own close frame (1002/1007/1009).
// After proxy_ready the two sockets are piped verbatim in BOTH directions,
// including close frames + codes (a drain close from the owner reaches the client;
// a client close tears down the owner leg) so grace-abort host-locality stays
// correct (#2191 overlap).
//
// INERT until 3.D: at a single host every route resolves `local`, so
// proxyClientToOwner is never called and the owner's proxy listener has no peers.

import { WebSocket, WebSocketServer } from "ws";
import { createServer, type Server as HttpsServer } from "node:https";
import { isIP, isIPv4, type Socket } from "node:net";
import type { IncomingMessage } from "node:http";
import { WS_CLOSE_CODES } from "@/lib/types";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";
import { loadProxyHelloKeys, loadProxyTlsClientCa, loadProxyTlsServerOptions } from "./proxy-tls";
import { createReplayCache, isCanonicalUuid, signProxyHello, verifyProxyHello } from "./proxy-hello";
import { verifyProxiedSessionMembership } from "./session-router";
import { recordProxyNotStarted, recordProxyServer } from "./proxy-listener-status";
import { denyReporter } from "./proxy-deny-report";

const log = createChildLogger("session-proxy");

/** Default private-net TLS port the owner's proxy listener binds (distinct from the public app port);
 *  prod pins it to the literal 8443 in ci-deploy.sh. The proxying host dials
 *  `wss://<ownerAddress>:<port>`. */
export const DEFAULT_PROXY_PORT = 8443;

/**
 * Strict parse of `SOLEUR_PROXY_PORT` (#12290), evaluated at call time (never a module-load constant that
 * could re-enter as `NaN`): unset or empty is the default; otherwise 1-5 ASCII digits in 1..65535, nothing
 * else. `Number()` would accept "0x20fb", "1e3" and " 8443 ", and `listen(NaN | 70000)` throws
 * ERR_SOCKET_BAD_PORT out of createProxyServer into index.ts (a restart loop for a relay-only fault).
 * Returns null for an invalid value.
 */
export function resolveProxyPort(raw: string | undefined = process.env.SOLEUR_PROXY_PORT): number | null {
  if (raw === undefined || raw === "") return DEFAULT_PROXY_PORT;
  if (!/^[0-9]{1,5}$/.test(raw)) return null;
  const n = Number(raw);
  return n >= 1 && n <= 65535 ? n : null;
}

/** A port handed in by a caller: an integer in range. `allowEphemeral` admits 0 (the owner's test seam). */
function isUsablePort(p: unknown, allowEphemeral: boolean): p is number {
  return typeof p === "number" && Number.isInteger(p) && p >= (allowEphemeral ? 0 : 1) && p <= 65535;
}

/** The single close reason for every owner-side refusal after the upgrade (never says which check failed). */
const RELAY_REFUSED = "relay refused";

/** Hello deadline (CTO ruling 2026-11-09, reversing the earlier "no timer" ruling): an allowlisted peer that
 *  has not produced a message this long after it was admitted is closed. The serve-gate probe holds a
 *  hello-less upgrade ~700 ms to read `ok`, so 10 s is compatible with it. */
export const HELLO_DEADLINE_MS = 10_000;

/** Cumulative bytes an admitted peer may send on the upgraded socket before its FIRST MESSAGE ARRIVES (not
 *  until one is accepted: a refusal ends in `refuse()`): the 1 KiB hello cap plus the WebSocket frame header
 *  and slack. The bound is this plus the read chunk that completes the first frame. `ws` buffers a whole
 *  first frame (default maxPayload 100 MiB), so this is what bounds pre-authentication memory. */
export const PRE_HELLO_MAX_BYTES = 2048;

/** After a verifier refusal the close frame goes out and the socket is terminated this long after: `ws`
 *  would otherwise keep reading a peer that ignores the close frame for up to 30 s, up to its 100 MiB
 *  maxPayload per frame. Long enough for the 4014 frame to reach a legitimate sender. */
export const REFUSE_LINGER_MS = 250;

/** Authenticated context a proxied connection carries once AP-2 passes — the
 *  owner attaches a PRE-authenticated session from this (no token re-auth; the
 *  proxying host already authenticated, and AP-2 re-verifies membership). */
export interface ProxiedSessionContext {
  userId: string;
  workspaceId: string;
}

// --- Proxying-host side ------------------------------------------------------

/**
 * Relay an already-authenticated CLIENT socket to its OWNER over one-way TLS.
 * Sends the proxy_hello, waits for proxy_ready (AP-2 passed on the owner), then
 * pipes frames + close both ways. On any setup failure (owner down, TLS reject,
 * AP-2 deny) the client socket is closed non-transiently so it reconnects (and is
 * re-routed). Never throws — the caller has already committed the client socket.
 *
 * `clientWs` is the `ws` server socket from the public connection. `dial` is
 * injected for testing (defaults to a real pinned-CA wss dial).
 */
export async function proxyClientToOwner(params: {
  clientWs: WebSocket;
  ownerAddress: string;
  userId: string;
  workspaceId: string;
  port?: number;
  dial?: (url: string, opts: { ca: string; rejectUnauthorized: true }) => WebSocket;
}): Promise<void> {
  const { clientWs, ownerAddress, userId, workspaceId } = params;
  const ca = loadProxyTlsClientCa();
  if (!ca) {
    denyReporter.record("no_ca");
    safeClose(clientWs, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "owner unreachable");
    return;
  }

  // The hello is signed with the dedicated hello key. Without a valid key, or with ids that are not
  // canonical UUIDs, there is nothing the owner could accept: close the client and never dial (like the CA
  // case). 4014 is a TRANSIENT code to the client (lib/ws-client.ts retries with capped backoff and no
  // limit, no terminal state), so each refused session loops until the cause is fixed. Reported through
  // the bounded reporter, no key detail in the event.
  const helloKey = loadProxyHelloKeys().current;
  if (!helloKey) {
    denyReporter.record("no_key");
    safeClose(clientWs, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "owner unreachable");
    return;
  }
  if (!isCanonicalUuid(userId) || !isCanonicalUuid(workspaceId)) {
    denyReporter.record("bad_ids");
    safeClose(clientWs, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "owner unreachable");
    return;
  }

  const port = params.port === undefined ? resolveProxyPort() : isUsablePort(params.port, false) ? params.port : null;
  if (port === null) {
    denyReporter.record("bad_port");
    safeClose(clientWs, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "owner unreachable");
    return;
  }

  const url = `wss://${ownerAddress}:${port}/ws-proxy`;
  // Pinned CA + rejectUnauthorized TRUE — never disable verification.
  const owner = params.dial
    ? params.dial(url, { ca, rejectUnauthorized: true })
    : new WebSocket(url, { ca, rejectUnauthorized: true });

  let ready = false;

  const teardown = (code: number, reason: string) => {
    safeClose(clientWs, code, reason);
    safeClose(owner, code, reason);
  };

  owner.on("open", () => {
    owner.send(signProxyHello(helloKey, userId, workspaceId));
  });

  owner.on("message", (data: unknown, isBinary?: boolean) => {
    if (!ready) {
      // First owner→proxy message is the control ack.
      try {
        const msg = JSON.parse(String(data)) as { type?: string };
        if (msg.type === "proxy_ready") {
          ready = true;
          return;
        }
      } catch {
        /* fall through to teardown */
      }
      teardown(WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "owner rejected proxied session");
      return;
    }
    // owner → client
    forward(clientWs, data, isBinary);
  });

  // client → owner (only once ready; pre-ready client frames are buffered by the
  // socket's own backpressure — the client sent auth first and waits for auth_ok,
  // which only arrives once the owner is serving).
  clientWs.on("message", (data: unknown, isBinary?: boolean) => {
    if (ready) forward(owner, data, isBinary);
  });

  // Close-frame forwarding BOTH ways (drain close from owner → client; client
  // close → owner leg). Preserve the code so the client's reconnect logic routes.
  owner.on("close", (code: number, reason: Buffer) => {
    // The owner's uniform refusal reason before proxy_ready: the sender-side view of a hello it refused.
    if (!ready && reason.toString() === RELAY_REFUSED) denyReporter.record("owner_refused");
    // An owner-side terminate()/destroy() (hello deadline, byte guard, crash) reads as 1006 here, which `ws`
    // cannot send: map it to the retryable 4014 so the browser reconnects instead of sitting on a dead socket.
    if (isSendableCloseCode(code)) safeClose(clientWs, code, reason.toString());
    else safeClose(clientWs, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "owner connection lost");
  });
  clientWs.on("close", (code: number, reason: Buffer) => safeClose(owner, code, reason.toString()));

  owner.on("error", (err: unknown) => {
    reportSilentFallback(err, {
      feature: "control_plane_route",
      op: "proxyClientToOwner.owner-socket-error",
      extra: { ownerAddress, userId: undefined, workspaceId },
    });
    teardown(WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "owner connection error");
  });
}

// --- Owning-host side --------------------------------------------------------

/**
 * Start the owner's private-net TLS proxy listener, or return null when the relay
 * cannot start: no TLS material (dev / single-host before 3.A delivers the cert —
 * the relay is then inert), no bind, no peer allowlist, no usable hello key, a bad
 * port, TLS setup failure, or a throwing `listen()` (each records `proxy_state`). Accepts a proxied connection, reads proxy_hello, runs
 * AP-2 membership re-verify (fail-closed), acks `proxy_ready`, then hands the
 * socket + context to `onProxiedSession` (which attaches a pre-authenticated
 * native session). Never re-authenticates a token — the proxying host already did,
 * and AP-2 re-verifies the membership boundary.
 */
/**
 * Strip an IPv4-mapped IPv6 prefix (`::ffff:10.0.1.20` → `10.0.1.20`) so a socket
 * peer address compares equal to the plain IPv4 the allowlist carries. Node reports
 * `remoteAddress` in v4-mapped form on dual-stack listeners.
 */
export function normalizeProxyPeerAddress(addr: string | undefined | null): string {
  if (!addr) return "";
  return addr.startsWith("::ffff:") ? addr.slice("::ffff:".length) : addr;
}

/** One predicate for both admission points (the pre-TLS `connection` listener and the in-`wss`
 *  re-check): a peer is admitted only when its normalized address is non-empty AND listed.
 *  A missing `remoteAddress` (socket already torn down) is a deny, never an allow. */
export function isAllowedProxyPeer(addr: string | undefined | null, allowlist: ReadonlySet<string>): boolean {
  const peer = normalizeProxyPeerAddress(addr);
  return peer !== "" && allowlist.has(peer);
}

/** The peer label a deny report carries: the kernel-supplied address when it has the shape of an IP
 *  literal, else a fixed token — never an arbitrary string. */
function peerLabel(addr: string | undefined | null): string {
  if (!addr) return "unknown";
  const peer = normalizeProxyPeerAddress(addr);
  return isIP(peer) !== 0 ? peer : "invalid";
}

/** Parse the comma-separated peer allowlist env into a Set of trimmed, non-empty IPs. */
export function parseProxyPeerAllowlist(csv: string | undefined | null): Set<string> {
  return new Set(
    (csv ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0),
  );
}

/** Private-net prefix a non-wildcard proxy bind must carry (the web hosts' 10.0.1.0/24). */
export const PROXY_PRIVATE_BIND_PREFIX = "10.0.1.";

/** Accept only an IPv4 literal that is exactly `0.0.0.0` or starts with the private prefix. */
export function isAllowedProxyBind(addr: string, prefix: string = PROXY_PRIVATE_BIND_PREFIX): boolean {
  return isIPv4(addr) && (addr === "0.0.0.0" || addr.startsWith(prefix));
}

export function createProxyServer(params: {
  onProxiedSession: (ws: WebSocket, ctx: ProxiedSessionContext) => void;
  port?: number;
  /** The bind address INSIDE the container's network namespace: an IPv4 literal that
   *  is exactly `0.0.0.0` (prod: the host's private IP is applied by
   *  `docker -p <private-ip>:8443:8443`, not by the app) or `10.0.1.x`. Anything else
   *  (unset, `::`, hostnames, IPv6, public IPs) refuses to start — this port carries a
   *  token-less pre-authenticated session (AP-2 verifies only a valid member PAIR, not
   *  the caller's right to act as that user), so a wrong bind would make network
   *  reachability the only control. Defaults to `SOLEUR_PROXY_BIND`. */
  bindAddress?: string;
  /** TEST-ONLY seam (a param, deliberately not an env var so a deployed container cannot
   *  set it): replaces the `10.0.1.` prefix so tests can bind loopback / TEST-NET.
   *  `net.isIPv4` is still enforced. index.ts never passes it. */
  privateBindPrefix?: string;
  /** TEST-ONLY seam, honoured solely under vitest (like `privateBindPrefix`): replaces HELLO_DEADLINE_MS. */
  helloDeadlineMs?: number;
}): HttpsServer | null {
  const tls = loadProxyTlsServerOptions();
  if (!tls) {
    recordProxyNotStarted("disabled");
    log.info("session-proxy: no PROXY_TLS material — owner proxy listener disabled (single-host/dev)");
    return null;
  }
  const bindAddress = params.bindAddress ?? process.env.SOLEUR_PROXY_BIND?.trim();
  if (!bindAddress) {
    recordProxyNotStarted("no_bind");
    // Fail-closed: without an explicit private-net bind we would default to
    // 0.0.0.0 and expose a token-less session port behind only the firewall.
    reportSilentFallback(
      new Error(
        "SOLEUR_PROXY_BIND unset — refusing to start the owner proxy listener on all " +
          "interfaces (a token-less pre-authenticated session port must bind the private net only)",
      ),
      { feature: "control_plane_route", op: "createProxyServer.no-bind" },
    );
    return null;
  }
  // The prefix override is a TEST seam only: honoured solely under vitest (VITEST is set by the
  // runner and never in a production container), so no production call site can lift the
  // private-net restriction on this token-less pre-authenticated port by passing "".
  const bindPrefix = process.env.VITEST ? (params.privateBindPrefix ?? PROXY_PRIVATE_BIND_PREFIX) : PROXY_PRIVATE_BIND_PREFIX;
  if (!isAllowedProxyBind(bindAddress, bindPrefix)) {
    recordProxyNotStarted("no_bind");
    // Fail-closed on a wildcard IPv6 (`::`), a hostname, a public or other-subnet IP.
    // The value is operator config (not secret) but is kept out of the message anyway.
    reportSilentFallback(
      new Error(
        `SOLEUR_PROXY_BIND is not an IPv4 literal of 0.0.0.0 or ${bindPrefix}x — refusing to start ` +
          "the owner proxy listener (a token-less pre-authenticated session port)",
      ),
      { feature: "control_plane_route", op: "createProxyServer.bad-bind" },
    );
    return null;
  }
  // Peer-origin allowlist (3.D, CTO ruling). One-way TLS + a token-less handshake
  // means network reachability is the only control, and Hetzner cloud firewalls do
  // NOT filter the private net (git-data.tf, resource "hcloud_firewall" "git_data" — no rule blocks) — so any 10.0.1.0/24 host,
  // INCLUDING the deliberately-lesser-privileged git-data host, could open this port
  // and take over any account (attachProxiedSession registers a full act-as-user
  // session). The infra firewall cannot scope 8443; this guest-side allowlist is the
  // load-bearing control. Fail-closed like the bind guard: TLS material present but
  // no allowlist ⇒ refuse to start (never serve an unrestricted takeover port).
  const peerAllowlist = parseProxyPeerAllowlist(process.env.SOLEUR_PROXY_PEER_ALLOWLIST);
  if (peerAllowlist.size === 0) {
    recordProxyNotStarted("no_allowlist");
    reportSilentFallback(
      new Error(
        "SOLEUR_PROXY_PEER_ALLOWLIST unset/empty — refusing to start the owner proxy " +
          "listener: a token-less pre-authed session port must restrict its private-net " +
          "source to known web-host peers (any other private-net host could take over accounts)",
      ),
      { feature: "control_plane_route", op: "createProxyServer.no-peer-allowlist" },
    );
    return null;
  }

  // Hello-signing key (#12289). Placed AFTER the tls/bind/allowlist checks so `disabled`, `no_bind` and
  // `no_allowlist` keep their meaning (a dev/CI box without TLS is `disabled`, never an error). With relay
  // TLS enabled and no usable key the relay stays down and reports `error`; the app keeps serving. The
  // canary does NOT catch this (it runs with an empty SOLEUR_PROXY_BIND, so it stops at `no_bind` first,
  // and ci-deploy.sh never gates on proxy_state): the signals are this event and the `relay_listener_down`
  // alert about 5 minutes later. The event text is a constant: no value, length or state.
  const helloKey = loadProxyHelloKeys().current;
  if (!helloKey) {
    recordProxyNotStarted("error");
    reportSilentFallback(null, {
      feature: "control_plane_route",
      op: "createProxyServer.no-hello-key",
      message: "PROXY_HELLO_HMAC_KEY missing or malformed — refusing to start the owner proxy listener",
    });
    return null;
  }
  const replayCache = createReplayCache();

  // #12290: a bad port stops only the relay. Checked after the key guard so every earlier state keeps its
  // meaning; the event carries no value.
  const port = params.port === undefined ? resolveProxyPort() : isUsablePort(params.port, true) ? params.port : null;
  if (port === null) {
    recordProxyNotStarted("error");
    reportSilentFallback(null, {
      feature: "control_plane_route",
      op: "createProxyServer.bad-port",
      message: "SOLEUR_PROXY_PORT is not a valid port — refusing to start the owner proxy listener",
    });
    return null;
  }
  // Everything that can throw synchronously on bad TLS material (an unparseable or
  // mismatched PEM throws ERR_OSSL_* out of https.createServer) is fenced: an unhandled
  // throw here would reach index.ts un-caught and restart-loop the WHOLE app for a
  // relay-only fault. Only the error CODE is reported, never the message (which can echo
  // OpenSSL detail) or any PEM byte.
  let httpsServer: HttpsServer;
  let wss: WebSocketServer;
  try {
    httpsServer = createServer({ key: tls.key, cert: tls.cert });
    try {
      // perMessageDeflate off and allowSynchronousEvents on are load-bearing for the pre-hello byte guard
      // (see `cutOff` below): pinned explicitly so a `ws` default change cannot move them.
      wss = new WebSocketServer({ server: httpsServer, path: "/ws-proxy", perMessageDeflate: false, allowSynchronousEvents: true });
    } catch (wssErr) {
      httpsServer.close(); // never listened; releases the parsed key/cert context
      throw wssErr;
    }
  } catch (err) {
    const rawCode = (err as NodeJS.ErrnoException | undefined)?.code;
    const code = typeof rawCode === "string" && /^[A-Z0-9_]{1,64}$/.test(rawCode) ? rawCode : undefined;
    recordProxyNotStarted("error");
    reportSilentFallback(new Error(`proxy TLS server setup failed (${code ?? "unknown"})`), {
      feature: "control_plane_route",
      op: "createProxyServer.tls-setup",
      message: "owner proxy listener TLS setup failed; relay not serving on this host",
      extra: { code },
    });
    return null;
  }

  // #12288 — admit a peer on the raw TCP stream BEFORE Node's TLS wrapper reads a byte. The https server
  // is a tls.Server, so its own `connection` listener starts the handshake; this listener is PREPENDED
  // (named, so a structural test can assert it is first) and destroys a non-allowlisted source before that
  // listener runs. A missing `remoteAddress` is a deny. A destroyed socket still reaches Node's wrapper
  // (one `tlsClientError` per deny, measured on Node 26; the admission test pins `secureConnection` = 0 on
  // the CI Node); the destroy comes FIRST so a fault in reporting can never leave a denied socket alive.
  //
  // HELLO DEADLINE (CTO ruling 2026-11-09, reversing "no timer"): an admitted peer that produces no message
  // within HELLO_DEADLINE_MS of admission is destroyed, covering the TLS handshake, the upgrade and the idle
  // wait. PROBE CONTRACT (ci-deploy.sh RELAY_PROBE_JS): the serve-gate probe holds a hello-less upgrade
  // ~700 ms to read `ok`, so the deadline must stay well above that. The timer is unref'd and keyed by the
  // peer's address:port because the TLS wrapper's socket is a different object from this raw one.
  // Residual (ADR-323): a non-allowlisted source now reads `relay_peer_probe result=tls` (reset before
  // secureConnect) and `denied` is unreachable from the probe.
  const deadlineMs = process.env.VITEST ? (params.helloDeadlineMs ?? HELLO_DEADLINE_MS) : HELLO_DEADLINE_MS;
  const helloDeadlines = new Map<string, NodeJS.Timeout>();
  const peerKey = (a: string | undefined, port: number | undefined) => `${a}:${port}`;
  const clearDeadline = (key: string) => {
    const t = helloDeadlines.get(key);
    if (t) clearTimeout(t);
    helloDeadlines.delete(key);
  };
  httpsServer.prependListener("connection", function admitProxyPeer(socket: Socket) {
    // Read once: a destroyed socket reports `remoteAddress` as undefined.
    const remote = socket.remoteAddress;
    const remotePort = socket.remotePort;
    if (!isAllowedProxyPeer(remote, peerAllowlist)) {
      socket.destroy();
      denyReporter.record("peer", { peer: peerLabel(remote) });
      return;
    }
    const key = peerKey(remote, remotePort);
    const timer = setTimeout(() => {
      if (helloDeadlines.get(key) === timer) helloDeadlines.delete(key);
      socket.destroy();
      denyReporter.record("hello_timeout", { peer: peerLabel(remote) });
    }, deadlineMs);
    timer.unref();
    clearDeadline(key); // a reused key must never orphan a live timer
    helloDeadlines.set(key, timer);
    socket.once("close", () => {
      if (helloDeadlines.get(key) === timer) clearDeadline(key); // never clear a newer connection's timer
    });
  });

  wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
    // A protocol violation (bad RSV bits, invalid UTF-8, an oversized declared length) makes `ws` emit
    // 'error' on this socket; with no listener that is an uncaught exception, and installCrashHandlers turns
    // it into process.exit(1) — one malformed frame from an allowlisted peer that holds no key would drop
    // every session on the host. Terminate and count it instead. Registered FIRST.
    const peer = peerLabel(req.socket.remoteAddress);
    const deadlineKey = peerKey(req.socket.remoteAddress, req.socket.remotePort);
    let accepted = false;
    ws.on("error", () => {
      clearDeadline(deadlineKey);
      // After proxy_ready a protocol error belongs to the relayed session, not to the hello: do not count it
      // as a hello refusal (it would inflate relay_hello_window denied and the `shape` bucket).
      if (!accepted && !refusedSockets.has(ws)) denyReporter.record("shape", { peer });
      ws.terminate();
    });
    // Defence in depth: the same predicate again after TLS + upgrade (no input reaches here with a
    // denied peer while the pre-TLS listener is first).
    if (!isAllowedProxyPeer(req.socket.remoteAddress, peerAllowlist)) {
      denyReporter.record("peer", { peer });
      refuse(ws);
      return;
    }
    // Pre-authentication bound (CTO ruling 2026-11-09): count bytes on the UPGRADED socket until the first
    // message is accepted, and terminate past PRE_HELLO_MAX_BYTES. The server-wide maxPayload cannot be
    // lowered because the same socket carries relayed session frames after proxy_ready. Counting here, on
    // req.socket, excludes the TLS handshake bytes a raw-socket count would include.
    let preHelloBytes = 0;
    let cutOff = false;
    let handled = false;
    const onPreHelloData = (chunk: Buffer) => {
      preHelloBytes += chunk.length;
      // `ws` registered its own data listener first, so for the chunk that carries the first frame the
      // message handler below has already run (and an emit iterates a snapshot of its listeners, so
      // removing this one there does not stop this call): do not count the same frame twice.
      if (preHelloBytes > PRE_HELLO_MAX_BYTES && !cutOff && !handled) {
        cutOff = true;
        req.socket.off("data", onPreHelloData);
        clearDeadline(deadlineKey);
        denyReporter.record("size", { peer });
        ws.terminate();
      }
    };
    req.socket.on("data", onPreHelloData);
    ws.once("close", () => req.socket.off("data", onPreHelloData));

    // First frame MUST be a signed proxy_hello; anything else → reject. Check order (CTO ruling,
    // ADR-323): allowlist (already passed pre-TLS) → 1 KiB cap → shape → MAC (constant time) → ts →
    // replay → AP-2 membership. The replay check-and-insert is SYNCHRONOUS and runs before the `await`
    // below, so two hellos with one nonce in the same tick cannot both pass. Every refusal closes with
    // the same reason, so a peer learns nothing about which check failed.
    ws.once("message", async (data: unknown, isBinary?: boolean) => {
      // Guard for two `ws` options pinned above (perMessageDeflate off, allowSynchronousEvents on): with them,
      // `ws` has already emitted the frame-completing chunk's message from its own data listener (which runs
      // before ours), so the guard sees `handled` and this line never runs with `cutOff` set. Without them
      // (async inflate, deferred emit) the message could arrive after the cut-off and be counted twice.
      if (cutOff) return;
      handled = true;
      req.socket.off("data", onPreHelloData);
      clearDeadline(deadlineKey);
      try {
        const verdict = verifyProxyHello(data, Boolean(isBinary), helloKey, replayCache);
        if (!verdict.ok) {
          denyReporter.record(verdict.reason, { peer });
          refuse(ws);
          return;
        }
        const { userId, workspaceId } = verdict;
        // AP-2: the OWNER re-verifies membership before serving a proxied session.
        const ok = await verifyProxiedSessionMembership(userId, workspaceId, createServiceClient());
        if (!ok) {
          // The pair is MAC-authenticated at this point, so it may ride the event (unauthenticated classes never do).
          denyReporter.record("membership", { peer, userId, workspaceId });
          refuse(ws);
          return;
        }
        // The proxying host may have dropped the client during the lookup: do not supersede the user's
        // live session on this host for a socket that is already gone.
        if (ws.readyState !== WebSocket.OPEN) return;
        denyReporter.recordAccepted();
        ws.send(JSON.stringify({ type: "proxy_ready" }));
        accepted = true; // only once proxy_ready is on the wire
        params.onProxiedSession(ws, { userId, workspaceId });
      } catch (err) {
        // An async handler's throw is an unhandledRejection -> process.exit(1). Fail closed instead. Only the
        // error CLASS is recorded (never the message): that is what tells a missing service-role env from a
        // throwing session attach.
        denyReporter.record("internal", { peer, errName: err instanceof Error ? err.name : typeof err });
        refuse(ws);
      }
    });
  });

  // A listen failure (EADDRNOTAVAIL when the private IP is not on this host yet,
  // EADDRINUSE on a stale listener) is emitted as 'error' on the https server, and
  // `ws` re-emits the server's 'error' on the WebSocketServer — which throws if the
  // wss has no listener. Either would reach installCrashHandlers -> process.exit(1)
  // -> a restart loop of the WHOLE app for a relay-only fault. Handle both here: the
  // relay is then simply not bound (proxy-listener-status derives `error` from
  // `server.listening`), the fault is mirrored, and the host keeps serving locally.
  const onListenError = (err: NodeJS.ErrnoException) => {
    reportSilentFallback(err, {
      feature: "control_plane_route",
      op: "createProxyServer.listen-error",
      message: "owner proxy listener failed to bind; relay not serving on this host",
      extra: { code: err.code, bindAddress, port },
    });
  };
  httpsServer.on("error", onListenError);
  wss.on("error", onListenError);
  recordProxyServer(httpsServer);

  // Bind the PRIVATE address only: `listen(port, cb)` would bind the wildcard (`::`),
  // exposing a token-less pre-authenticated session port beyond the private net.
  // `listen()` can still throw synchronously (ERR_SOCKET_BAD_PORT, ERR_INVALID_ARG_*), which would reach
  // index.ts un-caught and restart-loop the whole app. Fence it: close the never-listening server, report
  // the error CODE only, and leave the relay down with proxy_state=error.
  try {
    httpsServer.listen(port, bindAddress, () =>
      log.info({ port, bindAddress }, "session-proxy: owner proxy listener started (one-way TLS)"),
    );
  } catch (err) {
    const rawCode = (err as NodeJS.ErrnoException | undefined)?.code;
    const code = typeof rawCode === "string" && /^[A-Z0-9_]{1,64}$/.test(rawCode) ? rawCode : undefined;
    try {
      httpsServer.close();
    } catch {
      /* never listened */
    }
    recordProxyNotStarted("error");
    reportSilentFallback(null, {
      feature: "control_plane_route",
      op: "createProxyServer.listen-throw",
      message: "owner proxy listener could not start; relay not serving on this host",
      extra: { code },
    });
    return null;
  }
  return httpsServer;
}

// --- shared helpers ----------------------------------------------------------

function forward(target: WebSocket, data: unknown, isBinary?: boolean): void {
  if (target.readyState !== WebSocket.OPEN) return;
  target.send(data as never, { binary: Boolean(isBinary) });
}

function safeClose(ws: WebSocket, code: number, reason: string): void {
  try {
    if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
      ws.close(code, reason);
    }
  } catch {
    // `ws` throws for a status code it cannot put on the wire (1005/1006/1015...). Leaving the socket
    // open would strand the peer, so drop it.
    try {
      ws.terminate();
    } catch {
      /* best-effort */
    }
  }
}

/** A close status code `ws` can send: 1000-1014 except 1004/1005/1006, or the private range 3000-4999. */
export function isSendableCloseCode(code: number): boolean {
  return (code >= 1000 && code <= 1014 && code !== 1004 && code !== 1005 && code !== 1006) || (code >= 3000 && code <= 4999);
}

/** Owner-side verifier refusal: the uniform close frame, then terminate so a peer that ignores it cannot keep
 *  streaming into a closing socket. */
const refusedSockets = new WeakSet<WebSocket>();
function refuse(ws: WebSocket): void {
  refusedSockets.add(ws); // a refused peer's later socket error is not a second refusal
  safeClose(ws, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, RELAY_REFUSED);
  setTimeout(() => {
    try {
      ws.terminate();
    } catch {
      /* already gone */
    }
  }, REFUSE_LINGER_MS).unref();
}
