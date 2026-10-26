import { describe, test, expect } from "bun:test";
import { enrichErrorMessage } from "../skills/pencil-setup/scripts/pencil-error-enrichment.mjs";

describe("enrichErrorMessage", () => {
  test("enriches alignSelf unexpected property error with #1106 hint", () => {
    const input = 'Invalid properties: alignSelf is an unexpected property';
    const result = enrichErrorMessage(input);
    expect(result).toContain("[adapter hint]");
    expect(result).toContain("alignSelf is not supported on frames");
    expect(result).toContain("#1106");
  });

  test("enriches padding unexpected property error with #1107 hint", () => {
    const input = 'Invalid properties: padding is an unexpected property';
    const result = enrichErrorMessage(input);
    expect(result).toContain("[adapter hint]");
    expect(result).toContain("Text nodes do not support padding");
    expect(result).toContain("#1107");
  });

  test("enriches /id missing required property error with M() workaround and #1117 hint", () => {
    const input = 'Invalid properties: /id missing required property';
    const result = enrichErrorMessage(input);
    expect(result).toContain("[adapter hint]");
    expect(result).toContain("Positional insertion is not supported");
    expect(result).toContain("M(nodeId, parent, index)");
    expect(result).toContain("batch_get");
    expect(result).toContain("#1117");
  });

  test("preserves original error text when enriching", () => {
    const input = 'Invalid properties: /id missing required property';
    const result = enrichErrorMessage(input);
    expect(result).toStartWith(input);
  });

  test("returns unmodified text for unrecognized errors", () => {
    const input = "Some other error message";
    const result = enrichErrorMessage(input);
    expect(result).toBe(input);
  });

  test("returns unmodified text for normal batch_design output (no error)", () => {
    const input = 'node0="abc123"';
    const result = enrichErrorMessage(input);
    expect(result).toBe(input);
  });
});

// #11143 — replacement hints for the tools @pencil.dev/cli 0.2.9 removed.
describe("enrichErrorMessage — removed tools (#11143)", () => {
  const cases: Array<[string, RegExp]> = [
    ["set_variables", /SetVariables\(/],
    ["find_empty_space_on_canvas", /FindEmptySpace\(/],
    ["get_style_guide", /get_guidelines/],
    ["get_style_guide_tags", /get_guidelines/],
    ["search_all_unique_properties", /no headless equivalent/i],
    ["replace_all_matching_properties", /no headless equivalent/i],
  ];
  for (const [tool, re] of cases) {
    test(`${tool} gets a replacement hint`, () => {
      const out = enrichErrorMessage(`Unknown tool: ${tool}`);
      expect(out).toContain("[adapter hint]");
      expect(out).toMatch(re);
    });
  }
  test("an unrelated unknown tool is passed through unchanged", () => {
    expect(enrichErrorMessage("Unknown tool: nope")).toBe("Unknown tool: nope");
  });
  test("prototype names do not hit the hint table", () => {
    for (const name of ["constructor", "toString", "hasOwnProperty"]) {
      expect(enrichErrorMessage(`Unknown tool: ${name}`)).toBe(`Unknown tool: ${name}`);
    }
  });
});
