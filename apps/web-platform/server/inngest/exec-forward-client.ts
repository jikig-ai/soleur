// exec-forward-client.ts — the pinned-TLS outbound forward for pinned-class
// Inngest step calls (#9137, CTO ruling T3).
//
// When decidePlacement returns `forward`, this module replays the step POST
// verbatim — method, path, full query (fnId/stepId), headers (minus the
// RFC 7230 hop-by-hop set and Host), raw body — to the exec host's private-TLS
// receiver (EXEC_FORWARD_URL, the literal pin — never request-Host- or
// env-derived) and streams the response back.
//
// Transport: `https.request` with `ca` + `rejectUnauthorized: true` — the same
// dial shape the session relay uses (session-proxy.ts, NEVER false — that
// would be MITM-able). The PROXY_TLS cert carries SANs over every web host's
// private IP (proxy-tls.ts header), so Node's DEFAULT identity check passes
// on the IP-addressed dial: no `checkServerIdentity` override, and never a new
// verification scheme.
//
// Streaming (ADR-243, the 2026-09-23 double-run learning): the upstream
// response is passed through as a live stream — NEVER buffered — because step
// responses stream a 201 + heartbeat for minutes. Timeouts are ONLY a connect
// bound plus a per-chunk idle bound (socket inactivity); a TOTAL deadline
// would recreate the CF-524 class where a live step gets re-dispatched.
//
// Fail-closed: any dial/TLS/stream failure raises PlacementForwardError
// ("placement.forward_failed") — the caller must never fall back to local
// execution (that is exactly the wrong-host execution this mechanism exists
// to prevent).
//
// Module-load safety: env (PROXY_TLS_CERT) is read inside the call, never at
// import — `next build` loads this module without env.

import { request as httpsRequest } from "node:https";
import { Readable } from "node:stream";
import type { ReadableStream as NodeReadableStream } from "node:stream/web";
import type { IncomingMessage } from "node:http";

import { createChildLogger } from "../logger";
import { reportSilentFallback } from "../observability";
import { loadProxyTlsClientCa } from "../proxy-tls";
import {
  EXEC_FORWARD_HEADER,
  EXEC_FORWARD_URL,
  EXEC_PLACEMENT_FEATURE,
  decidePlacement,
  gatherPlacementFacts,
  recordPlacementDecision,
  refuseResponse,
} from "./exec-placement";

const log = createChildLogger("inngest-exec-placement");

/** Bounded time to establish TCP+TLS to the exec host's private listener. */
export const EXEC_FORWARD_CONNECT_TIMEOUT_MS = 10_000;
/**
 * Per-chunk idle bound on the established socket — a socket silent this long
 * is dead. Step streams heartbeat every ~3 s, so 60 s of silence is a dead
 * peer, not a slow one. NOT a total deadline: a step may stream for an hour
 * and every heartbeat resets this.
 */
export const EXEC_FORWARD_IDLE_TIMEOUT_MS = 60_000;

/**
 * The distinct error for every forward-path failure. Its `code` is the
 * `placement.forward_failed` signal the runbook and Sentry query name.
 */
export class PlacementForwardError extends Error {
  readonly code = "placement.forward_failed" as const;
}

/** RFC 7230 §6.1 hop-by-hop headers — plus `host` (the target's own Host is set
 *  by the dial; forwarding the public Host would lie about the hop). */
const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
  "host",
]);

/** Tokens named by a `Connection:` header value are hop-by-hop too (RFC 7230). */
function connectionTokens(raw: string | null | undefined): Set<string> {
  const out = new Set<string>();
  for (const value of raw?.split(",") ?? []) {
    const token = value.trim().toLowerCase();
    if (token) out.add(token);
  }
  return out;
}

/** End-to-end headers verbatim + the marker — the only mutation the envelope takes. */
export function buildForwardHeaders(req: Request): Record<string, string> {
  const connTokens = connectionTokens(req.headers.get("connection"));
  const out: Record<string, string> = {};
  for (const [name, value] of req.headers) {
    const lower = name.toLowerCase();
    if (HOP_BY_HOP.has(lower) || connTokens.has(lower)) continue;
    out[name] = value;
  }
  out[EXEC_FORWARD_HEADER] = "1";
  return out;
}

export interface ExecForwardDeps {
  /** Pinned CA — defaults to loadProxyTlsClientCa() (PROXY_TLS_CERT). */
  ca?: string | null;
  /** TEST seam only — prod code never passes this; the literal pin stands. */
  target?: string;
  connectTimeoutMs?: number;
  idleTimeoutMs?: number;
}

/**
 * Forward `req` to the exec host's private-TLS receiver and resolve to the
 * upstream response as a live stream. Throws PlacementForwardError on any
 * failure before the response headers arrive; a mid-stream upstream failure
 * surfaces as a body-stream error to the consumer (fail-closed either way).
 */
