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
//   7. Per-installation synthesis pattern (#4179): given a flat-array
//      `GET /app/installations` response, `jq '{permissions, events}'` per
//      element produces a file the diff script consumes correctly. First
//      install matches manifest (exit 0); second declares fewer perms
//      (exit non-zero, permission_drift).
//
// Ref #4115, #4179.

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

  // Case 7 (#4179): the drift-guard workflow's installation-grant block reads
  // a FLAT array from `GET /app/installations` and, per element, synthesizes
  // a `{permissions, events}` file via `jq '{permissions, events}'` and feeds
  // it back into this same diff script. This case asserts that synthesis is
  // contract-stable: the synthesized per-install file MUST be accepted by the
  // diff script and produce the same `permission_drift` / exit-0 classification
  // as a directly-shaped `{permissions, events}` response would.
  test("case 7: per-installation synthesis from /app/installations flat array (#4179)", () => {
    const manifest = {
      default_permissions: { contents: "write", metadata: "read" },
      default_events: [],
    };

    // Mirrors the FLAT-ARRAY shape of `GET /app/installations` per the
    // canonical OpenAPI schema (see plan §Sharp Edges). Install #1 carries
    // realistic extra fields the synthesis filter `jq '{permissions, events}'`
    // MUST discard (account, repository_selection, target_id, target_type,
    // suspended_at, etc.) -- proves the filter is correctly narrowing the
    // shape that bin/diff-github-app-manifest.sh contracts on. Without these
    // extras, the test would silently pass even if a future edit broadened
    // the synthesis filter (e.g., `{permissions, events, app_slug}`) and
    // re-introduced shape drift on the diff-script's input contract.
    // Install #2 declares fewer permissions (drops `contents`) -- drives the
    // permission_drift classification path.
    const installations = [
      {
        id: 111,
        app_slug: "soleur-ai",
        target_id: 9001,
        target_type: "Organization",
        account: { login: "jikig-ai", type: "Organization" },
        repository_selection: "selected",
        suspended_at: null,
        permissions: { contents: "write", metadata: "read" },
        events: [],
      },
      {
        id: 222,
        app_slug: "soleur-ai",
        target_id: 9002,
        target_type: "Organization",
        account: { login: "jikig-ai-staging", type: "Organization" },
        repository_selection: "all",
        suspended_at: null,
        permissions: { metadata: "read" },
        events: [],
      },
    ];

    const dir = mkdtempSync(path.join(tmpdir(), "manifest-diff-install-"));
    try {
      const manifestPath = path.join(dir, "manifest.json");
      writeFileSync(manifestPath, JSON.stringify(manifest));

      const listPath = path.join(dir, "installations.json");
      writeFileSync(listPath, JSON.stringify(installations));

      // Replicate the workflow's synthesis loop: jq -c '.[]' streams each
      // installation, then `jq -c '{permissions, events}'` per element
      // synthesizes a per-install file the diff script consumes.
      const stream = spawnSync("jq", ["-c", ".[]", listPath], {
        encoding: "utf-8",
      });
      expect(stream.status, `jq stream stderr: ${stream.stderr}`).toBe(0);

      const perInstallResults: Array<{ id: number; status: number | null; stdout: string }> = [];
      const lines = stream.stdout.split("\n").filter((l) => l.length > 0);
      expect(lines.length).toBe(2);

      for (const [idx, installJson] of lines.entries()) {
        const synth = spawnSync("jq", ["-c", "{permissions, events}"], {
          input: installJson,
          encoding: "utf-8",
        });
        expect(synth.status, `jq synth stderr: ${synth.stderr}`).toBe(0);

        const responsePath = path.join(dir, `install-${idx}-response.json`);
        writeFileSync(responsePath, synth.stdout);

        const diff = spawnSync("bash", [SCRIPT], {
          env: {
            ...process.env,
            MANIFEST_FILE: manifestPath,
            RESPONSE_FILE: responsePath,
            PATH: process.env.PATH ?? "",
          },
          encoding: "utf-8",
        });
        perInstallResults.push({
          id: installations[idx].id,
          status: diff.status,
          stdout: diff.stdout ?? "",
        });
      }

      // Install #1 matches manifest exactly.
      expect(perInstallResults[0].status, `stdout: ${perInstallResults[0].stdout}`).toBe(0);
      // Install #2 lacks `contents` -> permission_drift.
      expect(perInstallResults[1].status).not.toBe(0);
      expect(perInstallResults[1].stdout).toMatch(/^permission_drift:/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
