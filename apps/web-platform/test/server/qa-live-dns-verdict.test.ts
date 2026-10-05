import { describe, expect, it, vi } from "vitest";

// Importing anything under server/inngest/ evaluates client.ts, which throws
// `INNGEST_SIGNING_KEY missing at startup` unless this is set BEFORE the import.
// Hoisted, because vi.mock/vi.hoisted run before module evaluation. Running the
// suite under `doppler run` would inject the key and MASK this — CI has no
// inngest env, so an unguarded import fails at COLLECTION there.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
import { checkDnsPropagated, isGitHubShapedServer } from "@/server/inngest/functions/cron-gh-pages-cert-reissue";

// LIVE observation captured 2026-07-19 against the real zone in its PROXIED
// steady state (the state the routine starts from).
const LIVE_PROXIED = {
  resolved4: ["188.114.96.2", "188.114.97.2"],
  resolve4Error: null,
  resolved6: ["2a06:98c1:3120::2", "2a06:98c1:3121::2"],
  resolve6Error: null,
  acmeApexStatus: 404,
  acmeWwwStatus: 404,
  acmeApexServer: "cloudflare",
  acmeWwwServer: "cloudflare",
  // Measured live on 2026-08-19 via `GET /repos/jikig-ai/soleur/pages/health`
  // while apex+www were proxied — the same reading that finally explained the
  // 2026-08-16 outage. GitHub reports the domain HTTPS-INELIGIBLE purely because
  // it resolves to Cloudflare, with `caa_error: null` and `reason: null`.
  httpsEligibleApex: false,
  httpsEligibleWww: false,
  healthCaaError: null,
};

describe("gate against a LIVE proxied-state observation", () => {
  it("refuses to call the proxied steady state propagated", () => {
    const v = checkDnsPropagated(LIVE_PROXIED);
    expect(v.status).not.toBe("propagated");
  });

  it("the Server header is the real discriminator — status alone is not", () => {
    // Live apex returns 404 from Cloudflare. GitHub Pages ALSO returns 404 for a
    // nonexistent acme-challenge path, so a status-only check cannot separate
    // them. This is why the gate reads the header.
    expect(LIVE_PROXIED.acmeApexStatus).toBe(404);
    expect(isGitHubShapedServer("cloudflare")).toBe(false);
    expect(isGitHubShapedServer("GitHub.com")).toBe(true);
  });

  it("a DNS-only reading of the same zone would pass", () => {
    // What the flip is expected to produce: GitHub anycast, AAAA gone (the live
    // AAAA is Cloudflare's synthetic proxy answer — the zone declares none),
    // GitHub-shaped ACME.
    const v = checkDnsPropagated({
      ...LIVE_PROXIED,
      resolved4: ["185.199.108.153", "185.199.111.153"],
      resolved6: [],
      resolve6Error: "ENODATA",
      acmeApexServer: "GitHub.com",
      acmeWwwServer: "GitHub.com",
      // ‼️ Eligibility must flip too, and it is the SLOW half. GitHub
      // re-evaluates on its own schedule, so in practice this lags the resolver
      // answers by far longer than the DNS records take to propagate. Overriding
      // it here is what makes this case "what a fully-registered flip looks
      // like" rather than "what DNS alone looks like".
      httpsEligibleApex: true,
      httpsEligibleWww: true,
    });
    expect(v.status).toBe("propagated");
  });

  it("DNS alone is NOT enough — the exact state the 2026-08-16 hand-run reached", () => {
    // Records flipped and propagated on both public resolvers, ACME path
    // GitHub-shaped, AAAA gone — every signal the routine had at the time — yet
    // GitHub had not yet marked the domain eligible. The old gate called this
    // "propagated" and marched on to a poll that could never succeed.
    const v = checkDnsPropagated({
      ...LIVE_PROXIED,
      resolved4: ["185.199.108.153", "185.199.111.153"],
      resolved6: [],
      resolve6Error: "ENODATA",
      acmeApexServer: "GitHub.com",
      acmeWwwServer: "GitHub.com",
      // still false — the flip has not registered with GitHub yet
    });
    expect(v.status).toBe("retry");
    expect(v.reason).toContain("is_https_eligible=false");
  });
});
