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
