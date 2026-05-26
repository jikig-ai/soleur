// #4068 — Unit tests for _predicate-validator.ts (Layer 3 SSRF hardening).
//
// Tests validate the full SSRF defense surface:
//   - URL validation (HTTPS-only, no userinfo, host allowlist, public IP)
//   - IP range classification (unicast, private, loopback, link-local, IPv4-mapped IPv6)
//   - HTTP predicate execution (status 200 pass, non-200 fail)
//   - DNS predicate execution (expected value found → pass)
//   - Predicate YAML parsing (both HTML comment and ## Verification formats)

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) ----------------------------------------

// Mock node:dns promises API — prevent real DNS resolution in tests.
// The SUT uses `dns.promises.lookup`, `dns.promises.resolveTxt`, etc.
const dnsLookupMock = vi.fn();
const dnsResolveTxtMock = vi.fn();
const dnsResolve4Mock = vi.fn();

vi.mock("node:dns", () => ({
  promises: {
    lookup: dnsLookupMock,
    resolveTxt: dnsResolveTxtMock,
    resolve4: dnsResolve4Mock,
  },
}));

// --- Helpers -----------------------------------------------------------------

/** Configure dnsLookupMock to resolve to a specific address */
function mockDnsLookup(address: string) {
  dnsLookupMock.mockResolvedValue({
    address,
    family: address.includes(":") ? 6 : 4,
  });
}

/** Configure dnsLookupMock to fail */
function mockDnsLookupError(message: string) {
  dnsLookupMock.mockRejectedValue(new Error(message));
}

/** Configure dnsResolveTxtMock */
function mockResolveTxt(records: string[][]) {
  dnsResolveTxtMock.mockResolvedValue(records);
}

/** Configure dnsResolve4Mock */
function mockResolve4(addresses: string[]) {
  dnsResolve4Mock.mockResolvedValue(addresses);
}

beforeEach(() => {
  vi.resetModules();
  dnsLookupMock.mockReset();
  dnsResolveTxtMock.mockReset();
  dnsResolve4Mock.mockReset();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

async function importModule() {
  return import("@/server/inngest/functions/_predicate-validator");
}

// =============================================================================
// isPublicIp
// =============================================================================

describe("isPublicIp", () => {
  it("returns true for a public IPv4 address", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("93.184.216.34")).toBe(true); // example.com
  });

  it("returns false for private 10.x.x.x", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("10.0.0.1")).toBe(false);
  });

  it("returns false for private 172.16.x.x", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("172.16.0.1")).toBe(false);
  });

  it("returns false for private 192.168.x.x", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("192.168.1.1")).toBe(false);
  });

  it("returns false for loopback 127.0.0.1", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("127.0.0.1")).toBe(false);
  });

  it("returns false for IPv6 loopback ::1", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("::1")).toBe(false);
  });

  it("returns false for link-local 169.254.x.x", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("169.254.169.254")).toBe(false);
  });

  it("returns false for IPv6 link-local fe80::", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("fe80::1")).toBe(false);
  });

  it("returns false for IPv4-mapped IPv6 ::ffff:127.0.0.1", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("::ffff:127.0.0.1")).toBe(false);
  });

  it("returns false for IPv4-mapped IPv6 ::ffff:10.0.0.1", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("::ffff:10.0.0.1")).toBe(false);
  });

  it("returns false for invalid/malformed IP", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("not-an-ip")).toBe(false);
  });

  it("returns false for unspecified 0.0.0.0", async () => {
    const { isPublicIp } = await importModule();
    expect(isPublicIp("0.0.0.0")).toBe(false);
  });
});

// =============================================================================
// validatePredicateUrl
// =============================================================================

