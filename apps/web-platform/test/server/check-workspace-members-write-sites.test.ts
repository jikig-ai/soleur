import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import path from "node:path";

// feat-workspace-member-actions-audit (#4231) TR9 — sentinel sweep gate.
//
// Runs the standalone bash sentinel as part of the standard vitest suite so
// regressions are caught on every CI pass without requiring a separate CI
// step. A non-zero exit from the script means a new INSERT / UPDATE / DELETE
// site against public.workspace_members was added that does NOT route
// through the GUC-setting RPC layer (silent-audit-gap regression).

const SCRIPT_PATH = path.join(
  __dirname,
  "../../scripts/check-workspace-members-write-sites.sh",
);

describe("workspace_members write-site sentinel (#4231 TR9)", () => {
  it("exits 0 — every mutation site is in an approved category", () => {
    const result = spawnSync("bash", [SCRIPT_PATH], {
      encoding: "utf-8",
      timeout: 30_000,
    });
    if (result.status !== 0) {
      // Surface the script's own diagnostic so the failure message is
      // self-explanatory in CI logs.
      throw new Error(
        `Sentinel sweep failed (exit ${result.status}):\n` +
          `stdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
      );
    }
    expect(result.status).toBe(0);
  });
});
