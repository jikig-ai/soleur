import { describe, test, expect } from "bun:test";
import {
  enrichErrorMessage,
  removedToolHint,
  LIVE_TOOL_NAMES,
  REMOVED_TOOL_NAMES,
  RAW_CALL_STEERING,
} from "../skills/pencil-setup/scripts/pencil-error-enrichment.mjs";

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
    // batch_get is gone (0.3.13): the discovery advice must not name it
    expect(result).not.toContain("batch_get");
    expect(result).toContain("Get(");
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

// #11156 — the engine answers a removed tool with `Unknown tool: <name>`; the
// adapter registers each name as a stub whose answer is the hint below, so an
// agent holding stale prose learns the replacement.
const LIVE = [
  "batch_design",
  "export_nodes",
  "get_editor_state",
  "get_screenshot",
  "get_variables",
  "open_document",
  "read_skill",
  "save",
];
const REMOVED = [
  "batch_get",
  "find_empty_space_on_canvas",
  "get_guidelines",
  "get_style_guide",
  "get_style_guide_tags",
  "replace_all_matching_properties",
  "search_all_unique_properties",
  "set_variables",
  "snapshot_layout",
];

describe("tool name lists", () => {
  test("8 live tools and 9 removed stubs, disjoint", () => {
    expect([...LIVE_TOOL_NAMES].sort()).toEqual(LIVE);
    expect([...REMOVED_TOOL_NAMES].sort()).toEqual(REMOVED);
    for (const n of REMOVED_TOOL_NAMES) expect(LIVE_TOOL_NAMES).not.toContain(n);
  });
});

describe("RAW_CALL_STEERING (shared text contract)", () => {
  test("is the exact sentence the tool description, SKILL.md and ux-design-lead.md quote", () => {
    expect(RAW_CALL_STEERING).toBe(
      "Do not call Export or TakeScreenshot inside batch_design: use export_nodes and get_screenshot (raw calls skip the adapter's containment, overwrite list and unsaved-memory warning, and a relative path is resolved against the document's directory, so it can write next to the .pen)."
    );
  });
});

describe("enrichErrorMessage — removed tools", () => {
  const cases: Array<[string, RegExp]> = [
    ["batch_get", /Get\(.*Print\(.*batch_design.*auto-?saves?.*get_editor_state/s],
    ["snapshot_layout", /## issues detected:.*batch_design/s],
    ["get_guidelines", /read_skill\(\{ path: "guide\/<name>\.md" \}\)/],
    ["set_variables", /SetVariables\(.*batch_design/s],
    ["find_empty_space_on_canvas", /Print\(FindEmptySpace\(.*\)\).*batch_design/s],
    ["get_style_guide", /read_skill\(\).*cannot be loaded headless.*brand tokens/s],
    ["get_style_guide_tags", /read_skill\(\).*cannot be loaded headless.*brand tokens/s],
    ["search_all_unique_properties", /Get\(.*Update\(.*batch_design/s],
    ["replace_all_matching_properties", /Get\(.*Update\(.*batch_design/s],
  ];
  for (const [tool, re] of cases) {
    test(`${tool} gets a replacement hint`, () => {
      const out = enrichErrorMessage(`Unknown tool: ${tool}`);
      expect(out).toStartWith(`Unknown tool: ${tool}`);
      expect(out).toContain("[adapter hint]");
      expect(out).toMatch(re);
      expect(out).toBe(`Unknown tool: ${tool}\n\n[adapter hint] ${removedToolHint(tool)}`);
      // no 0.2.9-era advice
      expect(out).not.toMatch(/category|include_schema|get_guidelines\(\) with no arguments/);
    });
  }

  test("the measuring hints name the visitor forms the layout audit uses: c.bounds and c.problems", () => {
    for (const tool of ["batch_get", "snapshot_layout"]) {
      const hint = removedToolHint(tool) as string;
      expect(hint).toContain("Get(id,(n,c)=>Print(n.id+' '+c.bounds.width))");
      expect(hint).toMatch(/c\.problems reports clipping \(partially or fully clipped\)/);
      expect(hint).not.toMatch(/layout problems of a node/);
    }
  });

  test("the style-guide hints do not promise a loadable archetype (the names are listed, they cannot be loaded headless)", () => {
    for (const tool of ["get_style_guide", "get_style_guide_tags"]) {
      const hint = removedToolHint(tool) as string;
      expect(hint).not.toMatch(/read one with|lists the style archetypes/);
      expect(hint).toMatch(/by name, but style archetypes cannot be loaded headless/);
      expect(hint).toMatch(/brand tokens/);
      expect(hint).toMatch(/guide\/<name>\.md/);
    }
  });

  test("every removed tool has a hint and every hint names a tool that exists in the new surface", () => {
    for (const tool of REMOVED_TOOL_NAMES) {
      const hint = removedToolHint(tool) as string;
      expect(typeof hint).toBe("string");
      expect(hint.startsWith(`${tool} `)).toBe(true);
      // names at least one live tool ...
      expect(LIVE.some((live) => live !== "save" && hint.includes(live))).toBe(true);
      // ... and advises no other removed tool
      const withoutSelf = hint.split(tool).join("");
      for (const other of REMOVED_TOOL_NAMES) expect(withoutSelf).not.toContain(other);
    }
  });

  test("the answer is identical whenever it is asked (before and after open_document)", () => {
    for (const tool of REMOVED_TOOL_NAMES) {
      const a = enrichErrorMessage(`Unknown tool: ${tool}`);
      const b = enrichErrorMessage(`Unknown tool: ${tool}`);
      expect(a).toBe(b);
    }
  });

  test("a hint is found when the engine's line sits inside a longer reply", () => {
    const out = enrichErrorMessage("noise\nUnknown tool: batch_get\nmore");
    expect(out).toContain("[adapter hint] batch_get ");
  });

  test("an unrelated unknown tool is passed through unchanged", () => {
    expect(enrichErrorMessage("Unknown tool: nope")).toBe("Unknown tool: nope");
    expect(removedToolHint("nope")).toBeUndefined();
  });

  test("prototype names do not hit the hint table", () => {
    for (const name of ["constructor", "toString", "hasOwnProperty", "__proto__"]) {
      expect(enrichErrorMessage(`Unknown tool: ${name}`)).toBe(`Unknown tool: ${name}`);
      expect(removedToolHint(name)).toBeUndefined();
    }
  });
});

describe("enrichErrorMessage — execute failure advice (edits/editId are not exposed)", () => {
  const engine = [
    "Error: ### Failure during operation execution",
    "",
    "#### Errors in the input code:",
    "```",
    "Failed to execute: SyntaxError: expecting ';'",
    "```",
    "",
    "- All operations in this block have been rolled back.",
    "- IMPORTANT: Fix this by calling `execute` again with the `edits` parameter instead of regenerating the whole snippet",
    '- `editId`: "l3Gz8O"',
  ].join("\n");

  test("the retry advice names batch_design and drops the unreachable edits/editId instructions", () => {
    const out = enrichErrorMessage(engine);
    expect(out).toContain("re-send the corrected operations with batch_design");
    expect(out).not.toContain("with the `edits` parameter");
    expect(out).not.toContain("editId");
    expect(out).not.toContain("calling `execute`");
    // the rest of the engine text survives
    expect(out).toContain("Failed to execute: SyntaxError");
    expect(out).toContain("All operations in this block have been rolled back.");
  });

  test("text without that advice is unchanged", () => {
    const plain = "Error: ### Failure during operation execution\n\n- All operations in this block have been rolled back.";
    expect(enrichErrorMessage(plain)).toBe(plain);
  });
});
