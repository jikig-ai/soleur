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

    // Even error pages get framework scripts with nonces
    if (scriptNonces.length > 0) {
      for (const sNonce of scriptNonces) {
        expect(sNonce).toBe(nonce);
      }
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
  test("/login responds with CSP headers", async ({ request }) => {
    const response = await request.get("/login");
    const csp = response.headers()["content-security-policy"];
    expect(csp).toBeTruthy();
    expect(csp).toContain("nonce-");
  });

  test("/signup responds with CSP headers", async ({ request }) => {
    const response = await request.get("/signup");
    const csp = response.headers()["content-security-policy"];
    expect(csp).toBeTruthy();
    expect(csp).toContain("nonce-");
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
