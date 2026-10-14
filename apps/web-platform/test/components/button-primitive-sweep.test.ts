import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import path from "node:path";

// feat-ui-action-feedback (#8917) Guard 2 — button primitive sweep sentinel.
//
// Runs the standalone bash sentinel as part of the standard vitest suite so
// regressions are caught on every CI pass without requiring a separate CI
// step. A non-zero exit means a native <button> exists that neither renders
// through the Button primitive nor carries data-button-exempt="<reason>",
// an exemption marker with an empty reason was added, or the native-button
// count grew past NATIVE_BUTTON_BASELINE.

const SCRIPT_PATH = path.join(
  __dirname,
  "../../scripts/check-button-primitive-sweep.sh",
);

describe("button primitive sweep sentinel (#8917 Guard 2)", () => {
  it("exits 0 — every native <button> is exempt-marked within the baseline", () => {
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

  // Positive-mutation coverage: a tracked native <button> with no
  // data-button-exempt MUST fail — the baseline could otherwise pass
  // vacuously if the discovery grep silently broke.
  it("fails on a planted unexempted native button", () => {
    const result = spawnSync("bash", [SCRIPT_PATH], {
      encoding: "utf-8",
      timeout: 30_000,
      env: {
        ...process.env,
        BUTTON_SWEEP_PATHS: "test/fixtures/button-primitive-violation.tsx",
        BUTTON_SWEEP_BASELINE: "1",
      },
    });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain("FAIL");
  });
});