describe("validatePredicateUrl", () => {
  it("passes for HTTPS URL with allowed host and public IP", async () => {
    const { validatePredicateUrl } = await importModule();
    mockDnsLookup("93.184.216.34"); // public IP

    const result = await validatePredicateUrl("https://app.soleur.ai/health");
    expect(result.valid).toBe(true);
    expect(result.reason).toBeUndefined();
  });

  it("rejects non-HTTPS URL", async () => {
    const { validatePredicateUrl } = await importModule();

    const result = await validatePredicateUrl("http://app.soleur.ai/health");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("HTTPS");
  });

  it("rejects URL with userinfo", async () => {
    const { validatePredicateUrl } = await importModule();

    const result = await validatePredicateUrl("https://admin:pass@app.soleur.ai/health");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("userinfo");
  });

  it("rejects host NOT in allowlist", async () => {
    const { validatePredicateUrl } = await importModule();

    const result = await validatePredicateUrl("https://evil.example.com/probe");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("not in allowlist");
  });

  it("rejects when DNS resolves to private IP", async () => {
    const { validatePredicateUrl } = await importModule();
    mockDnsLookup("10.0.0.1"); // private IP

    const result = await validatePredicateUrl("https://app.soleur.ai/health");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("not a public unicast");
  });

  it("rejects when DNS resolves to loopback", async () => {
    const { validatePredicateUrl } = await importModule();
    mockDnsLookup("127.0.0.1");

    const result = await validatePredicateUrl("https://app.soleur.ai/health");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("not a public unicast");
  });

  it("rejects when DNS resolves to link-local (169.254.x.x)", async () => {
    const { validatePredicateUrl } = await importModule();
    mockDnsLookup("169.254.169.254");

    const result = await validatePredicateUrl("https://app.soleur.ai/health");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("not a public unicast");
  });

  it("rejects when DNS lookup fails", async () => {
    const { validatePredicateUrl } = await importModule();
    mockDnsLookupError("ENOTFOUND");

    const result = await validatePredicateUrl("https://app.soleur.ai/health");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("DNS lookup failed");
  });

  it("rejects malformed URL", async () => {
    const { validatePredicateUrl } = await importModule();

    const result = await validatePredicateUrl("not-a-url");
    expect(result.valid).toBe(false);
    expect(result.reason).toContain("Malformed URL");
  });

  it("allows api.github.com", async () => {
    const { validatePredicateUrl } = await importModule();
    mockDnsLookup("140.82.121.5");

    const result = await validatePredicateUrl("https://api.github.com/repos/jikig-ai/soleur");
    expect(result.valid).toBe(true);
  });

  it("allows api.doppler.com", async () => {
    const { validatePredicateUrl } = await importModule();
    mockDnsLookup("104.26.6.12");

    const result = await validatePredicateUrl("https://api.doppler.com/v3/projects");
    expect(result.valid).toBe(true);
  });
});

// =============================================================================
// executeHttpPredicate
// =============================================================================

describe("executeHttpPredicate", () => {
  it("returns passed=true for HTTP 200", async () => {
    const { executeHttpPredicate } = await importModule();
    vi.stubGlobal("fetch", vi.fn(async () => new Response("OK", { status: 200 })));

    const result = await executeHttpPredicate("https://app.soleur.ai/health");
    expect(result.passed).toBe(true);
    expect(result.statusCode).toBe(200);
  });

  it("returns passed=false for HTTP 404", async () => {
    const { executeHttpPredicate } = await importModule();
    vi.stubGlobal("fetch", vi.fn(async () => new Response("Not Found", { status: 404 })));

    const result = await executeHttpPredicate("https://app.soleur.ai/missing");
    expect(result.passed).toBe(false);
    expect(result.statusCode).toBe(404);
  });

  it("returns passed=false for HTTP 500", async () => {
    const { executeHttpPredicate } = await importModule();
    vi.stubGlobal("fetch", vi.fn(async () => new Response("Error", { status: 500 })));

    const result = await executeHttpPredicate("https://app.soleur.ai/error");
    expect(result.passed).toBe(false);
    expect(result.statusCode).toBe(500);
  });

  it("returns passed=false on fetch error", async () => {
    const { executeHttpPredicate } = await importModule();
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("network error"); }));

    const result = await executeHttpPredicate("https://app.soleur.ai/health");
    expect(result.passed).toBe(false);
    expect(result.statusCode).toBeNull();
    expect(result.error).toContain("network error");
  });

  it("uses redirect: error", async () => {
    const { executeHttpPredicate } = await importModule();
    const fetchMock = vi.fn(async () => new Response("OK", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await executeHttpPredicate("https://app.soleur.ai/health");
    expect(fetchMock).toHaveBeenCalledWith(
      "https://app.soleur.ai/health",
      expect.objectContaining({ redirect: "error" }),
    );
  });
});

// =============================================================================
// executeDnsPredicate
// =============================================================================

