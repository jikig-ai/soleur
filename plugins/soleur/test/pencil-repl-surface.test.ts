import { describe, test, expect } from "bun:test";
import {
  ReplContractError,
  REPL_SURFACE,
  BATCH_DESIGN_PREAMBLE,
  formatReplCommand,
  planSpawn,
} from "../skills/pencil-setup/scripts/pencil-repl-surface.mjs";

// #11143 — the adapter sent `batch_design({ operations })`; @pencil.dev/cli
// 0.2.9 takes `{ input }`, drops the unknown key and prints OK. The surface
// table below is the 0.2.9 `pencil interactive --help` signature list; the
// live engine-contract-probe.sh diffs it against the installed CLI.

const EXPECTED_SURFACE: Record<string, string[]> = {
  batch_design: ["input"],
  batch_get: [
    "includePathGeometry",
    "nodeIds",
    "parentId",
    "patterns",
    "readDepth",
    "resolveInstances",
    "resolveVariables",
    "searchDepth",
  ],
  export_html: [
    "format",
    "includeHtmlScaffold",
    "includeLayerIds",
    "includeLayerNames",
    "nodeIds",
    "outputPath",
  ],
  export_nodes: ["format", "nodeIds", "outputDir", "quality", "scale"],
  get_editor_state: ["include_schema"],
  get_guidelines: ["category", "name", "params"],
  get_screenshot: ["nodeId"],
  get_variables: [],
  save: [],
  snapshot_layout: ["maxDepth", "parentId", "problemsOnly"],
};

describe("REPL_SURFACE table", () => {
  test("exact tool set and key lists for the pinned CLI (0.2.9)", () => {
    const actual: Record<string, string[]> = {};
    for (const [tool, keys] of Object.entries(REPL_SURFACE)) {
      actual[tool] = [...(keys as string[])].sort();
    }
    const expected: Record<string, string[]> = {};
    for (const [tool, keys] of Object.entries(EXPECTED_SURFACE)) {
      expected[tool] = [...keys].sort();
    }
    expect(actual).toEqual(expected);
  });

  test("save is a keyless entry", () => {
    expect(REPL_SURFACE.save).toEqual([]);
  });
});

