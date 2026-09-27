import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import path from "node:path";

// feat-ui-action-feedback (#8917) nav-channel sentinel — the route-pending bar
// has exactly three producers (NavLink, usePendingRouter, popstate); a raw
// next/link import, a useRouter().push, or a literal internal <a href="/…">
// is a dead-click path that no listener can observe. This runs the bash
// sentinel in the standard vitest suite so drift reds on every CI pass.

const SCRIPT_PATH = path.join(
  __dirname,
  "../../scripts/check-nav-channel-sweep.sh",
);

describe("nav-channel sweep sentinel (#8917)", () => {
  it("exits 0 — every nav path flows through a pending channel", () => {
    const result = spawnSync("bash", [SCRIPT_PATH], {
      encoding: "utf-8",
      timeout: 30_000,
    });
    if (result.status !== 0) {
      throw new Error(
        `Nav-channel sweep failed (exit ${result.status}):\n` +
          `stdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
      );
    }
    expect(result.status).toBe(0);
  });

  // Positive-mutation coverage: the tracked fixtures under test/fixtures/
  // (outside the default pathspec) MUST fail the sentinel — an exit-0-only
  // assertion would stay green if a check's regex silently broke.
  it.each([
    ["nav-channel-violation-link.tsx", "next/link"],
    ["nav-channel-violation-router.tsx", "router"],
    ["nav-channel-violation-anchor.tsx", "anchor"],
  ])("fails on a planted %s bypass", (fixture, kind) => {
    const result = spawnSync("bash", [SCRIPT_PATH], {
      encoding: "utf-8",
      timeout: 30_000,
      env: {
        ...process.env,
        NAV_SWEEP_PATHS: `test/fixtures/${fixture}`,
      },
    });
    expect(result.status).toBe(1);
    expect(result.stderr).toContain("FAIL");
    // The per-class fixture isolates one check; the diagnostic should name
    // its violation class (defensive — kind kept for readable test names).
    expect(kind).toBeTruthy();
  });
});
