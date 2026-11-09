// Explicit slow-header bound for the plain :80 server (ADR-321 item 12, ruled by CTO agent 2026-11-08).
//
// Until now the :80 server assigned `headersTimeout = 910 s`, which did nothing useful: Node bounds the header phase by
// min(headersTimeout, requestTimeout), and requestTimeout defaults to 300 s, so the operative cutoff was an inherited 300 s.
// This module states the number: 60 s for the header phase inside a 300 s whole-request window. 60 s is also what the :443
// listener gets from Node's own default, so both listeners now cut a stalled client at the same bound.
//
// Node enforces these on a periodic sweep (connectionsCheckingInterval, 30 s by default), so the real cutoff is the timeout
// plus up to 30 s. This file imports nothing from the server on purpose: the behavioural test imports it directly, and
// `index.ts` (which starts a server) is never imported by a test except with mocks.
//
// Applies to the :80 server ONLY. origin-tls.ts must not assign either property (pinned in origin-tls.test.ts).

import type { Server } from "node:http";

/** Header phase: a client that has not finished sending its headers by now is answered 408 and dropped. */
export const PLAIN_HTTP_HEADERS_TIMEOUT_MS = 60_000;
/** Whole request (headers plus body): Node's own default, pinned here so it is a stated number and not an inherited one. */
export const PLAIN_HTTP_REQUEST_TIMEOUT_MS = 300_000;

export interface PlainHttpTimeouts {
  headersMs: number;
  requestMs: number;
}

/**
 * Assigns both timeouts on `server`. Throws (assigning nothing) when the header bound exceeds the request bound, because
 * Node would then silently use the smaller value and the stated header number would be a lie. Equal values are allowed.
 */
export function applyPlainHttpTimeouts(
  server: Pick<Server, "headersTimeout" | "requestTimeout">,
  timeouts: PlainHttpTimeouts = {
    headersMs: PLAIN_HTTP_HEADERS_TIMEOUT_MS,
    requestMs: PLAIN_HTTP_REQUEST_TIMEOUT_MS,
  },
): void {
  if (timeouts.headersMs > timeouts.requestMs) {
    throw new Error(
      `applyPlainHttpTimeouts: headers timeout (${timeouts.headersMs} ms) exceeds the request timeout (${timeouts.requestMs} ms)`,
    );
  }
  server.headersTimeout = timeouts.headersMs;
  server.requestTimeout = timeouts.requestMs;
}
