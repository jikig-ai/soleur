import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "fs";
import { resolve, join } from "path";

/**
 * Negative-space test: every POST route handler in app/api/ must either
 * call validateOrigin or be in the explicit exemption list.
 *
 * Per institutional learning: enumerate the full attack surface when fixing
 * security boundaries. This test prevents new POST routes from being added
 * without CSRF protection.
 */

const EXEMPT_ROUTES = new Set([
  // Stripe webhook uses signature verification, not cookies
  "app/api/webhooks/stripe/route.ts",
]);

describe("CSRF coverage", () => {
  it("every state-mutating route either uses validateOrigin or is explicitly exempt", () => {
    const appDir = resolve(__dirname, "../../app/api");
    const routeFiles = findRouteFiles(appDir);

    const unprotected: string[] = [];
    const mutatingMethodRe = /export\s+(async\s+)?function\s+(POST|DELETE|PUT|PATCH)/;

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      const match = content.match(mutatingMethodRe);
      if (!match) continue;

      const relativePath = filePath
        .split("/apps/web-platform/")[1];

      if (EXEMPT_ROUTES.has(relativePath)) continue;

      // CSRF protection is satisfied either by an inline validateOrigin call
      // OR by proven delegation to the KB helper (scoped to kb routes).
      // "Proven" means the helper must be invoked AND its {ok: false} result
      // must trigger an early return — substring presence alone is too weak
      // (would accept dead imports). See #2245.
      const hasInline = content.includes("validateOrigin");
      const isKbRoute = relativePath.startsWith("app/api/kb/");
      const invokesKbHelper =
        /const\s+\w+\s*=\s*await\s+authenticateAndResolveKbPath\s*\(/.test(
          content,
        );
      const checksKbHelperResult =
        /if\s*\(\s*!\s*\w+\.ok\s*\)\s*return\s+\w+\.response/.test(content);
      const delegatesToKbHelper = isKbRoute && invokesKbHelper && checksKbHelperResult;

      if (!hasInline && !delegatesToKbHelper) {
        unprotected.push(`${relativePath} (${match[2]})`);
      }
    }

    expect(
      unprotected,
      `State-mutating routes missing validateOrigin (add protection or add to EXEMPT_ROUTES with justification): ${unprotected.join(", ")}`,
    ).toEqual([]);
  });
});

function findRouteFiles(dir: string): string[] {
  const results: string[] = [];

  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      results.push(...findRouteFiles(full));
    } else if (entry === "route.ts") {
      results.push(full);
    }
  }

  return results;
}
