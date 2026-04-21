import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "fs";
import { resolve, join } from "path";

/**
 * Negative-space test: every KB route handler that accepts user-supplied
 * paths must import and use isPathInWorkspace from the sandbox module.
 *
 * This test prevents new KB endpoints from being added without path
 * traversal protection.
 */

describe("KB API security", () => {
  it("content route uses isPathInWorkspace for path validation", () => {
    const contentRoute = resolve(
      __dirname,
      "../app/api/kb/content/[...path]/route.ts",
    );
    const content = readFileSync(contentRoute, "utf-8");

    // The route imports from kb-reader which uses isPathInWorkspace
    expect(content).toContain("readContent");
    expect(content).toContain("KbAccessDeniedError");
  });

  it("kb-reader module imports isPathInWorkspace from sandbox", () => {
    const kbReader = resolve(__dirname, "../server/kb-reader.ts");
    const content = readFileSync(kbReader, "utf-8");

    expect(content).toContain('import { isPathInWorkspace }');
    expect(content).toContain("from \"./sandbox\"");
  });

  it("kb-reader uses kbRoot as containment boundary, not workspacePath", () => {
    const kbReader = resolve(__dirname, "../server/kb-reader.ts");
    const content = readFileSync(kbReader, "utf-8");

    // readContent should call isPathInWorkspace with kbRoot
    expect(content).toContain("isPathInWorkspace(fullPath, kbRoot)");
  });

  it("kb-reader rejects null bytes in paths", () => {
    const kbReader = resolve(__dirname, "../server/kb-reader.ts");
    const content = readFileSync(kbReader, "utf-8");

    expect(content).toContain("\\0");
  });

  it("kb-reader disables gray-matter engine execution", () => {
    const kbReader = resolve(__dirname, "../server/kb-reader.ts");
    const content = readFileSync(kbReader, "utf-8");

    expect(content).toContain("engines: {}");
  });

  it("no KB route handler exposes absolute paths in responses", () => {
    const routeDir = resolve(__dirname, "../app/api/kb");
    const routeFiles = findRouteFiles(routeDir);

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      // Route handlers should not interpolate workspace_path or kbRoot into responses
      expect(content).not.toMatch(
        /NextResponse\.json\([^)]*workspace_path/,
      );
      expect(content).not.toMatch(
        /NextResponse\.json\([^)]*kbRoot/,
      );
    }
  });

  it("all KB route handlers require authentication", () => {
    const routeDir = resolve(__dirname, "../app/api/kb");
    const routeFiles = findRouteFiles(routeDir);

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      const relativePath = filePath.split("/apps/web-platform/")[1];

      // Auth enforcement is satisfied by (a) an inline getUser call, (b) a
      // proven delegation to the shared helper (#2180 — INVOKED AND its
      // {ok: false} result must trigger an early return, per #2245), or
      // (c) wrapping the handler with `withUserRateLimit` (#2510 — the
      // wrapper performs `supabase.auth.getUser()` and 401s unauthenticated
      // callers before the inner handler runs).
      const hasInlineAuth = content.includes("supabase.auth.getUser");
      const invokesHelper =
        /const\s+\w+\s*=\s*await\s+authenticateAndResolveKbPath\s*\(/.test(
          content,
        );
      const checksHelperResult =
        /if\s*\(\s*!\s*\w+\.ok\s*\)\s*return\s+\w+\.response/.test(content);
      const delegatesToHelper = invokesHelper && checksHelperResult;
      // Wrapped export signals the wrapper is doing the auth — must be the
      // exact exported handler, not a bare import or a dead reference.
      const wrapsWithRateLimit =
        /export\s+const\s+(GET|POST|PUT|PATCH|DELETE)\s*=\s*withUserRateLimit\s*\(/.test(
          content,
        );

      expect(
        hasInlineAuth || delegatesToHelper || wrapsWithRateLimit,
        `${relativePath} missing auth check (inline getUser, authenticateAndResolveKbPath, or withUserRateLimit wrap)`,
      ).toBe(true);
    }
  });

  it("all KB route handlers check workspace_status", () => {
    const routeDir = resolve(__dirname, "../app/api/kb");
    const routeFiles = findRouteFiles(routeDir);

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      const relativePath = filePath.split("/apps/web-platform/")[1];

      // Same proven-delegation pattern as the auth check above (#2245).
      // Accept either helper — authenticateAndResolveKbPath (file routes)
      // or resolveUserKbRoot (share/upload, added in #2467 cleanup).
      const hasInline = content.includes("workspace_status");
      const helperName =
        /const\s+\w+\s*=\s*await\s+(authenticateAndResolveKbPath|resolveUserKbRoot)\s*\(/;
      const invokesHelper = helperName.test(content);
      const checksHelperResult =
        /if\s*\(\s*!\s*\w+\.ok\s*\)\s*return\s+\w+\.response/.test(content);
      const delegatesToHelper = invokesHelper && checksHelperResult;

      expect(
        hasInline || delegatesToHelper,
        `${relativePath} missing workspace_status check (inline or proven authenticateAndResolveKbPath / resolveUserKbRoot delegation)`,
      ).toBe(true);
    }
  });

  // Behavioral coverage: searchKb symlink-skip is in test/kb-reader.test.ts.
  // Behavioral coverage: case-insensitive extension match is in test/kb-reader.test.ts
  // (`filename match is case-insensitive on extension`).

  it("kb-route-helpers enforces path containment, symlink rejection, and null-byte guard", () => {
    // Architecture review finding D3: invariants moved to the helper when
    // PR #2235 extracted auth/path-resolution logic. These negative-space
    // assertions follow the code — a future refactor that removes any of
    // these lines fails the test.
    const helper = resolve(__dirname, "../server/kb-route-helpers.ts");
    const content = readFileSync(helper, "utf-8");
    expect(content).toContain("isPathInWorkspace(fullPath, kbRoot)");
    expect(content).toContain("isSymbolicLink()");
    expect(content).toContain('includes("\\0")');
  });

  it("all KB route handlers use structured logging for errors (direct or via a delegated helper)", () => {
    const routeDir = resolve(__dirname, "../app/api/kb");
    const routeFiles = findRouteFiles(routeDir);

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      const relativePath = filePath.split("/apps/web-platform/")[1];

      // Accept either:
      //   (a) inline `logger.error` in the route, OR
      //   (b) proven delegation to a server/ helper that returns a tagged
      //       union — invocation AND `!result.ok` early-return. The helper
      //       owns logger.error/Sentry, preserving the "errors are surfaced"
      //       invariant without duplicating the logging site.
      const hasInline = content.includes("logger.error");
      const delegatesToTaggedUnion =
        /const\s+\w+\s*=\s*await\s+(createShare|listShares|revokeShare|readContent|authenticateAndResolveKbPath|resolveUserKbRoot)\s*\(/.test(
          content,
        ) && /if\s*\(\s*!\s*\w+\.ok\s*\)/.test(content);

      expect(
        hasInline || delegatesToTaggedUnion,
        `${relativePath} missing logger.error for unexpected errors (and no proven tagged-union helper delegation detected)`,
      ).toBe(true);
    }
  });
});

function findRouteFiles(dir: string): string[] {
  const results: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      results.push(...findRouteFiles(full));
    } else if (entry === "route.ts") {
      results.push(full);
    }
  }
  return results;
}
