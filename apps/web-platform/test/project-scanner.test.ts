import { describe, it, expect, vi, beforeEach } from "vitest";
import fs from "fs";

// ---------------------------------------------------------------------------
// Mock fs BEFORE importing the module under test
// ---------------------------------------------------------------------------

vi.mock("fs", () => {
  const actual = vi.importActual<typeof import("fs")>("fs");
  return {
    ...actual,
    default: {
      ...actual,
      existsSync: vi.fn(),
      readdirSync: vi.fn(),
    },
    existsSync: vi.fn(),
    readdirSync: vi.fn(),
  };
});

const mockExistsSync = vi.mocked(fs.existsSync);
const mockReaddirSync = vi.mocked(fs.readdirSync);

import {
  scanProjectHealth,
  type ProjectHealthSnapshot,
} from "@/server/project-scanner";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const WORKSPACE = "/workspaces/user-123";

/**
 * Configure mocks so that specific paths "exist" and directories return entries.
 *
 * `existingPaths` — absolute paths that existsSync returns true for.
 * `dirEntries` — map of directory path → array of filenames returned by readdirSync.
 */
function setupFs(
  existingPaths: string[],
  dirEntries: Record<string, string[]> = {},
) {
  mockExistsSync.mockImplementation((p) => existingPaths.includes(String(p)));
  mockReaddirSync.mockImplementation(((p: unknown) => {
    const entries = dirEntries[String(p)];
    if (entries) return entries;
    return [];
  }) as typeof fs.readdirSync);
}

/**
 * Build the full set of paths that represent all 8 signals being present.
 *
 * The 8 core signals and their expected detection paths:
 *  1. package manager  — package.json (or Cargo.toml, go.mod, Gemfile, etc.)
 *  2. tests            — test/ or tests/ or spec/ directory, or __tests__
 *  3. CI               — .github/workflows/ or .gitlab-ci.yml or Jenkinsfile
 *  4. linting          — .eslintrc*, biome.json, .prettierrc*, etc.
 *  5. README           — README.md (or README.*)
 *  6. CLAUDE.md        — CLAUDE.md
 *  7. docs directory   — docs/
 *  8. knowledge-base   — knowledge-base/
 */
