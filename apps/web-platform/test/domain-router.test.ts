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
});
