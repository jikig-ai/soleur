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
// Repo root — the regen script + CI workflow that ALSO pin likec4 live here,
// outside apps/web-platform.
const REPO_ROOT = path.resolve(ROOT, "..", "..");

function read(rel: string): string {
  return readFileSync(path.join(ROOT, rel), "utf8");
}

function readRepo(rel: string): string {
  return readFileSync(path.join(REPO_ROOT, rel), "utf8");
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

  // The C4 auto-regen tooling adds two EXECUTABLE surfaces that render the model
  // with the pinned CLI: scripts/regenerate-c4-model.sh (pre-commit hook + ad-hoc)
  // and the .github/workflows/ci.yml freshness-test install. If either drifts from
  // the Dockerfile/package.json pin, the committed model.likec4.json is rendered by
  // a skewed CLI and the runtime client renderer mismatches. tsc can't catch a bash
  // literal or a YAML step — only this source-read parity assertion can.
  it("scripts/regenerate-c4-model.sh and ci.yml pin the same likec4 version as the Dockerfile", () => {
    const dockerfile = read("Dockerfile");
    const cliVersion = dockerfile.match(
      /npm install -g likec4@([0-9][^\s"'`]*)/,
    )![1];

    const script = readRepo("scripts/regenerate-c4-model.sh");
    const scriptMatch = script.match(/LIKEC4_VERSION="([0-9][^\s"'`]*)"/);
    expect(
      scriptMatch,
      "regenerate-c4-model.sh must pin LIKEC4_VERSION=\"<version>\"",
    ).toBeTruthy();
    expect(scriptMatch![1]).toBe(cliVersion);

    const ci = readRepo(".github/workflows/ci.yml");
    const ciMatch = ci.match(/npm install -g likec4@([0-9][^\s"'`]*)/);
    expect(
      ciMatch,
      "ci.yml must install a pinned `likec4@<version>` for the freshness test",
    ).toBeTruthy();
    expect(ciMatch![1]).toBe(cliVersion);

    // No surface may regress to a floating tag.
    expect(script).not.toMatch(/likec4@latest/);
    expect(ci).not.toMatch(/likec4@latest/);
  });
});
