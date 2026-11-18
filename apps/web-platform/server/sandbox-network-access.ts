// #12585 — the decision for the Agent SDK's `SandboxNetworkAccess` permission request.
//
// With `network.allowedDomains` empty (or GitHub-only), the SDK's host-side sandbox proxy asks `canUseTool` once per
// host a sandboxed command (curl, git, pip...) tries to reach, as the tool name `SandboxNetworkAccess` with input
// `{ host }` (measured on 0.3.321: the key set is exactly ["host"], the host bare, without a port). Before this module
// that request fell to the deny-default branch ("Tool not permitted in this environment"), with no reason and no signal.
//
// DENY-ALL BY MEASUREMENT (plan Phase 1a, row 6'). Measured on 0.3.321: an allowed host's traffic does transit the egress
// forwarder with the session credential, but the SDK caches a per-host allow for the whole CLI session, so revoking web
// access (toggle-off, forwarder exit) is never re-asked for a host already allowed. The plan pre-decided that a cached
// allow means only deny-all is safe, so an entitled, live session with a valid host is denied `gateway-unverified`. The
// real allow arm is the follow-up named in ADR-278's 2026-11-18 addendum.
//
// IMPORT-FREE except node:net (pinned by test): `agent-env.ts` imports WEB_EGRESS_NO_PROXY from here, and the
// egress-injector spike driver imports this file outside the app, so no logger, no Sentry, no `@/` alias.

import net from "node:net";

export const SANDBOX_NETWORK_ACCESS_TOOL = "SandboxNetworkAccess";

/**
 * The NO_PROXY list of an egress-proxied session (moved byte-identical out of `buildAgentEnv`). Hosts here bypass the
 * tenant gateway, so a sandboxed request to one of them can never be attributed or filtered there: the arm denies them.
 */
export const WEB_EGRESS_NO_PROXY =
  "localhost,127.0.0.1,::1,api.anthropic.com,mcp-proxy.anthropic.com,statsig.anthropic.com,*.sentry.io,*.datadoghq.com,*.supabase.co,*.supabase.in,api.stripe.com,github.com,*.github.com";

export type SandboxNetworkReason =
  | "not-entitled"
  | "egress-not-running"
  | "malformed-host"
  | "loopback-literal"
  | "no-proxy-match"
  | "gateway-unverified";

export interface SandboxNetworkDecision {
  behavior: "deny";
  reason: SandboxNetworkReason;
  /** The NO_PROXY ENTRY that matched (a list literal such as `*.supabase.co`), never the requested host. */
  matchedEntry?: string;
}

// Characters a host may carry before any transformation: ASCII letters, digits, dot, hyphen, IPv6 brackets and colons.
// Checked on the RAW value, before lowercasing ("\u212A".toLowerCase() === "k", the Kelvin sign); IDN must arrive as punycode.
const RAW_HOST = /^[A-Za-z0-9.\-[\]:]+$/;
// RFC 1035: 1-63 octets per label.
const LDH_LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
// RFC 1035's 253-octet name, plus a trailing dot or the two IPv6 brackets.
const MAX_RAW_HOST_LENGTH = 253 + 2;
// WHATWG "ends in a number": a last label of this shape makes a URL parser read the whole host as IPv4 (2130706433, 127.1).
const NUMERIC_LABEL = /^(?:0x[0-9a-f]*|[0-9]+)$/;

type Normalized = { kind: "dns" | "ipv4" | "ipv6"; host: string } | null;

/** Normalize a raw host, or null for anything that is not a plain DNS name or IP literal (deny `malformed-host`). */
export function normalizeHost(raw: unknown): Normalized {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > MAX_RAW_HOST_LENGTH || !RAW_HOST.test(raw)) return null;
  let h = raw.endsWith(".") ? raw.slice(0, -1) : raw;
  if (h.startsWith("[") || h.endsWith("]")) {
    if (!(h.startsWith("[") && h.endsWith("]"))) return null;
    h = h.slice(1, -1);
    if (!net.isIPv6(h)) return null;
  }
  // `[::1]:443` never reaches here: it does not end in "]", so the bracket check above rejects it.
  if (h.includes(":")) {
    // Any colon outside a valid IPv6 literal (host:443) is malformed; no port is ever stripped (CTO D7).
    if (!net.isIPv6(h)) return null;
    return { kind: "ipv6", host: new URL(`http://[${h}]`).hostname.slice(1, -1) };
  }
  h = h.toLowerCase();
  if (net.isIPv4(h)) return { kind: "ipv4", host: h };
  const labels = h.split(".");
  if (labels.some((l) => !LDH_LABEL.test(l))) return null; // also catches `localhost..` and a leading dot
  if (NUMERIC_LABEL.test(labels[labels.length - 1])) return null;
  return { kind: "dns", host: h };
}

function ipv4IsLoopbackOrUnspecified(v4: string): boolean {
  const first = Number(v4.split(".")[0]);
  return first === 127 || first === 0;
}

/** Expand a canonical IPv6 literal to eight 16-bit groups. */
function ipv6Groups(v6: string): number[] {
  const [head, tail] = v6.includes("::") ? v6.split("::") : [v6, undefined];
  const h = head ? head.split(":") : [];
  const t = tail ? tail.split(":") : [];
  const fill = tail === undefined ? [] : new Array(8 - h.length - t.length).fill("0");
  return [...h, ...fill, ...t].map((g) => parseInt(g, 16));
}

