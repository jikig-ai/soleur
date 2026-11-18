// #12585 — the pure SandboxNetworkAccess decision (server/sandbox-network-access.ts). The bypass-shape cases that matter
// at the entry point are re-driven through createCanUseTool in permission-callback-sandbox-network.test.ts.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  decideSandboxNetworkAccess,
  noProxyMatches,
  normalizeHost,
  SANDBOX_NETWORK_ACCESS_TOOL,
  sandboxNetworkDenyMessage,
  WEB_EGRESS_NO_PROXY,
} from "../server/sandbox-network-access";

const LIVE = { live: true };
const decide = (host: unknown) => decideSandboxNetworkAccess({ host }, LIVE);

// Today's literal, written out (CTO T1): drift in the constant reds here, drift in agent-env reds agent-env's pin.
const NO_PROXY_LITERAL =
  "localhost,127.0.0.1,::1,api.anthropic.com,mcp-proxy.anthropic.com,statsig.anthropic.com,*.sentry.io,*.datadoghq.com,*.supabase.co,*.supabase.in,api.stripe.com,github.com,*.github.com";

describe("sandbox-network-access: module contract", () => {
  it("names the SDK request and carries the NO_PROXY literal byte-identical", () => {
    expect(SANDBOX_NETWORK_ACCESS_TOOL).toBe("SandboxNetworkAccess");
    expect(WEB_EGRESS_NO_PROXY).toBe(NO_PROXY_LITERAL);
  });

  it("imports only node:net (the spike driver loads it outside the app; agent-env imports it) (AC10, CTO T17)", () => {
    const src = readFileSync(join(__dirname, "..", "server", "sandbox-network-access.ts"), "utf8");
    const specifiers = [...src.matchAll(/^\s*(?:import|export)\b[^;]*?\bfrom\s+["']([^"']+)["']/gm)].map((m) => m[1]);
    const dynamic = [...src.matchAll(/\b(?:import|require)\(\s*["']([^"']+)["']/g)].map((m) => m[1]);
    const bare = [...src.matchAll(/^\s*import\s+["']([^"']+)["']/gm)].map((m) => m[1]);
    expect(specifiers).toEqual(["node:net"]);
    expect(dynamic).toEqual([]);
    expect(bare).toEqual([]);
  });
});

describe("decideSandboxNetworkAccess: decision order", () => {
  it("no forwarder handle => not-entitled, before anything about the host", () => {
    expect(decideSandboxNetworkAccess({ host: "example.com" }, undefined)).toEqual({ behavior: "deny", reason: "not-entitled" });
    expect(decideSandboxNetworkAccess("garbage", undefined).reason).toBe("not-entitled");
  });

  it("a dead forwarder => egress-not-running, before the host checks", () => {
    expect(decideSandboxNetworkAccess({ host: "localhost" }, { live: false })).toEqual({
      behavior: "deny",
      reason: "egress-not-running",
    });
  });

  it("an ordinary DNS host and a public IP literal => gateway-unverified (row 6': the SDK caches allows, Phase 1a)", () => {
    for (const host of ["example.com", "EXAMPLE.COM.", "198.51.100.1", "2001:db8::1", "xn--supabase-9ta.co", "169.254.169.254"]) {
      expect(decide(host), host).toEqual({ behavior: "deny", reason: "gateway-unverified" });
    }
  });

  it("never returns allow, for any input shape (no allow branch ships in this PR)", () => {
    const inputs: unknown[] = [{ host: "example.com" }, { host: "a.b" }, {}, null, [], "x", 1];
    for (const input of inputs) {
      for (const egress of [undefined, { live: false }, LIVE]) {
        expect(decideSandboxNetworkAccess(input, egress).behavior).toBe("deny");
      }
    }
  });
});

describe("decideSandboxNetworkAccess: input shape (deny without throwing)", () => {
  it.each([
    ["extra key", { host: "example.com", port: 443 }],
    ["no host", {}],
    ["non-string host", { host: 7 }],
    ["array host", { host: ["example.com"] }],
    ["String object", { host: new String("example.com") }],
    ["empty host", { host: "" }],
    ["array input", ["example.com"]],
    ["null input", null],
    ["string input", "example.com"],
    ["class instance", new (class { host = "example.com"; })()],
  ])("%s => malformed-host", (_label, input) => {
    expect(() => decideSandboxNetworkAccess(input, LIVE)).not.toThrow();
    expect(decideSandboxNetworkAccess(input, LIVE).reason).toBe("malformed-host");
  });
});

describe("decideSandboxNetworkAccess: malformed hosts (AC27, CTO D7)", () => {
  it.each([
    "host:443",
    "localhost:80",
    "[::1]:443",
    "user@127.0.0.1",
    "a/b",
    "exa mple.com",
    "example.com\n",
    "\texample.com",
    "::1%lo",
    "fe80::1%eth0",
    "2130706433",
    "0x7f000001",
    "0x7F.0.0.0x1",
    "0177.0.0.01",
    "127.1",
    "localhost..",
    ".supabase.co",
    "-bad.example",
    "bad-.example",
    "a..b",
    "[example.com]",
    "[::1",
    "::1]",
    "x．supabase．co",
    "Kelvin.example",
    "ex_ample.com",
  ])("%j => malformed-host", (host) => {
    expect(decide(host).reason).toBe("malformed-host");
  });
});

describe("decideSandboxNetworkAccess: loopback and unspecified literals (AC3)", () => {
  it.each([
    "127.0.0.1",
    "127.0.0.2",
    "127.255.255.254",
    "0.0.0.0",
    "0.1.2.3",
    "::1",
    "[::1]",
    "[::1].",
    "0:0::1",
    "0:0:0:0:0:0:0:1",
    "::0001",
    "::",
    "[::]",
    "::ffff:127.0.0.1",
    "[::ffff:127.0.0.1]",
    "::ffff:7f00:1",
    "::127.0.0.1",
    "64:ff9b::7f00:1",
    "::ffff:0.0.0.0",
  ])("%j => loopback-literal", (host) => {
    expect(decide(host).reason).toBe("loopback-literal");
  });
});

describe("decideSandboxNetworkAccess: NO_PROXY matches (AC3, AC19)", () => {
  it.each([
    ["localhost", "localhost"],
    ["LOCALHOST.", "localhost"],
    ["api.anthropic.com", "api.anthropic.com"],
    ["API.Anthropic.COM.", "api.anthropic.com"],
    ["mcp-proxy.anthropic.com", "mcp-proxy.anthropic.com"],
    ["statsig.anthropic.com", "statsig.anthropic.com"],
    ["o1.ingest.sentry.io", "*.sentry.io"],
    ["sentry.io", "*.sentry.io"],
    ["x.datadoghq.com", "*.datadoghq.com"],
    ["x.supabase.co", "*.supabase.co"],
    ["supabase.co", "*.supabase.co"],
    ["a.b.supabase.in", "*.supabase.in"],
    ["api.stripe.com", "api.stripe.com"],
    // AC19 (CTO T19): an entitled session with no GitHub token still has github.com in NO_PROXY: denied, unchanged.
    ["github.com", "github.com"],
    ["api.github.com", "*.github.com"],
  ])("%j => no-proxy-match on %j", (host, entry) => {
    expect(decide(host)).toEqual({ behavior: "deny", reason: "no-proxy-match", matchedEntry: entry });
  });

  it("near-misses are not NO_PROXY matches (they are ordinary hosts)", () => {
    for (const host of ["notsupabase.co", "supabase.co.evil.example", "stripe.com", "anthropic.com", "xn--supabase-9ta.co"]) {
      expect(decide(host).reason, host).toBe("gateway-unverified");
    }
  });
});

describe("noProxyMatches", () => {
  it("supports exact, *.x, .x (apex included), * and bracketed IPv6 entries", () => {
    expect(noProxyMatches("a.example", ".example")).toBe(".example");
    expect(noProxyMatches("example", ".example")).toBe(".example");
    expect(noProxyMatches("anything", "foo, * ")).toBe("*");
    expect(noProxyMatches("::1", "[::1]")).toBe("[::1]");
    expect(noProxyMatches("example.com", "")).toBeUndefined();
    expect(noProxyMatches("ample.com", "example.com")).toBeUndefined();
  });
});

describe("property sweep: no NO_PROXY or loopback spelling ever reaches gateway-unverified (AC3)", () => {
  // Enumerated, not random: every entry of the literal crossed with the case / trailing-dot / bracket / port /
  // subdomain spellings an attacker controls, plus the loopback spellings.
  const entries = WEB_EGRESS_NO_PROXY.split(",");
  const spellings = (h: string): string[] => {
    const out = new Set<string>([h, h.toUpperCase(), `${h}.`, `${h.toUpperCase()}.`, `${h}:443`, `${h}:80`, ` ${h}`, `${h} `]);
    if (h.includes(":")) for (const v of [`[${h}]`, `[${h}]:443`, `[${h}].`]) out.add(v);
    return [...out];
  };
  const hosts: string[] = [];
  for (const e of entries) {
    const base = e.startsWith("*.") ? e.slice(2) : e;
    hosts.push(...spellings(base));
    if (e.startsWith("*.")) hosts.push(...spellings(`a.${base}`), ...spellings(`a.b.${base}`));
  }
  for (const lb of ["127.0.0.1", "127.9.9.9", "0.0.0.0", "::1", "::", "::ffff:127.0.0.1", "0:0:0:0:0:0:0:1", "localhost"]) {
    hosts.push(...spellings(lb));
  }

  it(`covers ${hosts.length} spellings, none reaches gateway-unverified`, () => {
    expect(hosts.length).toBeGreaterThan(150);
    const escaped = hosts.filter((h) => decide(h).reason === "gateway-unverified");
    expect(escaped).toEqual([]);
  });
});

describe("normalizeHost", () => {
  it("canonicalizes IPv6 and lowercases DNS names", () => {
    expect(normalizeHost("[0:0:0:0:0:0:0:1]")).toEqual({ kind: "ipv6", host: "::1" });
    expect(normalizeHost("Example.COM.")).toEqual({ kind: "dns", host: "example.com" });
    expect(normalizeHost("198.51.100.1")).toEqual({ kind: "ipv4", host: "198.51.100.1" });
    expect(normalizeHost("example.com..")).toBeNull();
  });
});

describe("sandboxNetworkDenyMessage (CPO ruling, keyed on reason and granted)", () => {
  const reasons = ["not-entitled", "egress-not-running", "malformed-host", "loopback-literal", "no-proxy-match", "gateway-unverified"] as const;

  it("is static, host-free, under 200 characters and never the deny-default text", () => {
    for (const r of reasons) {
      for (const g of [true, false]) {
        const m = sandboxNetworkDenyMessage(r, g);
        expect(m.length).toBeLessThan(200);
        expect(m).not.toBe("Tool not permitted in this environment");
        expect(m).not.toMatch(/example|supabase|localhost|127\./i);
      }
    }
  });

  it("tells a degraded granted session apart from an ungranted one", () => {
    expect(sandboxNetworkDenyMessage("not-entitled", false)).toBe(
      "Network access from sandboxed commands is not available in this session.",
    );
    expect(sandboxNetworkDenyMessage("not-entitled", true)).toMatch(/web access isn't working in this session/);
    expect(sandboxNetworkDenyMessage("egress-not-running", true)).toBe(sandboxNetworkDenyMessage("not-entitled", true));
    expect(sandboxNetworkDenyMessage("gateway-unverified", true)).toMatch(/`WebFetch` tool/);
    expect(sandboxNetworkDenyMessage("no-proxy-match", true)).toBe("Commands can't connect to this host from this session.");
  });

  it("CPO C1/C3: no string names WebSearch or claims web access is currently on; WebFetch only when granted", () => {
    const reasons = ["not-entitled", "egress-not-running", "malformed-host", "loopback-literal", "no-proxy-match", "gateway-unverified"] as const;
    for (const r of reasons) {
      for (const g of [true, false]) {
        for (const rv of [true, false]) {
          const m = sandboxNetworkDenyMessage(r, g, rv);
          expect(m).not.toMatch(/web search|WebSearch|web access is on|with web access on/i);
          if (!g) expect(m).not.toMatch(/WebFetch/);
        }
      }
    }
  });

  it("RFC 1035 label limit: a 64-octet label is malformed, a 63-octet one is a name", () => {
    expect(normalizeHost(`${"a".repeat(64)}.com`)).toBeNull();
    expect(normalizeHost(`${"a".repeat(63)}.com`)).toEqual({ kind: "dns", host: `${"a".repeat(63)}.com` });
  });

  it("CPO C2: a revoked session says web access was turned off, whatever the reason", () => {
    const revoked = "Web access was turned off for this workspace, so commands can't reach the internet. Retrying won't help.";
    expect(sandboxNetworkDenyMessage("egress-not-running", false, true)).toBe(revoked);
    expect(sandboxNetworkDenyMessage("gateway-unverified", true, true)).toBe(revoked);
  });
});
