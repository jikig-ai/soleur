// host-private-ip.ts — per-host private-net IP identity (#9137, CTO ruling T2
// 2026-11-10, re-ruled).
//
// The placement-aware Inngest forwarder (server/inngest/exec-placement.ts)
// needs each web host to self-identify as the step-executing host — the host
// carrying the ADR-119 workspaces LUKS volume and the Inngest `--sdk-url`
// registration poll. ci-deploy.sh injects the host's `10.0.1.x` NIC address as
// `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"` into the prod container (empty for
// the deploy canary — an empty value must refuse pinned work, which is correct
// because the canary serves no step traffic).
//
// Why a NEW env and not SOLEUR_PROXY_BIND: the container receives the literal
// `0.0.0.0` for the proxy bind (ci-deploy.sh) — a wildcard is a bind address,
// never an identity. And not SOLEUR_HOST_ID: the Hetzner instance id changes on
// every web-host replace, which would stall every pinned function until a
// manual constant edit. The private IP and the `10.0.1.10` exec pin share one
// Terraform source (variables.tf `web_hosts[].private_ip`, network.tf
// `hcloud_server_network.web["web-1"]`) and therefore survive web-host-replace.
//
// FAIL-CLOSED semantics: a host that cannot establish it is the exec host is
// "unknown" — the forwarder refuses pinned step calls rather than executing
// them on a guess (never a local fallback). Read at CALL TIME, never cached at
// module load, mirroring resolveProxyPort (session-proxy.ts): a module-load
// constant would freeze the empty-canary value into prod and route modules
// load without env during `next build`.
//
// This module imports NOTHING from server/ — the same leaf discipline as
// host-identity.ts, so inngest/* modules can consume it without pulling the
// request-path dependency tree.

/** `process.env.SOLEUR_HOST_PRIVATE_IP` is the only source. */
export const HOST_PRIVATE_IP_ENV = "SOLEUR_HOST_PRIVATE_IP";

/** The three-valued answer to "is THIS host the exec host?" */
export type HostExecIdentity = true | false | "unknown";

/**
 * The host's own private-net IP, or `null` when the env cannot establish an
 * identity: unset, empty/whitespace-only, or the literal `0.0.0.0` wildcard
 * (a bind address, never an identity — the SOLEUR_PROXY_BIND trap the T2
 * re-ruling corrected). `null` maps to the `"unknown"` refuse path.
 */
export function readHostPrivateIp(
  raw: string | undefined = process.env[HOST_PRIVATE_IP_ENV],
): string | null {
  const ip = raw?.trim();
  if (!ip || ip === "0.0.0.0") return null;
  return ip;
}

/**
 * `true` when the host's private IP equals the exec pin, `false` when it is
 * established and different, `"unknown"` when no identity can be established
 * (unset / empty / `0.0.0.0`). `"unknown"` is NOT `false`: the caller must
 * refuse rather than forward, because an unidentified host that guessed
 * "not exec" would forward to itself forever or misroute a call it owns.
 */
export function isExecHost(
  execHostPrivateIp: string,
  raw: string | undefined = process.env[HOST_PRIVATE_IP_ENV],
): HostExecIdentity {
  const ip = readHostPrivateIp(raw);
  if (ip === null) return "unknown";
  return ip === execHostPrivateIp;
}
