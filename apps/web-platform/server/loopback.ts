// Shared loopback gating helpers for the internal ops endpoints
// (/internal/metrics, /internal/readyz). Extracted to a LEAF module (imports
// nothing from index.ts / readiness.ts) so both can import it without a cycle —
// index.ts imports readiness.ts, so readiness.ts cannot import back from
// index.ts. Single source of truth: hardening one loopback form here propagates
// to every gated endpoint instead of drifting across per-file copies.

// Accept loopback Host headers only. resource-monitor.sh (and the readyz
// drain/undrain tooling) run on the same host and curl
// http://127.0.0.1:3000/internal/...; external callers arrive via the CF tunnel
// with the public Host header. Behind the tunnel the socket peer is loopback for
// ALL relayed traffic (cloudflared connects to the origin at 127.0.0.1), so for
// tunnel traffic THIS Host-header check is the load-bearing boundary: an
// off-host attacker cannot smuggle a `Host: 127.0.0.1`/`localhost` header
// through Cloudflare (the edge routes on Host/SNI to the zone; a loopback Host
// matches no configured hostname → no route → never reaches origin). The socket
// peer (isLoopbackPeer) additionally constrains direct off-host TCP to the port,
// which the host firewall should already block. Port suffix is optional so e2e
// tests that hit a non-3000 port still match.
//
// Reachability differs by endpoint on the bridge-networked prod container
// (`-p 0.0.0.0:3000:3000`, default bridge): /internal/metrics gates on
// isLoopbackHost ONLY, so resource-monitor.sh's bare HOST `curl 127.0.0.1:3000`
// works (Host: 127.0.0.1 passes). /internal/readyz ALSO gates on isLoopbackPeer,
// and a host-published-port curl presents the docker bridge gateway as its peer
// (not loopback) → 403; its on-host consumers therefore probe from INSIDE the
// container via `docker exec` (workspaces-luks-emit.sh:wl_probe_readyz).
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