describe("executeDnsPredicate", () => {
  it("dns-txt: passes when expected string found", async () => {
    const { executeDnsPredicate } = await importModule();
    mockResolveTxt([["v=spf1 include:_spf.google.com ~all"]]);

    const result = await executeDnsPredicate("dns-txt", "example.com", "_spf.google.com");
    expect(result.passed).toBe(true);
    expect(result.result).toContain("v=spf1 include:_spf.google.com ~all");
  });

  it("dns-txt: fails when expected string not found", async () => {
    const { executeDnsPredicate } = await importModule();
    mockResolveTxt([["v=spf1 ~all"]]);

    const result = await executeDnsPredicate("dns-txt", "example.com", "not-there");
    expect(result.passed).toBe(false);
  });

  it("dns-a: passes when expected IP found", async () => {
    const { executeDnsPredicate } = await importModule();
    mockResolve4(["93.184.216.34"]);

    const result = await executeDnsPredicate("dns-a", "example.com", "93.184.216.34");
    expect(result.passed).toBe(true);
    expect(result.result).toContain("93.184.216.34");
  });

  it("dns-a: fails when expected IP not found", async () => {
    const { executeDnsPredicate } = await importModule();
    mockResolve4(["93.184.216.34"]);

    const result = await executeDnsPredicate("dns-a", "example.com", "1.2.3.4");
    expect(result.passed).toBe(false);
  });
});

// =============================================================================
// parsePredicateYaml
// =============================================================================

describe("parsePredicateYaml", () => {
  it("parses HTML comment format", async () => {
    const { parsePredicateYaml } = await importModule();
    const body = `
Some issue text.
<!-- soleur:followthrough
type: http-200
url: https://app.soleur.ai/health
sla_business_days: 3
-->
More text.`;

    const result = parsePredicateYaml(body, 42, "Test issue");
    expect(result).not.toBeNull();
    expect(result!.type).toBe("http-200");
    expect(result!.url).toBe("https://app.soleur.ai/health");
    expect(result!.slaBusinessDays).toBe(3);
    expect(result!.issueNumber).toBe(42);
  });

  it("parses ## Verification YAML code block format", async () => {
    const { parsePredicateYaml } = await importModule();
    const body = `
## Verification

\`\`\`yaml
type: dns-txt
domain: example.com
expected: verify-123
sla_business_days: 10
\`\`\`
`;

    const result = parsePredicateYaml(body, 7, "DNS check");
    expect(result).not.toBeNull();
    expect(result!.type).toBe("dns-txt");
    expect(result!.domain).toBe("example.com");
    expect(result!.expected).toBe("verify-123");
    expect(result!.slaBusinessDays).toBe(10);
  });

  it("returns null when no predicate block found", async () => {
    const { parsePredicateYaml } = await importModule();
    const body = "Just a normal issue body with no predicates.";

    const result = parsePredicateYaml(body, 1, "No predicate");
    expect(result).toBeNull();
  });

  it("falls back to manual for unrecognized type", async () => {
    const { parsePredicateYaml } = await importModule();
    const body = `<!-- soleur:followthrough type: unknown-type -->`;

    const result = parsePredicateYaml(body, 1, "Unknown type");
    expect(result).not.toBeNull();
    expect(result!.type).toBe("manual");
  });

  it("defaults sla_business_days to 5", async () => {
    const { parsePredicateYaml } = await importModule();
    const body = `<!-- soleur:followthrough type: manual -->`;

    const result = parsePredicateYaml(body, 1, "Default SLA");
    expect(result).not.toBeNull();
    expect(result!.slaBusinessDays).toBe(5);
  });

  it("returns null for empty body", async () => {
    const { parsePredicateYaml } = await importModule();
    expect(parsePredicateYaml("", 1, "Empty")).toBeNull();
  });
});

// =============================================================================
// validateAndExecutePredicates (orchestrator)
// =============================================================================

