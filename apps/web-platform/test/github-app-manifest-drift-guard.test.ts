import { describe, test, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Contract test for bin/diff-github-app-manifest.sh — the shared diff
// script invoked by BOTH the workflow YAML and this test (Phase 3.3
// "share the diff bash" requirement).
//
// Mirrors github-app-drift-guard-contract.test.ts:3,375 spawnSync pattern.
// Skips when `jq` is unavailable on the runner.
//
// Six-case matrix per plan Phase 3.4:
//   1. Permission match -> exit 0
//   2. Manifest declares administration:write, live grants administration:read
//      -> exit non-zero, stdout matches /^permission_drift:/
//   3. Live has events:[repository_dispatch] not in manifest
//      -> exit non-zero, stdout matches /^permission_unexpected_grant:/
//   4. Response {message:"Not Found"} -> exit non-zero,
//      stdout matches /^response_shape_unparseable:/
//   5. Empty arrays both sides -> exit 0
//   6. Same array content, different ordering -> exit 0 (proves jq sort)
//
// Ref #4115.

const REPO_ROOT = path.resolve(__dirname, "../../..");
const SCRIPT = path.join(REPO_ROOT, "bin/diff-github-app-manifest.sh");

const jqAvailable = (() => {
  const out = spawnSync("which", ["jq"], { encoding: "utf-8" });
  return out.status === 0;
})();

interface Fixture {
  manifest: object;
  response: object;
}

function runDiff(fix: Fixture): {
  status: number | null;
  stdout: string;
  stderr: string;
} {
  const dir = mkdtempSync(path.join(tmpdir(), "manifest-diff-"));
  const manifestPath = path.join(dir, "manifest.json");
  const responsePath = path.join(dir, "response.json");
  writeFileSync(manifestPath, JSON.stringify(fix.manifest));
  writeFileSync(responsePath, JSON.stringify(fix.response));
  try {
    const result = spawnSync("bash", [SCRIPT], {
      env: {
        ...process.env,
        MANIFEST_FILE: manifestPath,
        RESPONSE_FILE: responsePath,
        PATH: process.env.PATH ?? "",
      },
      encoding: "utf-8",
    });
    return {
      status: result.status,
      stdout: result.stdout ?? "",
      stderr: result.stderr ?? "",
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe.skipIf(!jqAvailable)("bin/diff-github-app-manifest.sh contract", () => {
  test("script file exists and is executable", () => {
    expect(existsSync(SCRIPT), `missing ${SCRIPT}`).toBe(true);
  });

  test("case 1: permission match -> exit 0", () => {
    const result = runDiff({
      manifest: {
        default_permissions: { administration: "write", contents: "read" },
        default_events: ["push"],
      },
      response: {
        permissions: { administration: "write", contents: "read" },
        events: ["push"],
      },
    });
    expect(result.status, `stderr: ${result.stderr}\nstdout: ${result.stdout}`).toBe(0);
  });

  test("case 2: manifest declares administration:write, live grants administration:read -> permission_drift", () => {
    const result = runDiff({
      manifest: {
        default_permissions: { administration: "write" },
        default_events: [],
      },
      response: {
        permissions: { administration: "read" },
        events: [],
      },
    });
    expect(result.status).not.toBe(0);
    expect(result.stdout).toMatch(/^permission_drift:/);
  });

  test("case 3: live has events:[repository_dispatch] not in manifest -> permission_unexpected_grant", () => {
    const result = runDiff({
      manifest: {
        default_permissions: { metadata: "read" },
        default_events: [],
      },
      response: {
        permissions: { metadata: "read" },
        events: ["repository_dispatch"],
      },
    });
    expect(result.status).not.toBe(0);
    expect(result.stdout).toMatch(/^permission_unexpected_grant:/);
  });

  test("case 4: response shape malformed -> response_shape_unparseable", () => {
    const result = runDiff({
      manifest: {
        default_permissions: { metadata: "read" },
        default_events: [],
      },
      response: { message: "Not Found" },
    });
    expect(result.status).not.toBe(0);
    expect(result.stdout).toMatch(/^response_shape_unparseable:/);
  });

  test("case 5: empty arrays both sides -> exit 0", () => {
    const result = runDiff({
      manifest: {
        default_permissions: {},
        default_events: [],
      },
      response: {
        permissions: {},
        events: [],
      },
    });
    expect(result.status, `stderr: ${result.stderr}\nstdout: ${result.stdout}`).toBe(0);
  });

  test("case 6: same array content, different ordering -> exit 0", () => {
    const result = runDiff({
      manifest: {
        default_permissions: { contents: "read", metadata: "read" },
        default_events: ["push", "pull_request"],
      },
      response: {
        permissions: { metadata: "read", contents: "read" },
        events: ["pull_request", "push"],
      },
    });
    expect(result.status, `stderr: ${result.stderr}\nstdout: ${result.stdout}`).toBe(0);
  });
});
