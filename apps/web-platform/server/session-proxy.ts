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
//   proxying host → owner : {type:"proxy_hello", userId, workspaceId}
//   owner → proxying host : {type:"proxy_ready"}  (after AP-2 membership re-verify)
//                         | close(ROUTING_UNAVAILABLE) (AP-2 denied / not member)
// After proxy_ready the two sockets are piped verbatim in BOTH directions,
// including close frames + codes (a drain close from the owner reaches the client;
// a client close tears down the owner leg) so grace-abort host-locality stays
// correct (#2191 overlap).
//
// INERT until 3.D: at a single host every route resolves `local`, so
// proxyClientToOwner is never called and the owner's proxy listener has no peers.

import { WebSocket, WebSocketServer } from "ws";
import { createServer, type Server as HttpsServer } from "node:https";
import { isIPv4 } from "node:net";
import type { IncomingMessage } from "node:http";
import { WS_CLOSE_CODES } from "@/lib/types";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";
import { loadProxyTlsClientCa, loadProxyTlsServerOptions } from "./proxy-tls";
import { verifyProxiedSessionMembership } from "./session-router";
import { recordProxyNotStarted, recordProxyServer } from "./proxy-listener-status";

const log = createChildLogger("session-proxy");

/** Private-net TLS port the owner's proxy listener binds (distinct from the
 *  public app port). The proxying host dials `wss://<ownerAddress>:<port>`. */
export const PROXY_LISTEN_PORT = Number(process.env.SOLEUR_PROXY_PORT || 8443);

export interface ProxyHello {
  type: "proxy_hello";
  userId: string;
  workspaceId: string;
}

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
  const port = params.port ?? PROXY_LISTEN_PORT;
  const ca = loadProxyTlsClientCa();
  if (!ca) {
    reportSilentFallback(
      new Error("proxy client CA (PROXY_TLS_CERT) unavailable — cannot dial owner with a pinned trust anchor"),
      { feature: "control_plane_route", op: "proxyClientToOwner.no-ca", extra: { ownerAddress } },
    );
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
    owner.send(JSON.stringify({ type: "proxy_hello", userId, workspaceId } satisfies ProxyHello));
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
  owner.on("close", (code: number, reason: Buffer) => safeClose(clientWs, code, reason.toString()));
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
 * Start the owner's private-net TLS proxy listener, or return null when the TLS
 * material is not configured (dev / single-host before 3.A delivers the cert —
 * the relay is then inert). Accepts a proxied connection, reads proxy_hello, runs
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

  const port = params.port ?? PROXY_LISTEN_PORT;
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
      wss = new WebSocketServer({ server: httpsServer, path: "/ws-proxy" });
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

  wss.on("connection", (ws: WebSocket, req: IncomingMessage) => {
    // Reject any connection whose private-net source is not a known web-host peer
    // BEFORE the handshake — closes the git-data-host / non-web-host takeover vector.
    const peer = normalizeProxyPeerAddress(req.socket.remoteAddress);
    if (!peerAllowlist.has(peer)) {
      reportSilentFallback(
        new Error("proxy connection from a non-peer private IP — rejected before handshake"),
        { feature: "control_plane_route", op: "createProxyServer.peer-deny", extra: { peer } },
      );
      safeClose(ws, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "not a routing peer");
      return;
    }
    // First frame MUST be proxy_hello; anything else → reject.
    ws.once("message", async (data: unknown) => {
      let hello: ProxyHello | null = null;
      try {
        const parsed = JSON.parse(String(data)) as ProxyHello;
        if (parsed?.type === "proxy_hello" && typeof parsed.userId === "string" && typeof parsed.workspaceId === "string") {
          hello = parsed;
        }
      } catch {
        /* invalid */
      }
      if (!hello) {
        safeClose(ws, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "malformed proxy handshake");
        return;
      }
      // AP-2: the OWNER re-verifies membership before serving a proxied session.
      const ok = await verifyProxiedSessionMembership(hello.userId, hello.workspaceId, createServiceClient());
      if (!ok) {
        reportSilentFallback(
          new Error("proxied session failed AP-2 membership re-verify — cross-tenant/ stale route rejected"),
          { feature: "control_plane_route", op: "createProxyServer.ap2-deny", extra: { userId: hello.userId, workspaceId: hello.workspaceId } },
        );
        safeClose(ws, WS_CLOSE_CODES.ROUTING_UNAVAILABLE, "not authorized for this workspace");
        return;
      }
      ws.send(JSON.stringify({ type: "proxy_ready" }));
      params.onProxiedSession(ws, { userId: hello.userId, workspaceId: hello.workspaceId });
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
  httpsServer.listen(port, bindAddress, () =>
    log.info({ port, bindAddress }, "session-proxy: owner proxy listener started (one-way TLS)"),
  );
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
    /* best-effort */
  }
}
