// Parity guard for the bundled web copy of the canonical phase-surface map
// (#5772 lever 1, ADR-070 / ADR-053 three-coupling pattern). The web container
// does not ship `.claude/`, so `server/phase-surface-map.ts` is a bundled copy;
// this test deep-equals it against the canonical JSON (excluding the `_comment`
// key) and fails CI on any drift. Repo root is found by walking up to the
// `.claude/` dir (NOT a brittle hard-coded `../../..`).
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { PHASE_SURFACE_MAP } from "../server/phase-surface-map";

function findRepoRoot(start: string): string {
  let dir = start;
  for (let i = 0; i < 20; i++) {
    if (existsSync(path.join(dir, ".claude", "phase-surface-map.json"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error("phase-surface-map-parity: could not locate repo root (.claude/phase-surface-map.json) from " + start);
}

describe("phase-surface-map parity (bundled web copy vs canonical .claude/)", () => {
  const canonicalPath = path.join(findRepoRoot(__dirname), ".claude", "phase-surface-map.json");

  it("canonical map file exists and is valid JSON", () => {
    expect(existsSync(canonicalPath)).toBe(true);
    expect(() => JSON.parse(readFileSync(canonicalPath, "utf-8"))).not.toThrow();
  });

  it("bundled PHASE_SURFACE_MAP deep-equals the canonical JSON (excluding _comment)", () => {
    const canonical = JSON.parse(readFileSync(canonicalPath, "utf-8")) as Record<string, unknown>;
    delete canonical._comment;
    // Round-trip the bundled const through JSON to normalize readonly/tuple types
    // to plain arrays/objects for a structural deep-equal.
    const bundled = JSON.parse(JSON.stringify(PHASE_SURFACE_MAP));
    expect(bundled).toEqual(canonical);
  });
});
