import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Drift guard (#4964): the `likec4` CLI preinstalled in the Dockerfile MUST be
// pinned to the SAME version as the client renderer `@likec4/core` /
// `@likec4/diagram`. The CLI's `export json` schema must match what
// `LikeC4Model.create` consumes — a mismatched CLI silently emits a drifted
// schema and the rendered diagram breaks. The CLI is a Dockerfile global (not a
// package.json dep, to preserve lockfile parity), so tsc/lockfile checks cannot
// catch this coupling — only this source-read parity test can.
const ROOT = path.resolve(__dirname, "..");

function read(rel: string): string {
  return readFileSync(path.join(ROOT, rel), "utf8");
}

describe("likec4 CLI / client-renderer version parity", () => {
  it("Dockerfile `npm install -g likec4@X` matches @likec4/core and @likec4/diagram in package.json", () => {
    const dockerfile = read("Dockerfile");
    const pkg = JSON.parse(read("package.json")) as {
      dependencies: Record<string, string>;
    };

    const cliMatch = dockerfile.match(/npm install -g likec4@([0-9][^\s"'`]*)/);
    expect(cliMatch, "Dockerfile must pin `npm install -g likec4@<version>`").toBeTruthy();
    const cliVersion = cliMatch![1];

    const core = pkg.dependencies["@likec4/core"];
    const diagram = pkg.dependencies["@likec4/diagram"];
    expect(core, "@likec4/core must be an exact pin").toMatch(/^[0-9]/);
    expect(diagram, "@likec4/diagram must be an exact pin").toMatch(/^[0-9]/);

    expect(cliVersion).toBe(core);
    expect(cliVersion).toBe(diagram);
  });
});