export async function forwardStepCall(
  req: Request,
  deps: ExecForwardDeps = {},
): Promise<Response> {
  const ca = deps.ca !== undefined ? deps.ca : loadProxyTlsClientCa();
  if (!ca) {
    throw new PlacementForwardError(
      "placement.forward_failed: no PROXY_TLS_CERT — cannot pin the exec-host TLS dial",
    );
  }
  // Origin from the literal pin; path + query verbatim from the request.
  const inbound = new URL(req.url);
  const target = new URL(deps.target ?? EXEC_FORWARD_URL);
  target.pathname = inbound.pathname;
  target.search = inbound.search;

  const connectTimeoutMs = deps.connectTimeoutMs ?? EXEC_FORWARD_CONNECT_TIMEOUT_MS;
  const idleTimeoutMs = deps.idleTimeoutMs ?? EXEC_FORWARD_IDLE_TIMEOUT_MS;

  return await new Promise<Response>((resolve, reject) => {
    let settled = false;
    const fail = (err: unknown): void => {
      if (settled) return;
      settled = true;
      reject(
        err instanceof PlacementForwardError
          ? err
          : new PlacementForwardError(
              `placement.forward_failed: ${err instanceof Error ? err.message : String(err)}`,
            ),
      );
    };

    const upstream = httpsRequest(
      target,
      {
        method: req.method,
        // Pinned CA + rejectUnauthorized TRUE — never disable verification
        // (the session-relay dial shape; the cert's private-IP SANs satisfy
        // Node's default identity check — no checkServerIdentity override).
        ca,
        rejectUnauthorized: true,
        headers: buildForwardHeaders(req),
      },
      (res: IncomingMessage) => {
        if (settled) return;
        settled = true;
        // Per-chunk idle bound is the socket inactivity timer armed below —
        // heartbeats keep a live step's socket busy. Stream pass-through —
        // never buffer (ADR-243: buffered steps re-ran whole under CF 524).
        const connTokens = connectionTokens(
          typeof res.headers.connection === "string"
            ? res.headers.connection
            : undefined,
        );
        const headers = new Headers();
        for (let i = 0; i + 1 < res.rawHeaders.length; i += 2) {
          const name = res.rawHeaders[i];
          const lower = name.toLowerCase();
          if (HOP_BY_HOP.has(lower) || connTokens.has(lower)) continue;
          headers.append(name, res.rawHeaders[i + 1]);
        }
        const webBody = Readable.toWeb(res) as unknown as ReadableStream;
        resolve(
          new Response(webBody, {
            status: res.statusCode ?? 502,
            statusText: res.statusMessage,
            headers,
          }),
        );
      },
    );

    upstream.on("error", fail);

    // Two bounds, never a total deadline (ADR-243):
    //   - connect: the socket gets connectTimeoutMs to reach TLS-secure;
    //   - per-chunk idle: after secureConnect the socket timeout becomes
    //     idleTimeoutMs of inactivity — a streamed step's heartbeats keep it
    //     alive, a dead peer trips it.
    // 'timeout' never destroys on its own — we destroy with OUR error so the
    // failure is always the distinct placement.forward_failed.
    let connected = false;
    upstream.setTimeout(connectTimeoutMs);
    upstream.on("socket", (socket) => {
      socket.on("timeout", () => {
        upstream.destroy(
          new PlacementForwardError(
            `placement.forward_failed: ${connected ? "idle" : "connect"} timeout after ${connected ? idleTimeoutMs : connectTimeoutMs}ms`,
          ),
        );
      });
      socket.once("secureConnect", () => {
        connected = true;
        socket.setTimeout(idleTimeoutMs);
      });
    });

    // Upload the inbound body verbatim, streamed. No body → just end.
    if (req.body) {
      const bodyStream = Readable.fromWeb(
        req.body as unknown as NodeReadableStream<Uint8Array>,
      );
      bodyStream.on("error", (err) => upstream.destroy(err));
      bodyStream.pipe(upstream);
    } else {
      upstream.end();
    }
  });
}

/**
 * The route-side POST wrapper: gather facts → decide → execute/forward/refuse.
 * `localPost` is the SDK `serve()` handler, invoked unchanged on `execute`.
 * Every refusal and every `placement.forward_failed` is mirrored to Sentry
 * with feature=inngest-exec-placement (task 3.4 wiring — the refusal mirror
 * itself lives in recordPlacementDecision, this is the forward-failure one).
 */
export async function dispatchPlacementAwarePost<Req extends Request>(
  req: Req,
  res: unknown,
  localPost: (req: Req, res: unknown) => Promise<Response>,
): Promise<Response> {
  const facts = gatherPlacementFacts(req);
  const decision = decidePlacement(facts);
  recordPlacementDecision(facts, decision);
  if (decision.action === "execute") return localPost(req, res);
  if (decision.action !== "forward") {
    return refuseResponse(decision);
  }
  try {
    return await forwardStepCall(req, { target: decision.target });
  } catch (err) {
    // Fail-closed: NEVER fall back to local execution — a pinned call on the
    // wrong host is the exact defect this mechanism exists to prevent.
    const forwardError =
      err instanceof PlacementForwardError
        ? err
        : new PlacementForwardError(
            `placement.forward_failed: ${err instanceof Error ? err.message : String(err)}`,
          );
    log.error(
      {
        op: EXEC_PLACEMENT_FEATURE,
        event: "placement_decision",
        fnId: facts.fnId,
        decision: "forward",
        host_ip: facts.hostIp,
        err: forwardError,
      },
      "placement_decision: forward_failed",
    );
    reportSilentFallback(forwardError, {
      feature: EXEC_PLACEMENT_FEATURE,
      op: "placement.forward_failed",
      extra: { fnId: facts.fnId, hostIp: facts.hostIp },
    });
    return Response.json(
      { error: "placement.forward_failed" },
      { status: 502 },
    );
  }
}