describe("validateAndExecutePredicates", () => {
  it("handles http-200 predicate with valid URL", async () => {
    const { validateAndExecutePredicates } = await importModule();
    mockDnsLookup("93.184.216.34");
    vi.stubGlobal("fetch", vi.fn(async () => new Response("OK", { status: 200 })));

    const results = await validateAndExecutePredicates([
      {
        number: 42,
        title: "Check health",
        body: `<!-- soleur:followthrough type: http-200 url: https://app.soleur.ai/health -->`,
      },
    ]);

    expect(results).toHaveLength(1);
    expect(results[0].type).toBe("http-200");
    expect(results[0].validationResult?.valid).toBe(true);
    expect((results[0].executionResult as { passed: boolean }).passed).toBe(true);
  });

  it("blocks http-200 predicate with disallowed host", async () => {
    const { validateAndExecutePredicates } = await importModule();

    const results = await validateAndExecutePredicates([
      {
        number: 43,
        title: "Evil check",
        body: `<!-- soleur:followthrough type: http-200 url: https://evil.example.com/probe -->`,
      },
    ]);

    expect(results).toHaveLength(1);
    expect(results[0].validationResult?.valid).toBe(false);
    expect(results[0].executionResult).toBeUndefined();
  });

  it("handles manual predicate (skipped)", async () => {
    const { validateAndExecutePredicates } = await importModule();

    const results = await validateAndExecutePredicates([
      {
        number: 44,
        title: "Manual check",
        body: `<!-- soleur:followthrough type: manual -->`,
      },
    ]);

    expect(results).toHaveLength(1);
    expect(results[0].skipped).toBe(true);
    expect(results[0].skipReason).toContain("handled by agent");
  });

  it("handles issue with no predicate block", async () => {
    const { validateAndExecutePredicates } = await importModule();

    const results = await validateAndExecutePredicates([
      {
        number: 45,
        title: "No predicate",
        body: "Just a body with no predicate.",
      },
    ]);

    expect(results).toHaveLength(1);
    expect(results[0].skipped).toBe(true);
    expect(results[0].skipReason).toContain("No predicate block");
  });

  it("handles dns-a predicate with allowed domain", async () => {
    const { validateAndExecutePredicates } = await importModule();
    mockResolve4(["140.82.121.6"]);

    const results = await validateAndExecutePredicates([
      {
        number: 46,
        title: "DNS A check",
        body: `<!-- soleur:followthrough
type: dns-a
domain: api.github.com
expected: 140.82.121.6
-->`,
      },
    ]);

    expect(results).toHaveLength(1);
    expect(results[0].type).toBe("dns-a");
    expect((results[0].executionResult as { passed: boolean }).passed).toBe(true);
  });

  it("rejects dns-a predicate with non-allowlisted domain", async () => {
    const { validateAndExecutePredicates } = await importModule();

    const results = await validateAndExecutePredicates([
      {
        number: 47,
        title: "DNS A blocked",
        body: `<!-- soleur:followthrough
type: dns-a
domain: internal.corp.local
expected: 10.0.0.1
-->`,
      },
    ]);

    expect(results).toHaveLength(1);
    expect(results[0].skipped).toBe(true);
    expect(results[0].skipReason).toContain("not in allowlist");
  });
});

// =============================================================================
// formatPredicateResults
// =============================================================================

describe("formatPredicateResults", () => {
  it("formats empty results", async () => {
    const { formatPredicateResults } = await importModule();
    const output = formatPredicateResults([]);
    expect(output).toContain("No predicate results");
  });

  it("formats passed HTTP predicate", async () => {
    const { formatPredicateResults } = await importModule();
    const output = formatPredicateResults([
      {
        issueNumber: 42,
        issueTitle: "Health check",
        type: "http-200",
        validationResult: { valid: true },
        executionResult: { passed: true, statusCode: 200 },
      },
    ]);
    expect(output).toContain("PASSED");
    expect(output).toContain("#42");
    expect(output).toContain("HTTP 200");
  });

  it("formats blocked predicate", async () => {
    const { formatPredicateResults } = await importModule();
    const output = formatPredicateResults([
      {
        issueNumber: 43,
        issueTitle: "Evil check",
        type: "http-200",
        validationResult: { valid: false, reason: "Host not in allowlist" },
      },
    ]);
    expect(output).toContain("BLOCKED");
    expect(output).toContain("Host not in allowlist");
  });

  it("formats skipped predicate", async () => {
    const { formatPredicateResults } = await importModule();
    const output = formatPredicateResults([
      {
        issueNumber: 44,
        issueTitle: "Manual",
        type: "manual",
        skipped: true,
        skipReason: "handled by agent",
      },
    ]);
    expect(output).toContain("SKIPPED");
    expect(output).toContain("handled by agent");
  });
});

// =============================================================================
// ALLOWED_PREDICATE_HOSTS
// =============================================================================

describe("ALLOWED_PREDICATE_HOSTS", () => {
  it("contains the expected hosts", async () => {
    const { ALLOWED_PREDICATE_HOSTS } = await importModule();
    expect(ALLOWED_PREDICATE_HOSTS.has("app.soleur.ai")).toBe(true);
    expect(ALLOWED_PREDICATE_HOSTS.has("api.github.com")).toBe(true);
    expect(ALLOWED_PREDICATE_HOSTS.has("api.doppler.com")).toBe(true);
  });

  it("does not contain arbitrary hosts", async () => {
    const { ALLOWED_PREDICATE_HOSTS } = await importModule();
    expect(ALLOWED_PREDICATE_HOSTS.has("evil.com")).toBe(false);
    expect(ALLOWED_PREDICATE_HOSTS.has("localhost")).toBe(false);
    expect(ALLOWED_PREDICATE_HOSTS.has("127.0.0.1")).toBe(false);
  });
});
