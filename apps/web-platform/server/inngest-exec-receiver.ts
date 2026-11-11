// inngest-exec-receiver.ts — the exec host's private-TLS ingress for forwarded
// Inngest step calls (#9137, CTO ruling T3; plan-review P1/P5).
//
// A pinned-class step call that lands on a NON-exec web host is forwarded
// verbatim by exec-forward-client.ts to https://10.0.1.10:8445/api/inngest.
// This module is the listener that terminates that hop: a sibling
// `https.createServer` on dedicated port 8445 (NOT :8443 — the wss relay's
// 10 s HELLO_DEADLINE_MS would kill a step call that streams for minutes, and
// NOT 8444 — that number is a deliberately-wrong sentinel in the infra
// egress-firewall/lb-weight fixtures), presenting the SAME PROXY_TLS material
// and bound to the private net exactly like the session relay.
//
// It is a TRANSPORT, not a second app (the origin-tls.ts pattern): an
// admitted, marked POST to /api/inngest is re-emitted as a 'request' on the
// app's own HTTP server, so the request flows through the same Next handler,
// the same /api/inngest route, and the same SDK HMAC verification as a public
// call. The x-soleur-exec-forward marker is trusted ONLY because it arrived
// on this private-TLS listener — the route's placement dispatcher sees marked
// + exec host and executes; a forged marker on the public path is refused by
// the non-exec rule or fails signature.
//
// Admission is the relay's two controls, reused verbatim (a forwarded call
// carries a pre-signed step payload — an open port here would let any
// private-net host inject step calls): the SOLEUR_PROXY_PEER_ALLOWLIST
// peer-origin check on the raw socket BEFORE Node's TLS wrapper reads a byte
// (#12288 pattern), and the SOLEUR_PROXY_BIND private-net bind guard.
//
// INERT WHEN ABSENT: no TLS material, no bind, no allowlist → returns null and
// the app keeps serving (dev, CI, canary). A listener that cannot start must
// never crash startup — the same discipline as createProxyServer.

import { createServer as createHttpsServer, type Server as HttpsServer } from "node:https";
import type { Server as HttpServer, IncomingMessage, ServerResponse } from "node:http";
import { isIP, type Socket } from "node:net";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";
import { loadProxyTlsServerOptions } from "./proxy-tls";
import {
  isAllowedProxyBind,
  isAllowedProxyPeer,
  normalizeProxyPeerAddress,
  parseProxyPeerAllowlist,
} from "./session-proxy";
import {
  EXEC_FORWARD_HEADER,
  EXEC_FORWARD_PORT,
  EXEC_PLACEMENT_FEATURE,
} from "./inngest/exec-placement";

const log = createChildLogger("inngest-exec-placement");

/** The only path this transport serves — the forwarder's verbatim target. */
const INNGEST_PATH_PREFIX = "/api/inngest";

/** A peer label for deny logs: the kernel IP when it parses, a fixed token otherwise. */
function peerLabel(addr: string | undefined | null): string {
  if (!addr) return "unknown";
  const peer = normalizeProxyPeerAddress(addr);
  return isIP(peer) !== 0 ? peer : "invalid";
}

/**
 * Is this a forwarded step call? Marker + POST + the inngest path — all three,
 * because the marker is what the private ingress attests. Anything else on
 * this port (an allowlisted peer probing, a typo'd dial) gets a flat 404.
 */
function isForwardedStepCall(req: IncomingMessage): boolean {
  if (req.method !== "POST") return false;
  if (req.headers[EXEC_FORWARD_HEADER] === undefined) return false;
  const url = req.url ?? "";
  return url === INNGEST_PATH_PREFIX || url.startsWith(`${INNGEST_PATH_PREFIX}?`);
}

/**
 * Start the exec-step receiver next to `httpServer`, or return null when it
 * must not run. Never throws — a relay-adjacent listener fault must not take
 * the app down (mirror createProxyServer's fencing).
 */