function allSignalPaths(): string[] {
  return [
    `${WORKSPACE}/package.json`,
    `${WORKSPACE}/test`,
    `${WORKSPACE}/.github/workflows`,
    `${WORKSPACE}/.eslintrc.json`,
    `${WORKSPACE}/README.md`,
    `${WORKSPACE}/CLAUDE.md`,
    `${WORKSPACE}/docs`,
    `${WORKSPACE}/knowledge-base`,
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("scanProjectHealth", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // 1. All 8 signals present → "strong"
  it('categorises a repo with all 8 signals as "strong"', () => {
    setupFs(allSignalPaths());

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("strong");
    expect(result.signals.detected).toHaveLength(8);
    expect(result.signals.missing).toHaveLength(0);
  });

  // 2. 4 signals → "developing"
  it('categorises a repo with 4 signals as "developing"', () => {
    setupFs([
      `${WORKSPACE}/package.json`,
      `${WORKSPACE}/README.md`,
      `${WORKSPACE}/test`,
      `${WORKSPACE}/docs`,
    ]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("developing");
    expect(result.signals.detected).toHaveLength(4);
    expect(result.signals.missing).toHaveLength(4);
  });

  // 3. 1 signal → "gaps-found"
  it('categorises a repo with 1 signal as "gaps-found"', () => {
    setupFs([`${WORKSPACE}/package.json`]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("gaps-found");
    expect(result.signals.detected).toHaveLength(1);
    expect(result.signals.missing).toHaveLength(7);
  });

  // 4. Empty repo → "gaps-found" with generic recommendations
  it('categorises an empty repo as "gaps-found" with recommendations', () => {
    setupFs([]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("gaps-found");
    expect(result.signals.detected).toHaveLength(0);
    expect(result.signals.missing).toHaveLength(8);
    expect(result.recommendations.length).toBeGreaterThan(0);
    // Recommendations should be human-readable strings
    for (const rec of result.recommendations) {
      expect(typeof rec).toBe("string");
      expect(rec.length).toBeGreaterThan(0);
    }
  });

  // 5. kbExists is true when knowledge-base/ directory exists
  it("sets kbExists true when knowledge-base/ directory is present", () => {
    setupFs([`${WORKSPACE}/knowledge-base`]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.kbExists).toBe(true);
  });

  it("sets kbExists false when knowledge-base/ directory is absent", () => {
    setupFs([`${WORKSPACE}/package.json`]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.kbExists).toBe(false);
  });

  // 6. Recommendations: top 3 from missing signals, or fewer if < 3 missing
  it("returns at most 3 recommendations when 4+ signals are missing", () => {
    setupFs([
      `${WORKSPACE}/package.json`,
      `${WORKSPACE}/README.md`,
      `${WORKSPACE}/test`,
      `${WORKSPACE}/docs`,
    ]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.recommendations).toHaveLength(3);
  });

  it("returns 3 recommendations when all signals are missing", () => {
    setupFs([]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.recommendations).toHaveLength(3);
  });

  it("returns 1 recommendation when only 1 signal is missing", () => {
    const paths = allSignalPaths().slice(0, 7); // drop knowledge-base
    setupFs(paths);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.recommendations).toHaveLength(1);
  });

  // 7. scannedAt is a valid ISO date string
  it("returns a valid ISO 8601 date string in scannedAt", () => {
    setupFs([]);

    const result = scanProjectHealth(WORKSPACE);

    expect(result.scannedAt).toBeDefined();
    const parsed = new Date(result.scannedAt);
    expect(parsed.toISOString()).toBe(result.scannedAt);
    expect(Number.isNaN(parsed.getTime())).toBe(false);
  });

  // Structural: returned object matches ProjectHealthSnapshot shape
  it("returns an object matching the ProjectHealthSnapshot interface", () => {
    setupFs(allSignalPaths());

    const result: ProjectHealthSnapshot = scanProjectHealth(WORKSPACE);

    expect(result).toHaveProperty("scannedAt");
    expect(result).toHaveProperty("category");
    expect(result).toHaveProperty("signals");
    expect(result).toHaveProperty("signals.detected");
    expect(result).toHaveProperty("signals.missing");
    expect(result).toHaveProperty("recommendations");
    expect(result).toHaveProperty("kbExists");
  });

  // Category boundary: exactly 6 signals → "strong" (lower bound)
  it('categorises a repo with exactly 6 signals as "strong" (boundary)', () => {
    setupFs(allSignalPaths().slice(0, 6));

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("strong");
    expect(result.signals.detected).toHaveLength(6);
  });

  // Category boundary: exactly 5 signals → "developing" (upper bound)
  it('categorises a repo with exactly 5 signals as "developing" (boundary)', () => {
    setupFs(allSignalPaths().slice(0, 5));

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("developing");
    expect(result.signals.detected).toHaveLength(5);
  });

  // Category boundary: exactly 3 signals → "developing" (lower bound)
  it('categorises a repo with exactly 3 signals as "developing" (boundary)', () => {
    setupFs(allSignalPaths().slice(0, 3));

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("developing");
    expect(result.signals.detected).toHaveLength(3);
  });

  // Category boundary: exactly 2 signals → "gaps-found" (upper bound)
  it('categorises a repo with exactly 2 signals as "gaps-found" (boundary)', () => {
    setupFs(allSignalPaths().slice(0, 2));

    const result = scanProjectHealth(WORKSPACE);

    expect(result.category).toBe("gaps-found");
    expect(result.signals.detected).toHaveLength(2);
  });

  // Signal objects have id and label
  it("returns signal objects with id and label properties", () => {
    setupFs(allSignalPaths());

    const result = scanProjectHealth(WORKSPACE);

    for (const signal of result.signals.detected) {
      expect(signal).toHaveProperty("id");
      expect(signal).toHaveProperty("label");
      expect(typeof signal.id).toBe("string");
      expect(typeof signal.label).toBe("string");
      expect(signal.id.length).toBeGreaterThan(0);
      expect(signal.label.length).toBeGreaterThan(0);
    }
  });
});
