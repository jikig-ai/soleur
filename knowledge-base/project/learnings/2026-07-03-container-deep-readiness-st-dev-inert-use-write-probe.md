---
title: "Container deep-readiness: st_dev mountpoint check is inert inside a docker bind mount — use a write+unlink probe"
date: 2026-07-03
category: integration-issues
module: apps/web-platform/server
tags: [readiness, docker, bind-mount, health-check, fail-closed, loopback-gating, observability]
issue: 5966
pr: 5967
---

# Container deep-readiness for a host-local volume: `st_dev` is inert inside a bind mount — probe by writing

## Problem

`/health` is a **liveness** probe (hardcoded `status:"ok"` + a *shared*-Supabase reachability
check). On a multi-host topology where each web host serves its **own** host-local
`/workspaces` block volume (ADR-068), a bare host with an empty/unmounted `/workspaces` still
returns `200 / status:ok / supabase:connected` — a routing lie. A separate deep-readiness
signal is needed before a host can receive live LB weight: "can THIS host actually serve?"

The intuitive implementation — compare device IDs to prove `/workspaces` is a distinct
mountpoint (`st_dev(/workspaces) !== st_dev(/)`) — is **wrong inside the container**.

## Key Insight

**Inside the webapp container, `/workspaces` is a docker `-v /mnt/data/workspaces:/workspaces`
bind mount over an overlayfs root, so `st_dev(/workspaces) !== st_dev(/)` is ALWAYS true —
even when the host's block volume failed to attach.** Docker auto-creates the bind source
directory on the host root fs and bind-mounts *that*, so the device IDs differ regardless of
whether the real volume is present. The whole "is it mounted?" defense collapses.

**The only signal that proves serviceability from inside the container is a real write.** A
`writeFileSync(join(root, ".readyz-probe-<rand>"), "", { flag: "wx" })` + `unlinkSync`
(fail-closed on any throw) catches every failure mode the mountpoint check cannot:
- absent / unmounted → `ENOENT`
- read-only / degraded mount → `EROFS` (the silent-write-loss mode the mountpoint check
  would pass while user writes are silently lost)
- permission / I/O → `EACCES` / `EIO`

Pair the write probe with a **populated** check (≥1 host-local workspace dir; exclude
`lost+found` — a freshly-`mkfs`'d ext4/xfs volume carries one and would false-report
populated) to reject a fresh/empty volume. `ready = writable && populated`.

## Solution (what shipped)

`apps/web-platform/server/readiness.ts` — `GET /internal/readyz`, returning non-2xx unless
`/workspaces` is **writable AND populated**. Design notes worth reusing:

1. **Separate module, not folded into `health.ts`.** The physical split structurally enforces
   the "no mount coupling on `/health`" invariant — you cannot accidentally couple them. The
   LB monitor must stay reachability-only on `/health` (both hosts share one Supabase, so
   body-coupling would eject the sole live origin on a DB blip).
2. **Fail-closed must be COMPLETE.** An unguarded throw in the route handler becomes an
   uncaught exception → `installCrashHandlers()` → `process.exit(1)` = a *restart* of the live
   host, strictly worse than a 503. Wrap the ENTIRE handler body (gate lines included) in
   try/catch → 503, and make the builder itself total (returns `ready:false` on any internal
   error). Use `req.socket?.remoteAddress` (optional chain) so a missing socket can't throw.
3. **Boot-time Sentry mirror.** A pull-only endpoint has a steady-state blind window (a
   mis-mounted host with no consumer polling). A latched one-shot `verifyWorkspacesMountOnce()`
   at boot (`reportSilentFallback`, `op=boot-readiness`) is the async/push layer. NB the
   existing `verifyPluginMountOnce` checks the *plugin* mount, NOT `/workspaces` — it passes on
   a bare volume, so it does not cover this surface.
4. **Resolve the root ONCE.** Read `WORKSPACES_ROOT` once and pass it into BOTH the write probe
   and the count (extract a root-parameterized `countWorkspaceDirsAt(root)`), so the two
   signals provably read the same root — do not call a helper that reads a module-load cached
   root, which would split-brain.
5. **Flap-safety is a contract, not code here.** Any consumer draining a *live* origin on a
   not-ready read MUST require N≥2 consecutive not-ready reads; the fail-closed single-shot
   bias applies only to the *candidate*/pre-pool decision. Record it in the ADR so the future
   LB-config PR inherits it (and ship an executable N≥2 test WITH that consumer, not just the
   prose line).

## Security subtlety (surfaced at review): peer vs Host primacy behind a CF tunnel

The endpoint is gated to the loopback transport peer (`req.socket.remoteAddress`, unspoofable
off-host) AND a loopback Host header. The intuitive framing — "socket peer is the unspoofable
primary control, Host header is secondary" — is **inverted for tunnel traffic**: `cloudflared`
runs on the host and connects to the origin at `127.0.0.1`, so for ALL tunnel-relayed requests
the socket peer is loopback. The **Host header is therefore the load-bearing boundary** behind
the tunnel (an off-host attacker cannot smuggle a `Host: 127.0.0.1` through Cloudflare's
Host/SNI routing → no route → never reaches origin); the peer check only additionally blocks
direct off-host TCP to the port (the firewall's job too). Document this so a future maintainer
does not relax the Host clause thinking the peer alone protects. Corollary: such loopback-gated
endpoints are reachable only by **on-host** consumers — an off-host LB health probe gets 403,
so the readiness consumer must run on-host (drain tooling / deploy sidecar) or via the
private-net proxy.

## Test approach that worked

Use **real temp dirs** (`mkdtempSync`), not a mocked `fs` — mocking `fs` makes a write-probe
test vacuous. Force EROFS via `chmodSync(root, 0o555)` (guard `if (process.getuid?.() === 0)
return` — root bypasses perm bits). Inject the builder into the route handler
(`handleReadyzRequest(req, res, build = buildReadinessResponse)`) so the catch→503 path is
testable without brittle fs sabotage. Exercise the `::ffff:127.0.0.1` mapped-peer branch
explicitly (a regression removing it ships green otherwise).

## Session Errors

1. **Accidental placeholder `Write` to a malformed path** (`.worktrees/feat-one-plugin-holder`
   instead of the intended `apps/web-platform/server/loopback.ts`). Recovered immediately via
   `rm`. One-off typo, no recurrence vector. **Prevention:** none warranted — a single
   mis-typed path caught and reverted within one tool call; a hook would add noise for a
   self-correcting slip.

## Tags
category: integration-issues
module: apps/web-platform/server