function ipv6IsLoopbackOrUnspecified(v6: string): boolean {
  const g = ipv6Groups(v6);
  const embedded = () => `${g[6] >> 8}.${g[6] & 0xff}.${g[7] >> 8}.${g[7] & 0xff}`;
  const zero = (from: number, to: number) => g.slice(from, to).every((x) => x === 0);
  if (zero(0, 7) && (g[7] === 0 || g[7] === 1)) return true; // :: and ::1
  if (zero(0, 6)) return ipv4IsLoopbackOrUnspecified(embedded()); // IPv4-compatible ::a.b.c.d
  if (zero(0, 5) && g[5] === 0xffff) return ipv4IsLoopbackOrUnspecified(embedded()); // IPv4-mapped
  if (g[0] === 0x64 && g[1] === 0xff9b && zero(2, 6)) return ipv4IsLoopbackOrUnspecified(embedded()); // NAT64
  return false;
}

/** The first NO_PROXY entry that matches the NORMALIZED host (exact, `*.x` / `.x` including the apex, or `*`). */
export function noProxyMatches(host: string, noProxy: string = WEB_EGRESS_NO_PROXY): string | undefined {
  for (const rawEntry of noProxy.split(",")) {
    const entry = rawEntry.trim();
    if (!entry) continue;
    const e = entry.toLowerCase().replace(/^\[(.*)\]$/, "$1");
    if (e === "*") return entry;
    const suffix = e.startsWith("*.") ? e.slice(2) : e.startsWith(".") ? e.slice(1) : null;
    if (suffix !== null ? host === suffix || host.endsWith(`.${suffix}`) : host === e) return entry;
  }
  return undefined;
}

/**
 * The whole decision order (CTO F10/T2): not-entitled, egress-not-running, malformed-host, loopback-literal,
 * no-proxy-match, then gateway-unverified (row 6': deny-all, see the header). `egress` is undefined when the session has
 * no live forwarder handle; the caller evaluates `isLive()` and passes the boolean.
 */
export function decideSandboxNetworkAccess(
  input: unknown,
  egress: { live: boolean } | undefined,
  noProxy: string = WEB_EGRESS_NO_PROXY,
): SandboxNetworkDecision {
  if (egress === undefined) return { behavior: "deny", reason: "not-entitled" };
  if (!egress.live) return { behavior: "deny", reason: "egress-not-running" };
  const isPlainObject =
    typeof input === "object" && input !== null && !Array.isArray(input) && Object.getPrototypeOf(input) === Object.prototype;
  const keys = isPlainObject ? Object.keys(input as object) : [];
  const normalized = keys.length === 1 && keys[0] === "host" ? normalizeHost((input as { host: unknown }).host) : null;
  if (normalized === null) return { behavior: "deny", reason: "malformed-host" };
  const loopback =
    normalized.kind === "ipv4"
      ? ipv4IsLoopbackOrUnspecified(normalized.host)
      : normalized.kind === "ipv6"
        ? ipv6IsLoopbackOrUnspecified(normalized.host)
        : false;
  if (loopback) return { behavior: "deny", reason: "loopback-literal" };
  const matchedEntry = noProxyMatches(normalized.host, noProxy);
  if (matchedEntry !== undefined) return { behavior: "deny", reason: "no-proxy-match", matchedEntry };
  return { behavior: "deny", reason: "gateway-unverified" };
}

const NOT_AVAILABLE = "Network access from sandboxed commands is not available in this session.";
const REVOKED = "Web access was turned off for this workspace, so commands can't reach the internet. Retrying won't help.";
const DEGRADED =
  "Commands can't reach the internet: web access isn't working in this session. Retrying won't help; let the user know.";
const GATEWAY_UNVERIFIED =
  "Commands can't reach the internet in this session. To read a web page, use the `WebFetch` tool instead. Retrying won't help.";
const HOST_DENIED = "Commands can't connect to this host from this session.";

/**
 * The static, host-free message returned to the model, keyed on (reason, granted, revoked) (CPO rulings, 2026-11-18).
 * `revoked` wins: it is the only state the code knows the toggle position for. `granted` is a session-start snapshot, so
 * no string claims web access is currently on. WebFetch is named only when granted (it is disallowed otherwise).
 */
export function sandboxNetworkDenyMessage(reason: SandboxNetworkReason, granted: boolean, revoked = false): string {
  if (revoked) return REVOKED;
  switch (reason) {
    case "not-entitled":
    case "egress-not-running":
      return granted ? DEGRADED : NOT_AVAILABLE;
    case "gateway-unverified":
      return granted ? GATEWAY_UNVERIFIED : NOT_AVAILABLE;
    case "malformed-host":
    case "loopback-literal":
    case "no-proxy-match":
      return HOST_DENIED;
    default: {
      // Compile-time exhaustiveness; at runtime an unknown reason gets the host copy, never the reason token.
      const unreachable: never = reason;
      void unreachable;
      return HOST_DENIED;
    }
  }
}
