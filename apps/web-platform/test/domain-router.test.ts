import { describe, expect, test } from "vitest";
import { parseAtMentions } from "@/server/domain-router";

describe("parseAtMentions", () => {
  test("parses lowercase leader IDs", () => {
    expect(parseAtMentions("@cto fix the build")).toEqual(["cto"]);
  });

  test("parses uppercase leader names", () => {
    expect(parseAtMentions("@CMO review this")).toEqual(["cmo"]);
  });

  test("parses multiple mentions", () => {
    const result = parseAtMentions("@CTO @CLO review this architecture");
    expect(result).toEqual(["cto", "clo"]);
  });

  test("deduplicates repeated mentions", () => {
    const result = parseAtMentions("@cto please help @CTO");
    expect(result).toEqual(["cto"]);
  });

  test("ignores invalid mentions", () => {
    expect(parseAtMentions("@XYZ this is not a leader")).toEqual([]);
  });

  test("returns empty for no mentions", () => {
    expect(parseAtMentions("What is our marketing strategy?")).toEqual([]);
  });

  test("handles mixed valid and invalid mentions", () => {
    const result = parseAtMentions("@CTO @FAKE @clo help");
    expect(result).toEqual(["cto", "clo"]);
  });

  test("handles mention at end of message", () => {
    expect(parseAtMentions("help me @cfo")).toEqual(["cfo"]);
  });

  test("handles mention with punctuation after", () => {
    expect(parseAtMentions("@cmo, what do you think?")).toEqual(["cmo"]);
  });

  test("is case-insensitive for leader names", () => {
    expect(parseAtMentions("@Cto review")).toEqual(["cto"]);
  });

  // Custom name @-mention tests (FR5)
  test("resolves @Alex to CTO when custom name is Alex", () => {
    expect(parseAtMentions("@Alex review this", { cto: "Alex" })).toEqual(["cto"]);
  });

  test("still resolves @CTO when custom name is set", () => {
    expect(parseAtMentions("@CTO fix the build", { cto: "Alex" })).toEqual(["cto"]);
  });

  test("custom name matching is case-insensitive", () => {
    expect(parseAtMentions("@alex help", { cto: "Alex" })).toEqual(["cto"]);
  });

  test("resolves multiple custom names", () => {
    const names = { cto: "Alex", cmo: "Sarah" };
    const result = parseAtMentions("@Sarah @Alex coordinate", names);
    expect(result).toEqual(["cmo", "cto"]);
  });

  test("custom name does not match if it belongs to a different leader", () => {
    // "Alex" maps to CTO, typing @Alex should NOT resolve to CMO
    const result = parseAtMentions("@Alex review", { cto: "Alex" });
    expect(result).toEqual(["cto"]);
  });

  test("ignores custom name with spaces in mention", () => {
    // @-mentions match \w+ so multi-word names only match first word
    const result = parseAtMentions("@Alex review", { cto: "Alex Smith" });
    expect(result).toEqual(["cto"]);
  });

  test("works with no custom names (backward compat)", () => {
    expect(parseAtMentions("@CTO fix")).toEqual(["cto"]);
  });
});
