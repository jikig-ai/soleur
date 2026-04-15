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

      // Auth enforcement is satisfied either by an inline getUser call OR by
      // delegation to the shared helper, which performs the same check (#2180).
      const hasInlineAuth = content.includes("supabase.auth.getUser");
      const delegatesToHelper = content.includes("authenticateAndResolveKbPath");

      expect(
        hasInlineAuth || delegatesToHelper,
        `${relativePath} missing auth check (inline getUser or authenticateAndResolveKbPath)`,
      ).toBe(true);
    }
  });

  it("all KB route handlers check workspace_status", () => {
    const routeDir = resolve(__dirname, "../app/api/kb");
    const routeFiles = findRouteFiles(routeDir);

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      const relativePath = filePath.split("/apps/web-platform/")[1];

      // Enforcement is satisfied either by an inline workspace_status check OR
      // by delegation to the shared helper, which enforces it (#2180).
      const hasInline = content.includes("workspace_status");
      const delegatesToHelper = content.includes("authenticateAndResolveKbPath");

      expect(
        hasInline || delegatesToHelper,
        `${relativePath} missing workspace_status check (inline or authenticateAndResolveKbPath)`,
      ).toBe(true);
    }
  });

  it("all KB route handlers use structured logging for errors", () => {
    const routeDir = resolve(__dirname, "../app/api/kb");
    const routeFiles = findRouteFiles(routeDir);

    for (const filePath of routeFiles) {
      const content = readFileSync(filePath, "utf-8");
      const relativePath = filePath.split("/apps/web-platform/")[1];

      expect(
        content.includes("logger.error"),
        `${relativePath} missing logger.error for unexpected errors`,
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
