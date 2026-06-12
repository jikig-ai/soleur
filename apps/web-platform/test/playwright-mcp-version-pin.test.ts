import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Drift guard (#5199): the Chromium baked into the prod image (via the
// Dockerfile `npx playwright@<version> install`) MUST match the `playwright-core`
// version that `@playwright/mcp` actually resolves to — because the prod image
// runs ONLY cron-ux-audit's Playwright MCP, and registry.npmjs.org + the browser
// CDN are both OFF the cron egress allowlist. A mismatch means @playwright/mcp's
// playwright-core wants a Chromium revision the image did not bake → a runtime
// browser download → blocked egress → the cron hangs/fails inside the firewalled
// container (the hardest place to diagnose, per the no-SSH rule). The three pins
// (package.json @playwright/mcp, the lockfile's nested playwright-core, the
// Dockerfile install version) have no other cross-check — only this source-read
// parity test catches the coupling on the next @playwright/mcp bump.
const ROOT = path.resolve(__dirname, "..");

function read(rel: string): string {
  return readFileSync(path.join(ROOT, rel), "utf8");
}

describe("Dockerfile Chromium / @playwright/mcp playwright-core version parity", () => {
  it("Dockerfile `npx playwright@X install` matches @playwright/mcp's resolved playwright-core", () => {
    const dockerfile = read("Dockerfile");
    const lock = JSON.parse(read("package-lock.json")) as {
      packages: Record<string, { version?: string }>;
    };

    const installMatch = dockerfile.match(
      /npx playwright@([^\s"'`]+) install/,
    );
    expect(
      installMatch,
      "Dockerfile must pin `npx playwright@<version> install`",
    ).toBeTruthy();
    const dockerfileVersion = installMatch![1];

    const nestedCore =
      lock.packages["node_modules/@playwright/mcp/node_modules/playwright-core"];
    expect(
      nestedCore?.version,
      "@playwright/mcp must resolve a nested playwright-core in package-lock.json",
    ).toBeTruthy();

    expect(dockerfileVersion).toBe(nestedCore!.version);
  });
});
