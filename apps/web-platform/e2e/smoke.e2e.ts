import { test, expect } from "@playwright/test";

/**
 * Extract the nonce from a CSP header string.
 * CSP format: "... script-src ... 'nonce-<base64>' ..."
 */
function extractNonceFromCsp(csp: string): string | null {
  const match = csp.match(/'nonce-([^']+)'/);
  return match ? match[1] : null;
}

// ---------- CSP Nonce Tests (regression for #1213) ----------

test.describe("CSP nonce propagation", () => {
  test("CSP header contains nonce and strict-dynamic on public pages", async ({
    request,
  }) => {
    // Use API request to check headers without rendering (avoids CSS compilation issues)
    const response = await request.get("/login");
    const csp = response.headers()["content-security-policy"];

    expect(csp).toBeTruthy();
    expect(csp).toContain("strict-dynamic");

    const nonce = extractNonceFromCsp(csp!);
    expect(nonce).toBeTruthy();
    expect(nonce!.length).toBeGreaterThan(0);
  });

  test("nonce changes between requests (not cached)", async ({ request }) => {
    const response1 = await request.get("/login");
    const csp1 = response1.headers()["content-security-policy"]!;
    const nonce1 = extractNonceFromCsp(csp1);

    const response2 = await request.get("/login");
    const csp2 = response2.headers()["content-security-policy"]!;
    const nonce2 = extractNonceFromCsp(csp2);

    expect(nonce1).toBeTruthy();
    expect(nonce2).toBeTruthy();
    expect(nonce1).not.toBe(nonce2);
  });

  test("nonce in CSP header matches nonce on rendered script tags", async ({
    page,
  }) => {
    const response = await page.goto("/login");
    expect(response).toBeTruthy();

    const csp = response!.headers()["content-security-policy"];
    expect(csp).toBeTruthy();

    const nonce = extractNonceFromCsp(csp!);
    expect(nonce).toBeTruthy();

    // Wait for whatever renders (may be error page in dev if CSS fails)
    await page.waitForLoadState("load");

    // Check that Next.js framework scripts have the nonce attribute.
    // Browsers clear getAttribute("nonce") after parsing to prevent CSS exfiltration,
    // but the .nonce IDL property still returns the original value.
    const scriptNonces = await page.evaluate(() => {
      const scripts = document.querySelectorAll("script[nonce]");
      return Array.from(scripts).map(
        (s) => (s as HTMLScriptElement).nonce || s.getAttribute("nonce"),
      );
    });

    // Framework scripts must carry nonces — if this is 0, nonce propagation is broken
    // (the exact #1213 failure mode)
    expect(scriptNonces.length).toBeGreaterThan(0);
    for (const sNonce of scriptNonces) {
      expect(sNonce).toBe(nonce);
    }
  });

  test("no CSP violations on page load", async ({ page }) => {
    const violations: string[] = [];
    page.on("console", (msg) => {
      const text = msg.text();
      if (text.includes("Refused to")) {
        violations.push(text);
      }
    });

    await page.goto("/login");
    await page.waitForLoadState("load");

    expect(violations).toEqual([]);
  });
});

// ---------- Public Page Smoke Tests ----------

test.describe("public pages", () => {
  test("CSP header contains all hardening directives", async ({ request }) => {
    const response = await request.get("/login");
    const csp = response.headers()["content-security-policy"]!;
    for (const directive of [
      "frame-ancestors 'none'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "upgrade-insecure-requests",
    ]) {
      expect(csp).toContain(directive);
    }
  });

  test("/signup responds with CSP headers", async ({ request }) => {
    const response = await request.get("/signup");
    const csp = response.headers()["content-security-policy"];
    expect(csp).toBeTruthy();
    expect(csp).toContain("nonce-");
  });

  test("CSP connect-src uses x-forwarded-host when present (regression for #1075)", async ({
    request,
  }) => {
    // Simulate proxy forwarding (like Cloudflare): set x-forwarded-host header.
    // The middleware validates this against the origin allowlist via resolveOrigin().
    const response = await request.get("/login", {
      headers: { "x-forwarded-host": "app.soleur.ai" },
    });
    const csp = response.headers()["content-security-policy"]!;
    // In dev mode buildCspHeader uses ws:// (not wss://) but the host should
    // come from x-forwarded-host, not the internal server bind address.
    expect(csp).toContain("ws://app.soleur.ai");
  });

  test("CSP connect-src rejects spoofed x-forwarded-host", async ({
    request,
  }) => {
    // If an attacker bypasses Cloudflare and sends a forged x-forwarded-host,
    // resolveOrigin() rejects it and falls back to the default origin.
    const response = await request.get("/login", {
      headers: { "x-forwarded-host": "evil.com" },
    });
    const csp = response.headers()["content-security-policy"]!;
    expect(csp).not.toContain("evil.com");
  });

  test("/health returns JSON without CSP header", async ({ request }) => {
    const response = await request.get("/health");
    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body.status).toBe("ok");

    const csp = response.headers()["content-security-policy"];
    expect(csp).toBeUndefined();
  });
});

// ---------- Auth Redirect Tests ----------

test.describe("auth redirects", () => {
  test("/dashboard redirects unauthenticated to /login", async ({
    request,
  }) => {
    const response = await request.get("/dashboard", {
      maxRedirects: 0,
    });
    // Middleware returns 307 redirect to /login
    expect(response.status()).toBe(307);
    expect(response.headers()["location"]).toContain("/login");
  });

  test("/setup-key redirects unauthenticated to /login", async ({
    request,
  }) => {
    const response = await request.get("/setup-key", {
      maxRedirects: 0,
    });
    expect(response.status()).toBe(307);
    expect(response.headers()["location"]).toContain("/login");
  });
});
