// RED-first per cq-write-failing-tests-before. Phase 2.
// TS3: allowlist parser stays in sync with cla.yml; excludes DB-id 41898282.
import { describe, it, expect } from "vitest";
import {
  isAllowlistBypass,
  parseAllowlistFromYaml,
  GITHUB_ACTIONS_BOT_DB_ID,
} from "@/scripts/cla-evidence/allowlist";

const SAMPLE_CLA_YML_ALLOWLIST = "dependabot[bot],github-actions[bot],renovate[bot],deruelle,claude[bot],soleur-ai[bot]";

describe("parseAllowlistFromYaml", () => {
  it("splits comma-separated logins from cla.yml allowlist", () => {
    const list = parseAllowlistFromYaml(SAMPLE_CLA_YML_ALLOWLIST);
    expect(list).toEqual([
      "dependabot[bot]",
      "github-actions[bot]",
      "renovate[bot]",
      "deruelle",
      "claude[bot]",
      "soleur-ai[bot]",
    ]);
  });

  it("trims whitespace around each login", () => {
    expect(parseAllowlistFromYaml(" a , b , c ")).toEqual(["a", "b", "c"]);
  });
});

describe("isAllowlistBypass — login + DB-id 41898282 filter", () => {
  const allowlist = parseAllowlistFromYaml(SAMPLE_CLA_YML_ALLOWLIST);

  it("returns true for dependabot[bot] (matches allowlist, not the filtered DB-id)", () => {
    expect(isAllowlistBypass("dependabot[bot]", 49699333, allowlist)).toBe(true);
  });

  it("returns true for renovate[bot]", () => {
    expect(isAllowlistBypass("renovate[bot]", 29139614, allowlist)).toBe(true);
  });

  it("returns true for claude[bot] (Anthropic GitHub App)", () => {
    expect(isAllowlistBypass("claude[bot]", 209825114, allowlist)).toBe(true);
  });

  it("returns true for soleur-ai[bot] (Soleur automation App, bot user id 273333864 — #5520)", () => {
    expect(isAllowlistBypass("soleur-ai[bot]", 273333864, allowlist)).toBe(true);
  });

  it("returns FALSE for github-actions[bot] DB-id 41898282 even though login is allowlisted (learning #2)", () => {
    // The upstream contributor-assistant/github-action filters this DB-id
    // BEFORE the allowlist check fires, so including it would produce
    // false-positive evidence records.
    expect(isAllowlistBypass("github-actions[bot]", GITHUB_ACTIONS_BOT_DB_ID, allowlist)).toBe(false);
    expect(GITHUB_ACTIONS_BOT_DB_ID).toBe(41898282);
  });

  it("returns false for an unknown human login", () => {
    expect(isAllowlistBypass("randomdev", 99999999, allowlist)).toBe(false);
  });

  it("filters DB-id 41898282 even if a future allowlist did NOT contain github-actions[bot]", () => {
    // Defense-in-depth: the DB-id filter is independent of the login string.
    const trimmedList = parseAllowlistFromYaml("dependabot[bot],renovate[bot]");
    expect(isAllowlistBypass("github-actions[bot]", GITHUB_ACTIONS_BOT_DB_ID, trimmedList)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Guard 1 — the allowlist regex parses the REAL .github/workflows/cla.yml.
//
// Closes the #7597 gap: a format-breaking hand-edit passed unit tests (which
// only ever saw the SAMPLE constant above) and then reddened a required check
// for every open PR in the repository. Rows G1-M1..G1-M5 each drive this RED.
//
// The parser under test is the pure `parseAllowlistLine()`. It lives in
// allowlist.ts and NOT in build-bypass.ts, whose top-level `main()` calls
// process.exit() at import and would kill the test worker rather than fail an
// assertion.
// ---------------------------------------------------------------------------
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parseAllowlistLine } from "@/scripts/cla-evidence/allowlist";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const CLA_YML_REL = ".github/workflows/cla.yml";
const claYmlPath = join(repoRoot, CLA_YML_REL);

describe("Guard 1 — parseAllowlistLine against the tracked cla.yml", () => {
  const claYml = readFileSync(claYmlPath, "utf8");

  it("anti-vacuity: the text under test is the tracked workflow, not a fixture (G1-M5)", () => {
    // Swapping this read for SAMPLE_CLA_YML_ALLOWLIST must RED. These anchors
    // exist only in the real workflow file.
    expect(claYmlPath.endsWith(CLA_YML_REL)).toBe(true);
    expect(claYml).toContain("contributor-assistant/github-action");
    expect(claYml).toContain("path-to-signatures");
    expect(claYml).not.toBe(SAMPLE_CLA_YML_ALLOWLIST);
  });

  it("parses the real allowlist line — G1-M1..G1-M4 drive this RED", () => {
    const parsed = parseAllowlistLine(claYml);
    expect(parsed).not.toBeNull();
    expect(parsed!.length).toBeGreaterThanOrEqual(2);
    expect(parsed).toContain("deruelle");
  });

  it("agrees with the value the upstream action is actually configured with", () => {
    // Ties the parse to the file's own bytes, so a silent allowlist change is
    // visible here as well as at AC1.
    const parsed = parseAllowlistLine(claYml)!;
    for (const login of parsed) expect(claYml).toContain(login);
  });

  it("G1-M1: an unquoted scalar does not parse", () => {
    expect(parseAllowlistLine("          allowlist: a,b\n")).toBeNull();
  });

  it("G1-M2: a trailing inline comment does not parse", () => {
    expect(parseAllowlistLine('          allowlist: "a,b" # bots\n')).toBeNull();
  });

  it("G1-M3: a block scalar does not parse", () => {
    expect(parseAllowlistLine("          allowlist: >-\n            a,b\n")).toBeNull();
    expect(parseAllowlistLine("          allowlist: |\n            a,b\n")).toBeNull();
  });

  it("G1-M4: a missing allowlist line returns null rather than a vacuous pass", () => {
    expect(parseAllowlistLine("jobs:\n  cla-check:\n    steps: []\n")).toBeNull();
    expect(parseAllowlistLine("")).toBeNull();
  });

  it("must-PASS, non-canonical: single quotes, extra whitespace, a different login set", () => {
    expect(parseAllowlistLine("      allowlist: 'x,y'\n")).toEqual(["x", "y"]);
    expect(parseAllowlistLine('  allowlist:   "x , y"  \n')).toEqual(["x", "y"]);
    expect(parseAllowlistLine('allowlist: "solo"\n')).toEqual(["solo"]);
  });

  it("build-bypass.ts delegates to this one implementation — the chokepoint stays singular", () => {
    const src = readFileSync(join(repoRoot, "apps/web-platform/scripts/cla-evidence/build-bypass.ts"), "utf8");
    expect(src).toContain("parseAllowlistLine");
  });
});