describe("formatReplCommand", () => {
  test("batch_design maps operations to input with the alias preamble", () => {
    const cmd = formatReplCommand("batch_design", {
      operations: 'a=Insert(document,{type:"frame"})',
    });
    expect(cmd.startsWith("batch_design({ input: ")).toBe(true);
    expect(cmd).not.toContain("operations");
    const arg = cmd.slice("batch_design({ input: ".length, -" })".length);
    const decoded = JSON.parse(arg);
    expect(decoded).toBe(`${BATCH_DESIGN_PREAMBLE}\na=Insert(document,{type:"frame"})`);
    expect(decoded.startsWith("var I=Insert,U=Update,C=Copy,R=Replace,M=Move,D=Delete,G=Generate;")).toBe(true);
  });

  test("the REPL command is one physical line (newlines, CR, U+2028/9 escaped)", () => {
    const cmd = formatReplCommand("batch_design", {
      operations: 'a=Insert(document,{name:"x\ny"})\r\nb=I(a,{})\u2028c\u2029',
    });
    expect(cmd).not.toMatch(/[\n\r\u2028\u2029]/);
  });

  test("U+0085 (NEL) is escaped too, so a line-splitting engine cannot see a second command", () => {
    const cmd = formatReplCommand("batch_design", {
      operations: "a=I(document,{})" + String.fromCharCode(0x85) + "save()",
    });
    expect(cmd.includes(String.fromCharCode(0x85))).toBe(false);
    expect(cmd).toContain("\\u0085");
  });

  test("empty or non-string operations throw ReplContractError", () => {
    expect(() => formatReplCommand("batch_design", { operations: "" })).toThrow(ReplContractError);
    expect(() => formatReplCommand("batch_design", { operations: "   " })).toThrow(ReplContractError);
    expect(() => formatReplCommand("batch_design", {})).toThrow(ReplContractError);
    expect(() => formatReplCommand("batch_design", { operations: 5 })).toThrow(ReplContractError);
  });

  test("an unknown tool throws a message starting with 'Unknown tool:'", () => {
    for (const tool of [
      "find_empty_space_on_canvas",
      "get_style_guide",
      "get_style_guide_tags",
      "search_all_unique_properties",
      "replace_all_matching_properties",
      "set_variables",
      "nope",
    ]) {
      let err: any;
      try {
        formatReplCommand(tool, { a: 1 });
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(ReplContractError);
      expect(err.message.startsWith(`Unknown tool: ${tool}`)).toBe(true);
    }
  });

  test("an unknown key on a known tool throws", () => {
    expect(() => formatReplCommand("get_screenshot", { nodeId: "a", bogus: 1 })).toThrow(ReplContractError);
    expect(() => formatReplCommand("save", { x: 1 })).toThrow(ReplContractError);
    // the old key must not sneak through for batch_design
    expect(() => formatReplCommand("batch_design", { operations: "a=I()", input: "b" })).toThrow(ReplContractError);
  });

  test("no params gives tool()", () => {
    expect(formatReplCommand("save", {})).toBe("save()");
    expect(formatReplCommand("get_variables", undefined)).toBe("get_variables()");
    expect(formatReplCommand("batch_get", {})).toBe("batch_get()");
  });

  test("optional keys may be omitted; known keys are JSON-encoded", () => {
    expect(formatReplCommand("get_guidelines", { category: "guide", name: "Web App" })).toBe(
      'get_guidelines({"category":"guide","name":"Web App"})'
    );
    expect(formatReplCommand("snapshot_layout", {})).toBe("snapshot_layout()");
    expect(formatReplCommand("batch_get", { nodeIds: ["a"] })).toBe('batch_get({"nodeIds":["a"]})');
  });

  test("undefined-valued keys are dropped, not emitted", () => {
    expect(formatReplCommand("export_nodes", { nodeIds: ["a"], outputDir: "/o", format: undefined })).toBe(
      'export_nodes({"nodeIds":["a"],"outputDir":"/o"})'
    );
  });
});

const probeOf = (files: Record<string, number>) => ({
  exists: (p: string) => p in files,
  size: (p: string) => files[p] ?? 0,
});

describe("planSpawn", () => {
  test("existing non-empty outFile is reloaded: inFile === outFile", () => {
    expect(
      planSpawn({ outFile: "/d/a.pen", initialInFile: null, probe: probeOf({ "/d/a.pen": 489 }) })
    ).toEqual({ inFile: "/d/a.pen" });
  });

  test("missing outFile gives no --in", () => {
    expect(planSpawn({ outFile: "/d/a.pen", initialInFile: null, probe: probeOf({}) })).toEqual({ inFile: null });
  });

  test("0-byte outFile gives no --in", () => {
    expect(
      planSpawn({ outFile: "/d/a.pen", initialInFile: undefined, probe: probeOf({ "/d/a.pen": 0 }) })
    ).toEqual({ inFile: null });
  });

  test("explicit initial inFile that exists is used", () => {
    expect(
      planSpawn({ outFile: "/d/new.pen", initialInFile: "/t/tpl.pen", probe: probeOf({ "/t/tpl.pen": 300 }) })
    ).toEqual({ inFile: "/t/tpl.pen" });
  });

  test("explicit initial inFile that is missing fails fast", () => {
    expect(() =>
      planSpawn({ outFile: "/d/new.pen", initialInFile: "/t/missing.pen", probe: probeOf({}) })
    ).toThrow(/not found/i);
  });

  test("a respawn (no explicit inFile) reloads outFile, never a template", () => {
    // The adapter clears the explicit inFile after the first successful spawn.
    expect(
      planSpawn({ outFile: "/d/new.pen", initialInFile: null, probe: probeOf({ "/d/new.pen": 700, "/t/tpl.pen": 300 }) })
    ).toEqual({ inFile: "/d/new.pen" });
  });

  test("a respawn before the first save falls back to the template; saved edits still win", () => {
    const resume = "/t/tpl.pen";
    expect(
      planSpawn({ outFile: "/d/new.pen", initialInFile: null, resumeInFile: resume, probe: probeOf({ "/t/tpl.pen": 300 }) })
    ).toEqual({ inFile: resume });
    expect(
      planSpawn({ outFile: "/d/new.pen", initialInFile: null, resumeInFile: resume, probe: probeOf({ "/d/new.pen": 0, "/t/tpl.pen": 300 }) })
    ).toEqual({ inFile: resume });
    expect(
      planSpawn({ outFile: "/d/new.pen", initialInFile: null, resumeInFile: resume, probe: probeOf({ "/d/new.pen": 700, "/t/tpl.pen": 300 }) })
    ).toEqual({ inFile: "/d/new.pen" });
    expect(
      planSpawn({ outFile: "/d/new.pen", initialInFile: null, resumeInFile: resume, probe: probeOf({}) })
    ).toEqual({ inFile: null });
  });
});
