import { test, expect } from "@playwright/test";

// pyramid-justified: asserts nonce values on RENDERED <script> tags and
// browser console CSP violations — both require a real browser evaluating
// the page; header-only counterparts demoted to test/csp-middleware.test.ts
// (#9855).

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
