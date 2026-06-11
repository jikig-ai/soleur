import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { parseAtMentions, routeMessage } from "@/server/domain-router";

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

describe("routeMessage", () => {
  test("resolves @oleg to CTO with custom names (mention mode, no API call)", async () => {
    const result = await routeMessage(
      "@oleg review this architecture",
      "fake-api-key",
      undefined,
      { cto: "Oleg" },
    );
    expect(result).toEqual({ leaders: ["cto"], source: "mention" });
  });

  test("still resolves @CTO without custom names (backward compat)", async () => {
    const result = await routeMessage(
      "@CTO fix the build",
      "fake-api-key",
    );
    expect(result).toEqual({ leaders: ["cto"], source: "mention" });
  });
});

// #5186: the classify (auto) path had ZERO coverage — parseAtMentions and the
// mention-override branch both return before classifyMessage's fetch is reached.
// These fetch-mock tests pin the structured-output migration: the request body
// carries output_config with the json_schema, parsed.leaders is extracted +
// validIds-filtered + sliced, and the ["cpo"] fallback fires on failure.
describe("routeMessage classify (auto) path", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  function anthropicResponse(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), { status });
  }

  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test("sends output_config json_schema and extracts + filters parsed.leaders", async () => {
    fetchSpy.mockResolvedValue(
      anthropicResponse({
        content: [{ type: "text", text: '{"leaders":["cmo","not-a-leader"]}' }],
        stop_reason: "end_turn",
      }),
    );

    const result = await routeMessage("What is our marketing strategy?", "fake-api-key");

    expect(result).toEqual({ leaders: ["cmo"], source: "auto" });
    // The request body carries the structured-output schema.
    const [, init] = fetchSpy.mock.calls[0] as [string, RequestInit];
    const sent = JSON.parse(init.body as string);
    expect(sent.output_config?.format?.type).toBe("json_schema");
    expect(sent.output_config.format.schema.properties).toHaveProperty("leaders");
  });

  test("caps extracted leaders at MAX_LEADERS_PER_MESSAGE", async () => {
    fetchSpy.mockResolvedValue(
      anthropicResponse({
        content: [{ type: "text", text: '{"leaders":["cmo","cto","clo","cfo"]}' }],
        stop_reason: "end_turn",
      }),
    );

    const result = await routeMessage("Plan the next quarter", "fake-api-key");

    expect(result.source).toBe("auto");
    expect(result.leaders).toHaveLength(3);
    expect(result.leaders).toEqual(["cmo", "cto", "clo"]);
  });

  test("falls back to [cpo] on a non-ok response", async () => {
    fetchSpy.mockResolvedValue(anthropicResponse({}, 500));

    const result = await routeMessage("Help me with something", "fake-api-key");

    expect(result).toEqual({ leaders: ["cpo"], source: "auto" });
  });

  test("falls back to [cpo] when the model returns unparseable text", async () => {
    fetchSpy.mockResolvedValue(
      anthropicResponse({
        content: [{ type: "text", text: "not json at all" }],
        stop_reason: "end_turn",
      }),
    );

    const result = await routeMessage("Help me with something", "fake-api-key");

    expect(result).toEqual({ leaders: ["cpo"], source: "auto" });
  });
});
