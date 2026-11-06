// Shared loopback gating helpers for the internal ops endpoints
// (/internal/metrics, /internal/readyz). Extracted to a LEAF module (imports
// nothing from index.ts / readiness.ts) so both can import it without a cycle —
// index.ts imports readiness.ts, so readiness.ts cannot import back from
// index.ts. Single source of truth: hardening one loopback form here propagates
// to every gated endpoint instead of drifting across per-file copies.

// Accept loopback Host headers only. resource-monitor.sh (and the readyz
// drain/undrain tooling) run on the same host and curl
// http://127.0.0.1:3000/internal/...; external callers arrive through Cloudflare
// with the public Host header.
//
// A loopback Host is NOT unreachable from outside, and this module used to claim it was
// ("a loopback Host matches no configured hostname → no route"). That holds for OUR zone only:
// anyone who knows an origin IP can put it behind their OWN Cloudflare zone and use an Origin
// Rule to rewrite the Host header to `127.0.0.1`, and the origin (:80, and :443 once the origin
// TLS listener is live) then sees a loopback Host. The Host check alone is therefore not a
// boundary. Cloudflare adds `cf-ray` / `cf-connecting-ip` to every proxied request and a tenant
// cannot strip them, so {@link hasProxyMarkers} is the second clause: a request that went through
// ANY proxy is never an on-host caller. On-host consumers (resource-monitor.sh, docker exec)
// send none of those headers. This is defence in depth, not origin authentication (Authenticated
// Origin Pulls stays deferred, ADR-321). The socket peer (isLoopbackPeer) additionally
// constrains direct off-host TCP to the port. Port suffix is optional so e2e tests that hit a
// non-3000 port still match.
//
// Reachability differs by endpoint on the bridge-networked prod container
// (`-p 0.0.0.0:3000:3000`, default bridge): /internal/metrics gates on
// isLoopbackHost ONLY, so resource-monitor.sh's bare HOST `curl 127.0.0.1:3000`
// works (Host: 127.0.0.1 passes). /internal/readyz ALSO gates on isLoopbackPeer,
// and a host-published-port curl presents the docker bridge gateway as its peer
// (not loopback) → 403; its on-host consumers therefore probe from INSIDE the
// container via `docker exec` (workspaces-luks-emit.sh:wl_probe_readyz).
/**
 * Request headers a reverse proxy adds. Cloudflare adds the first three on every proxied request
 * (and the client cannot remove them); `x-real-ip` is the usual proxy header. Vector and
 * resource-monitor.sh send none. `x-forwarded-for` is handled separately by {@link hasProxyMarkers}
 * because Next.js itself adds x-forwarded-* once it takes over a request (egress-audit-ingest.ts
 * reads after Next and so excludes it; the gates here run before Next).
 */
export const PROXY_MARKER_HEADERS = ["forwarded", "cf-connecting-ip", "cf-ray", "x-real-ip"] as const;

/** True when the request carries any sign of having passed through a proxy. */
export function hasProxyMarkers(headers: Readonly<Record<string, string | string[] | undefined>>): boolean {
  return (
    PROXY_MARKER_HEADERS.some((h) => headers[h] !== undefined) || headers["x-forwarded-for"] !== undefined
  );
}

export function isLoopbackHost(hostHeader: string | undefined): boolean {
  if (!hostHeader) return false;
  const host = hostHeader.split(":")[0];
  return host === "127.0.0.1" || host === "localhost" || host === "::1";
}

// Loopback transport peer (req.socket.remoteAddress) — unspoofable off-host (it
// is the real TCP peer, never a client header). Covers the IPv4-mapped-IPv6
// form docker/node presents. Fail-closed: anything outside the loopback set
// (including undefined) is treated as non-loopback.
export function isLoopbackPeer(remoteAddress: string | undefined): boolean {
  return (
    remoteAddress === "127.0.0.1" ||
    remoteAddress === "::1" ||
    remoteAddress === "::ffff:127.0.0.1"
  );
}
