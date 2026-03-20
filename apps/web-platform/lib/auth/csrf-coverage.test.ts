import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { resolve } from "path";

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
  it("every POST route either uses validateOrigin or is explicitly exempt", () => {
    const appDir = resolve(__dirname, "../../app/api");
    const routeFiles = findRouteFiles(appDir);

    const unprotected: string[] = [];

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      if (!content.includes("export async function POST")) continue;

      const relativePath = filePath
        .split("/apps/web-platform/")[1];

      if (EXEMPT_ROUTES.has(relativePath)) continue;

      if (!content.includes("validateOrigin")) {
        unprotected.push(relativePath);
      }
    }

    expect(
      unprotected,
      `POST routes missing validateOrigin (add protection or add to EXEMPT_ROUTES with justification): ${unprotected.join(", ")}`,
    ).toEqual([]);
  });
});

function findRouteFiles(dir: string): string[] {
  const { readdirSync, statSync } = require("fs");
  const { join } = require("path");
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