export function startInngestExecReceiver(params: {
  /** The app's plain-HTTP server; admitted requests are re-emitted on it. */
  httpServer: HttpServer;
  /** Default EXEC_FORWARD_PORT (8445). Tests may bind 0 for ephemeral. */
  port?: number;
  /** The in-container bind: `0.0.0.0` (prod — docker publishes it on the host's
   *  private IP) or `10.0.1.x`; anything else refuses to start. Defaults to
   *  SOLEUR_PROXY_BIND — the same private-net bind the relay uses. */
  bindAddress?: string;
  /** TEST-ONLY seam, honoured solely under vitest (like session-proxy's). */
  privateBindPrefix?: string;
}): HttpsServer | null {
  const tls = loadProxyTlsServerOptions();
  if (!tls) {
    log.info(
      "inngest-exec-receiver: no PROXY_TLS material — exec-step receiver disabled (single-host/dev)",
    );
    return null;
  }
  const bindAddress = params.bindAddress ?? process.env.SOLEUR_PROXY_BIND?.trim();
  if (!bindAddress) {
    reportSilentFallback(
      new Error(
        "SOLEUR_PROXY_BIND unset — refusing to start the inngest exec-step receiver on all " +
          "interfaces (forwarded step calls must arrive on the private net only)",
      ),
      {
        feature: EXEC_PLACEMENT_FEATURE,
        op: "exec_receiver.no-bind",
      },
    );
    return null;
  }
  const bindPrefix = process.env.VITEST
    ? (params.privateBindPrefix ?? "10.0.1.")
    : "10.0.1.";
  if (!isAllowedProxyBind(bindAddress, bindPrefix)) {
    reportSilentFallback(
      new Error(
        `SOLEUR_PROXY_BIND is not an IPv4 literal of 0.0.0.0 or ${bindPrefix}x — refusing to start ` +
          "the inngest exec-step receiver (forwarded step calls must arrive on the private net only)",
      ),
      {
        feature: EXEC_PLACEMENT_FEATURE,
        op: "exec_receiver.bad-bind",
      },
    );
    return null;
  }
  const peerAllowlist = parseProxyPeerAllowlist(
    process.env.SOLEUR_PROXY_PEER_ALLOWLIST,
  );
  if (peerAllowlist.size === 0) {
    reportSilentFallback(
      new Error(
        "SOLEUR_PROXY_PEER_ALLOWLIST unset/empty — refusing to start the inngest exec-step " +
          "receiver: a port that forwards pre-signed step calls into the app must restrict " +
          "its private-net source to known web-host peers",
      ),
      {
        feature: EXEC_PLACEMENT_FEATURE,
        op: "exec_receiver.no-peer-allowlist",
      },
    );
    return null;
  }

  let httpsServer: HttpsServer;
  try {
    httpsServer = createHttpsServer({ key: tls.key, cert: tls.cert });
  } catch (err) {
    const rawCode = (err as NodeJS.ErrnoException | undefined)?.code;
    const code =
      typeof rawCode === "string" && /^[A-Z0-9_]{1,64}$/.test(rawCode)
        ? rawCode
        : undefined;
    reportSilentFallback(
      new Error(`inngest exec-step receiver TLS setup failed (${code ?? "unknown"})`),
      {
        feature: EXEC_PLACEMENT_FEATURE,
        op: "exec_receiver.tls-setup",
        extra: { code },
      },
    );
    return null;
  }

  // #12288 pattern — admit a peer on the raw TCP stream BEFORE Node's TLS
  // wrapper reads a byte. Prepended so it runs ahead of the https server's own
  // `connection` listener that starts the handshake; a non-allowlisted source
  // is destroyed first. A missing remoteAddress is a deny, never an allow.
  httpsServer.prependListener("connection", function admitExecReceiverPeer(
    socket: Socket,
  ) {
    const remote = socket.remoteAddress;
    if (!isAllowedProxyPeer(remote, peerAllowlist)) {
      socket.destroy();
      log.warn(
        { peer: peerLabel(remote) },
        "inngest-exec-receiver: denied non-allowlisted peer",
      );
    }
  });

  httpsServer.on("request", (req: IncomingMessage, res: ServerResponse) => {
    if (isForwardedStepCall(req)) {
      // The origin-tls pattern: re-emit on the app's own server so the request
      // runs the SAME handler graph — Next, /api/inngest, the SDK HMAC check —
      // as a public call. The marker is trusted because it arrived here, on
      // the private-TLS, peer-allowlisted ingress.
      params.httpServer.emit("request", req, res);
      return;
    }
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "not_found" }));
  });

  // A listen failure (EADDRNOTAVAIL on a not-yet-attached private IP,
  // EADDRINUSE on a stale listener) is emitted async as 'error'; a throwing
  // listen() is synchronous. Both are fenced: the receiver is then simply not
  // bound, the fault is mirrored once, and the app keeps serving — a
  // relay-adjacent fault must never restart-loop the whole process.
  httpsServer.on("error", (err: NodeJS.ErrnoException) => {
    reportSilentFallback(err, {
      feature: EXEC_PLACEMENT_FEATURE,
      op: "exec_receiver.listen-error",
      message:
        "inngest exec-step receiver failed to bind; forwarded step calls will fail closed (placement.forward_failed) on the senders",
      extra: { code: err.code, bindAddress, port: params.port ?? EXEC_FORWARD_PORT },
    });
  });

  try {
    httpsServer.listen(params.port ?? EXEC_FORWARD_PORT, bindAddress, () =>
      log.info(
        { port: params.port ?? EXEC_FORWARD_PORT, bindAddress },
        "inngest-exec-receiver: exec-step listener started (pinned one-way TLS)",
      ),
    );
  } catch (err) {
    const rawCode = (err as NodeJS.ErrnoException | undefined)?.code;
    const code =
      typeof rawCode === "string" && /^[A-Z0-9_]{1,64}$/.test(rawCode)
        ? rawCode
        : undefined;
    try {
      httpsServer.close();
    } catch {
      /* never listened */
    }
    reportSilentFallback(null, {
      feature: EXEC_PLACEMENT_FEATURE,
      op: "exec_receiver.listen-throw",
      message: "inngest exec-step receiver could not start; receiver not bound on this host",
      extra: { code },
    });
    return null;
  }
  return httpsServer;
}
