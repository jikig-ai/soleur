// Token-bearing public path prefixes — the last segment is a bearer
// credential (#8984 review): `/invite/<token>` invites stay valid for days,
// `/shared/<token>` grants document read, `/api/account/export/<jobId>` is a
// job-scoped artifact URL. `tracesSampler` made transaction envelopes live
// (previously `tracesSampleRate: 0`), and `request.url`/`query_string` pass
// through the key-name scrub untouched — these prefixes keep the boundary
// honest for the new surface.
//
// Single source of truth shared by `server/sentry-scrub.ts` (error/transaction
// envelopes) and `sentry.client.config.ts` (browser tracing envelopes, #9178):
// duplicating this list across server/ and client config files is the
// replicated-literal parity-drift class — a prefix added on one side only
// reopens the leak the other closed.
export const TOKEN_PATH_PREFIXES = [
  "/invite/",
  "/shared/",
  "/api/shared/",
  "/api/account/export/",
] as const;

/** Reduce a raw path to `<prefix><token>` when it carries a bearer tail. */
export function reduceTokenPath(pathname: string): string {
  for (const prefix of TOKEN_PATH_PREFIXES) {
    if (pathname.startsWith(prefix)) return `${prefix}<token>`;
  }
  return pathname;
}

/** Strip query + hash + bearer-token tails off a request URL string. */
export function sanitizeRequestUrl(url: string): string {
  try {
    const u = new URL(url);
    // Query strings carry OAuth `code` params and other credentials; hash
    // carries the implicit-flow access_token. Neither belongs in Sentry.
    u.search = "";
    u.hash = "";
    // Build the string directly — assigning `<token>` via URL.pathname would
    // percent-encode the angle brackets.
    return `${u.origin}${reduceTokenPath(u.pathname)}${u.search}`;
  } catch {
    // Unparsable URL — still strip the query/hash tail fail-closed.
    const q = url.indexOf("?");
    const h = url.indexOf("#");
    const cut = [q, h].filter((i) => i >= 0).sort((a, b) => a - b)[0];
    return cut !== undefined ? url.slice(0, cut) : url;
  }
}

/** Transaction names carry raw path tails for unrouted requests
 * ("GET /invite/<token>") — same prefix reduction as request.url. */
export function reduceTransactionName(tx: string): string {
  for (const prefix of TOKEN_PATH_PREFIXES) {
    const idx = tx.indexOf(prefix);
    if (idx >= 0) {
      const after = idx + prefix.length;
      const end = tx.indexOf(" ", after);
      return tx.slice(0, after) + "<token>" + (end >= 0 ? tx.slice(end) : "");
    }
  }
  return tx;
}
