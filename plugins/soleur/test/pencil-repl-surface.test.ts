import { describe, test, expect } from "bun:test";
import {
  ReplContractError,
  REPL_SURFACE,
  REPL_PROMPT,
  REPL_PROMPT_RAW,
  BATCH_DESIGN_PREAMBLE,
  NODE_FLOOR,
  EXPORT_FORMATS,
  MAX_NODE_IDS,
  formatReplCommand,
  buildBatchDesignCommand,
  buildScreenshotCommand,
  buildExportCommand,
  buildVariablesCommand,
  buildEditorStateCommand,
  buildReadSkillCommand,
  buildSaveCommand,
  buildCountSnippet,
  buildCountCommand,
  newCountNonce,
  countSnippetNonce,
  parseCountReply,
  validateNodeId,
  validateNodeIds,
  validateExportFormat,
  validateScale,
  validateQuality,
  validateSkillPath,
  validateOutputDir,
  redactionForms,
  redactText,
  createRollingRedactor,
  compareVersions,
  nodeVersionOk,
  planSpawn,
} from "../skills/pencil-setup/scripts/pencil-repl-surface.mjs";

// #11156 — the surface of `pen interactive` in @pen.dev/cli 0.3.13. The table
// below is the signature list `pen interactive --help` prints for the REPL
// tools the adapter drives (get_style and browser exist but are deliberately
// absent: CTO ruling 10 cut get_style, the adapter never emits browser).
// engine-contract-probe.sh diffs the live engine against the module table on
// every pin bump.

const EXPECTED_SURFACE: Record<string, string[]> = {
  execute: ["description", "editId", "edits", "input"],
  get_app_state: [],
  read_skill: ["path"],
  save: [],
};

const REMOVED_NAMES = [
  "batch_design",
  "batch_get",
  "snapshot_layout",
  "get_guidelines",
  "get_style_guide",
  "get_style_guide_tags",
  "find_empty_space_on_canvas",
  "search_all_unique_properties",
  "replace_all_matching_properties",
  "set_variables",
  "get_editor_state",
  "get_screenshot",
  "export_nodes",
  "get_variables",
];

// Decoded argument of an `execute({ input: "<json>" })` line.
const inputOf = (cmd: string): string => {
  expect(cmd.startsWith("execute({ input: ")).toBe(true);
  expect(cmd.endsWith(" })")).toBe(true);
  return JSON.parse(cmd.slice("execute({ input: ".length, -" })".length));
};

describe("REPL_SURFACE table", () => {
  test("exact tool set and key lists for the pinned CLI (0.3.13)", () => {
    const actual: Record<string, string[]> = {};
    for (const [tool, keys] of Object.entries(REPL_SURFACE)) actual[tool] = [...(keys as string[])].sort();
    const expected: Record<string, string[]> = {};
    for (const [tool, keys] of Object.entries(EXPECTED_SURFACE)) expected[tool] = [...keys].sort();
    expect(actual).toEqual(expected);
  });

  test("the table is frozen", () => {
    expect(Object.isFrozen(REPL_SURFACE)).toBe(true);
  });

  test("save and get_app_state are keyless entries", () => {
    expect(REPL_SURFACE.save).toEqual([]);
    expect(REPL_SURFACE.get_app_state).toEqual([]);
  });

  test("the prompt constant is `pen > ` (it was `pencil > `) and the raw prompt strips to it", () => {
    expect(REPL_PROMPT).toBe("pen > ");
    // measured on piped stdout: the engine colours the prompt even without a TTY
    expect(REPL_PROMPT_RAW).toBe("\x1b[36mpen\x1b[39m \x1b[2m>\x1b[22m ");
    expect(REPL_PROMPT_RAW.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "")).toBe(REPL_PROMPT);
  });
});

describe("formatReplCommand", () => {
  test("no params gives tool()", () => {
    expect(formatReplCommand("save", {})).toBe("save()");
    expect(formatReplCommand("get_app_state", undefined)).toBe("get_app_state()");
    expect(formatReplCommand("read_skill", {})).toBe("read_skill()");
  });

  test("execute with only input uses the `{ input: <json> }` shape", () => {
    expect(formatReplCommand("execute", { input: "Print(1)" })).toBe('execute({ input: "Print(1)" })');
  });

  test("read_skill with a path is JSON-encoded", () => {
    expect(formatReplCommand("read_skill", { path: "guide/table.md" })).toBe('read_skill({"path":"guide/table.md"})');
  });

  test("undefined-valued keys are dropped, not emitted", () => {
    expect(formatReplCommand("read_skill", { path: undefined })).toBe("read_skill()");
  });

  test("a tool the engine does not have (or the adapter retired) throws 'Unknown tool:'", () => {
    for (const tool of [...REMOVED_NAMES, "nope", "get_style", "browser"]) {
      let err: any;
      try {
        formatReplCommand(tool, { a: 1 });
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(ReplContractError);
      expect(err.message.startsWith(`Unknown tool: ${tool}`)).toBe(true);
      expect(err.message).toContain("@pen.dev/cli");
    }
  });

  test("prototype names do not pass the table", () => {
    for (const name of ["constructor", "toString", "hasOwnProperty", "__proto__"]) {
      expect(() => formatReplCommand(name, {})).toThrow(ReplContractError);
    }
  });

  test("an unknown key on a known tool throws", () => {
    expect(() => formatReplCommand("save", { x: 1 })).toThrow(ReplContractError);
    expect(() => formatReplCommand("get_app_state", { include_schema: true })).toThrow(ReplContractError);
    expect(() => formatReplCommand("read_skill", { name: "a" })).toThrow(ReplContractError);
    // the old 0.2.9 key must not sneak through: `operations` is the adapter's name, not the engine's
    expect(() => formatReplCommand("execute", { operations: "a=I()" })).toThrow(ReplContractError);
  });

  test("execute needs a non-empty string input", () => {
    expect(() => formatReplCommand("execute", {})).toThrow(ReplContractError);
    expect(() => formatReplCommand("execute", { input: "" })).toThrow(ReplContractError);
    expect(() => formatReplCommand("execute", { input: "  " })).toThrow(ReplContractError);
    expect(() => formatReplCommand("execute", { input: 5 })).toThrow(ReplContractError);
  });
});

describe("jsonLine escaping (through every builder)", () => {
  const C1_AND_SEPARATORS = (() => {
    const chars: string[] = [String.fromCharCode(0x7f), String.fromCharCode(0x2028), String.fromCharCode(0x2029)];
    for (let c = 0x80; c <= 0x9f; c++) chars.push(String.fromCharCode(c));
    return chars;
  })();

  test("the REPL command is one physical line (newlines, CR, U+2028/9 escaped)", () => {
    const cmd = buildBatchDesignCommand(
      'a=Insert(document,{name:"x\ny"})\r\nb=I(a,{})' + String.fromCharCode(0x2028) + "c" + String.fromCharCode(0x2029)
    );
    expect(cmd).not.toMatch(/[\n\r]/);
    expect(cmd.includes(String.fromCharCode(0x2028))).toBe(false);
    expect(cmd.includes(String.fromCharCode(0x2029))).toBe(false);
  });

  test("DEL and the whole C1 range (U+0080..U+009F, incl. NEL) are escaped", () => {
    for (const ch of C1_AND_SEPARATORS) {
      const cmd = buildBatchDesignCommand("a=I(document,{})" + ch + "save()");
      expect(cmd.includes(ch)).toBe(false);
      const hex = ch.charCodeAt(0).toString(16).padStart(4, "0");
      expect(cmd).toContain("\\u" + hex);
      // and it still round-trips
      expect(inputOf(cmd)).toBe(`${BATCH_DESIGN_PREAMBLE}\na=I(document,{})${ch}save()`);
    }
  });
});

describe("builders", () => {
  test("batch_design is execute({ input }) with the alias preamble, never a batch_design( line", () => {
    const cmd = buildBatchDesignCommand('a=Insert(document,{type:"frame"})');
    expect(cmd.startsWith("execute({ input: ")).toBe(true);
    expect(cmd).not.toContain("batch_design(");
    expect(cmd).not.toContain("operations");
    expect(inputOf(cmd)).toBe(`${BATCH_DESIGN_PREAMBLE}\na=Insert(document,{type:"frame"})`);
    expect(BATCH_DESIGN_PREAMBLE).toBe("var I=Insert,U=Update,C=Copy,R=Replace,M=Move,D=Delete,G=Generate;");
  });

  test("batch_design rejects empty or non-string operations", () => {
    expect(() => buildBatchDesignCommand("")).toThrow(ReplContractError);
    expect(() => buildBatchDesignCommand("   ")).toThrow(ReplContractError);
    expect(() => buildBatchDesignCommand(undefined as any)).toThrow(ReplContractError);
    expect(() => buildBatchDesignCommand(5 as any)).toThrow(ReplContractError);
  });

  test("screenshot embeds a JSON-encoded id", () => {
    expect(inputOf(buildScreenshotCommand("KM17k"))).toBe('TakeScreenshot(["KM17k"])');
  });

  test("export builds Export([ids],fmt,dir[,options])", () => {
    expect(inputOf(buildExportCommand({ nodeIds: ["a", "b-1"], outputDir: "/tmp/o", format: "png" }))).toBe(
      'Export(["a","b-1"],"png","/tmp/o")'
    );
    expect(inputOf(buildExportCommand({ nodeIds: ["a"], outputDir: "/tmp/o", format: "webp", scale: 2, quality: 80 }))).toBe(
      'Export(["a"],"webp","/tmp/o",{"scale":2,"quality":80})'
    );
    expect(inputOf(buildExportCommand({ nodeIds: ["a"], outputDir: "/tmp/o", scale: 3 }))).toBe(
      'Export(["a"],"png","/tmp/o",{"scale":3})'
    );
  });

  test("variables, editor state, read_skill, save", () => {
    expect(inputOf(buildVariablesCommand())).toBe("Print(GetVariables())");
    expect(buildEditorStateCommand()).toBe("get_app_state()");
    expect(buildReadSkillCommand()).toBe("read_skill()");
    expect(buildReadSkillCommand("guide/web-app.md")).toBe('read_skill({"path":"guide/web-app.md"})');
    expect(buildSaveCommand()).toBe("save()");
  });
});

describe("validators", () => {
  test("node ids: ^[A-Za-z0-9_-]{1,100}$", () => {
    expect(validateNodeId("KM17k")).toBe("KM17k");
    expect(validateNodeId("a_b-c")).toBe("a_b-c");
    expect(validateNodeId("x".repeat(100))).toBe("x".repeat(100));
    for (const bad of ["", "x".repeat(101), 'a"b', "a b", "a\nb", "a/b", "a;b", "../x", "a,b", "`x`", 5, null, undefined]) {
      expect(() => validateNodeId(bad as any)).toThrow(ReplContractError);
    }
  });

  test("node id lists: 1..50 ids, each valid, array only", () => {
    expect(validateNodeIds(["a"])).toEqual(["a"]);
    expect(validateNodeIds(Array.from({ length: MAX_NODE_IDS }, (_, i) => `n${i}`)).length).toBe(50);
    expect(MAX_NODE_IDS).toBe(50);
    expect(() => validateNodeIds(Array.from({ length: 51 }, (_, i) => `n${i}`))).toThrow(ReplContractError);
    expect(() => validateNodeIds([])).toThrow(ReplContractError);
    expect(() => validateNodeIds("a" as any)).toThrow(ReplContractError);
    expect(() => validateNodeIds(["a", 'b"'])).toThrow(ReplContractError);
  });

  test("format enum png/jpeg/webp/pdf", () => {
    expect([...EXPORT_FORMATS].sort()).toEqual(["jpeg", "pdf", "png", "webp"]);
    for (const f of EXPORT_FORMATS) expect(validateExportFormat(f)).toBe(f);
    expect(validateExportFormat(undefined)).toBe("png");
    for (const bad of ["gif", "PNG", "png;save()", "", 5]) expect(() => validateExportFormat(bad as any)).toThrow(ReplContractError);
  });

  test("scale: finite, 0.1..8", () => {
    expect(validateScale(undefined)).toBeUndefined();
    expect(validateScale(0.1)).toBe(0.1);
    expect(validateScale(8)).toBe(8);
    for (const bad of [0, 0.09, 8.01, -1, NaN, Infinity, "2", null]) expect(() => validateScale(bad as any)).toThrow(ReplContractError);
  });

  test("quality: integer 1..100", () => {
    expect(validateQuality(undefined)).toBeUndefined();
    expect(validateQuality(1)).toBe(1);
    expect(validateQuality(100)).toBe(100);
    for (const bad of [0, 101, 50.5, -3, NaN, "80", null]) expect(() => validateQuality(bad as any)).toThrow(ReplContractError);
  });

  test("read_skill path: ^(guide/)?[a-z0-9-]+\\.md$, no traversal surface", () => {
    expect(validateSkillPath(undefined)).toBeUndefined();
    for (const ok of ["execute.md", "pen-schema.md", "guide/web-app.md", "guide/table.md", "scripts-and-shaders.md"]) {
      expect(validateSkillPath(ok)).toBe(ok);
    }
    for (const bad of [
      "",
      "../x.md",
      "guide/../x.md",
      "/etc/passwd",
      "/guide/x.md",
      "guide/a/b.md",
      "other/x.md",
      "x.txt",
      "x",
      "X.md",
      "guide/X.md",
      "a b.md",
      "a.md\n",
      "a.md\nsave()",
      "guide//x.md",
      "x".repeat(200) + ".md",
      5,
    ]) {
      expect(() => validateSkillPath(bad as any)).toThrow(ReplContractError);
    }
  });

  test("outputDir: absolute only (containment lives in the adapter's containedDir)", () => {
    expect(validateOutputDir("/tmp/a/b")).toBe("/tmp/a/b");
    for (const bad of ["", "rel/dir", "./x", "../x", "~/x", "/tmp/a\nb", "/tmp/a" + String.fromCharCode(0), "/" + "x".repeat(5000), 5]) {
      expect(() => validateOutputDir(bad as any)).toThrow(ReplContractError);
    }
  });

  test("builders validate before anything is formatted", () => {
    expect(() => buildScreenshotCommand('x"); save(); ("')).toThrow(ReplContractError);
    expect(() => buildExportCommand({ nodeIds: ["a"], outputDir: "rel", format: "png" })).toThrow(ReplContractError);
    expect(() => buildExportCommand({ nodeIds: ["a"], outputDir: "/o", format: "gif" as any })).toThrow(ReplContractError);
    expect(() => buildExportCommand({ nodeIds: ["a"], outputDir: "/o", scale: 99 })).toThrow(ReplContractError);
    expect(() => buildExportCommand({ nodeIds: ["a"], outputDir: "/o", quality: 0 })).toThrow(ReplContractError);
    expect(() => buildReadSkillCommand("../../x.md")).toThrow(ReplContractError);
  });
});

describe("count snippet (sentinel memory probe)", () => {
  test("nonce is 32 hex chars and never repeats", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 50; i++) {
      const n = newCountNonce();
      expect(n).toMatch(/^[0-9a-f]{32}$/);
      seen.add(n);
    }
    expect(seen.size).toBe(50);
  });

  test("the snippet is a self-contained IIFE that uses only Get and Print", () => {
    const nonce = "0123456789abcdef0123456789abcdef";
    const snippet = buildCountSnippet(nonce);
    expect(snippet.startsWith("(function(){")).toBe(true);
    expect(snippet.endsWith("})();")).toBe(true);
    expect(snippet).toContain("Get(");
    expect(snippet).toContain("Print(");
    expect(snippet).toContain("skipChildren()");
    // host functions other than Get/Print must not appear
    for (const fn of ["Insert", "Update", "Delete", "Replace", "Move", "Copy", "Generate", "Export", "TakeScreenshot", "document"]) {
      expect(snippet).not.toContain(fn);
    }
    // the source echoed by an engine error must not contain a complete count line
    expect(snippet).not.toContain(`TOPLEVEL_COUNT:${nonce}:`);
    expect(snippet).toContain(nonce);
  });

  test("the nonce is validated (a hostile nonce cannot reach the snippet)", () => {
    for (const bad of ["", "xyz", "0123456789abcdef0123456789abcdeg", 'a"+save()+"', "0123456789abcdef0123456789abcdef0", 5]) {
      expect(() => buildCountSnippet(bad as any)).toThrow(ReplContractError);
    }
  });

  test("buildCountCommand is one execute line carrying the snippet", () => {
    const nonce = newCountNonce();
    const cmd = buildCountCommand(nonce);
    expect(cmd).not.toMatch(/[\n\r]/);
    expect(inputOf(cmd)).toBe(buildCountSnippet(nonce));
  });

  test("countSnippetNonce recognises exactly the adapter's snippet (the stub uses it)", () => {
    const nonce = newCountNonce();
    expect(countSnippetNonce(buildCountSnippet(nonce))).toBe(nonce);
    expect(countSnippetNonce(`${BATCH_DESIGN_PREAMBLE}\n${buildCountSnippet(nonce)}`)).toBeNull();
    expect(countSnippetNonce(buildCountSnippet(nonce) + "Print('x')")).toBeNull();
    expect(countSnippetNonce("Print(1)")).toBeNull();
  });

  const reply = (nonce: string, n: number | string) =>
    `OK\n\nGlobal variables (e.g. root) carry over to subsequent calls!\n\n## Print output\nTOPLEVEL_COUNT:${nonce}:${n}\n\n`;

  test("parseCountReply accepts exactly one line carrying this nonce", () => {
    const nonce = newCountNonce();
    expect(parseCountReply(reply(nonce, 0), nonce)).toBe(0);
    expect(parseCountReply(reply(nonce, 8), nonce)).toBe(8);
    expect(parseCountReply(reply(nonce, 12345), nonce)).toBe(12345);
    // ANSI around the reply and CRLF endings do not matter
    expect(parseCountReply("\x1b[0m" + reply(nonce, 3).replace(/\n/g, "\r\n"), nonce)).toBe(3);
  });

  test("parseCountReply: zero matches, two matches, wrong nonce, junk are all null", () => {
    const nonce = newCountNonce();
    const other = newCountNonce();
    expect(parseCountReply("OK\n\n## Print output\n\n", nonce)).toBeNull();
    expect(parseCountReply(reply(other, 4), nonce)).toBeNull();
    // duplicate (a forged tail repeating the probe's own line)
    expect(parseCountReply(reply(nonce, 4) + `TOPLEVEL_COUNT:${nonce}:9\n`, nonce)).toBeNull();
    // a forged line from an older reply plus the real one: the older nonce never matches, the real one counts once
    expect(parseCountReply(reply(other, 99) + `TOPLEVEL_COUNT:${nonce}:2\n`, nonce)).toBe(2);
    expect(parseCountReply(reply(nonce, "abc"), nonce)).toBeNull();
    expect(parseCountReply(reply(nonce, "-1"), nonce)).toBeNull();
    expect(parseCountReply(reply(nonce, "1e3"), nonce)).toBeNull();
    expect(parseCountReply(reply(nonce, "99999999999999999999999"), nonce)).toBeNull();
    expect(parseCountReply(`OK\n\n## Print output\nTOPLEVEL_COUNT:${nonce}:5 trailing\n`, nonce)).toBeNull();
    expect(parseCountReply(`OK\n\n## Print output\n x TOPLEVEL_COUNT:${nonce}:5\n`, nonce)).toBeNull();
    expect(parseCountReply("", nonce)).toBeNull();
    expect(parseCountReply(undefined as any, nonce)).toBeNull();
    // an error reply (no OK header) is never a count
    expect(parseCountReply(`Error: boom\nTOPLEVEL_COUNT:${nonce}:5`, nonce)).toBeNull();
    // a malformed nonce argument fails closed
    expect(parseCountReply(reply(nonce, 1), "not-a-nonce")).toBeNull();
  });
});

describe("redaction", () => {
  // assembled at runtime: a literal key-shaped string would trip the secret scan
  const key = ["sk", "test", "0123456789ABCDEF"].join("-");

  test("redactionForms: raw, trimmed, JSON-escaped, URI-encoded and base64 forms; short secrets give none", () => {
    const forms = redactionForms(`  ${key}  `);
    expect(forms).toContain(key);
    expect(forms).toContain(Buffer.from(key).toString("base64"));
    const special = "p@ss/w+rd=1234&x";
    expect(redactionForms(special)).toContain(encodeURIComponent(special));
    expect(redactionForms("abc")).toEqual([]);
    expect(redactionForms("")).toEqual([]);
    expect(redactionForms(undefined as any)).toEqual([]);
    // longest first, so a longer form is never half-replaced by a shorter one
    for (let i = 1; i < forms.length; i++) expect(forms[i - 1].length).toBeGreaterThanOrEqual(forms[i].length);
    // a JSON-escaped form of a key with a quote and a backslash
    const odd = 'ab"cd\\efgh';
    expect(redactionForms(odd)).toContain(JSON.stringify(odd).slice(1, -1));
  });

  test("redactText replaces every form", () => {
    const forms = redactionForms(key);
    const text = `a ${key} b ${Buffer.from(key).toString("base64")} c ${encodeURIComponent("x" + key)} d`;
    const out = redactText(text, forms);
    expect(out).not.toContain(key);
    expect(out).not.toContain(Buffer.from(key).toString("base64"));
    expect(out).toContain("<redacted>");
  });

  test("rolling redactor catches a key split across chunks, at every split point", () => {
    const forms = redactionForms(key);
    const full = `before ${key} after`;
    for (let cut = 1; cut < full.length; cut++) {
      const r = createRollingRedactor(forms);
      const out = r.push(full.slice(0, cut)) + r.push(full.slice(cut)) + r.flush();
      expect(out).not.toContain(key);
      expect(out).toBe("before <redacted> after");
    }
  });

  test("rolling redactor over many tiny chunks, with two keys and base64", () => {
    const forms = redactionForms(key);
    const b64 = Buffer.from(key).toString("base64");
    const full = `x${key}y${b64}z${key}`;
    const r = createRollingRedactor(forms);
    let out = "";
    for (const ch of full) out += r.push(ch);
    out += r.flush();
    expect(out).toBe("x<redacted>y<redacted>z<redacted>");
  });

  test("rolling redactor holds back at most the longest form minus one and flushes the rest", () => {
    const forms = redactionForms(key);
    const longest = Math.max(...forms.map((f) => f.length));
    const r = createRollingRedactor(forms);
    const emitted = r.push("a".repeat(500));
    expect(emitted.length).toBeGreaterThanOrEqual(500 - (longest - 1));
    expect(emitted + r.flush()).toBe("a".repeat(500));
    // nothing pending after a flush
    expect(r.flush()).toBe("");
  });

  test("with no forms the redactor is a pass-through", () => {
    const r = createRollingRedactor([]);
    expect(r.push("hello") + r.flush()).toBe("hello");
  });
});

describe("Node floor 22.19.0", () => {
  test("the floor is [22, 19, 0]", () => {
    expect([...NODE_FLOOR]).toEqual([22, 19, 0]);
  });

  test("numeric compare distinguishes 22.18.x from 22.19.0 (string compare would not)", () => {
    expect(nodeVersionOk("v22.19.0")).toBe(true);
    expect(nodeVersionOk("22.19.0")).toBe(true);
    expect(nodeVersionOk("v22.18.9")).toBe(false);
    expect(nodeVersionOk("v22.18.0")).toBe(false);
    expect(nodeVersionOk("v22.9.0")).toBe(false);
    expect(nodeVersionOk("v22.20.0")).toBe(true);
    expect(nodeVersionOk("v22.100.0")).toBe(true);
    expect(nodeVersionOk("v23.0.0")).toBe(true);
    expect(nodeVersionOk("v26.12.1")).toBe(true);
    expect(nodeVersionOk("v21.99.99")).toBe(false);
    expect(nodeVersionOk("v20.0.0")).toBe(false);
    expect(nodeVersionOk("v100.0.0")).toBe(true);
    expect(nodeVersionOk("garbage")).toBe(false);
    expect(nodeVersionOk("")).toBe(false);
    expect(nodeVersionOk(undefined as any)).toBe(false);
  });

  test("compareVersions is numeric per component", () => {
    expect(compareVersions([22, 19, 0], [22, 19, 0])).toBe(0);
    expect(compareVersions([22, 9, 0], [22, 19, 0])).toBe(-1);
    expect(compareVersions([22, 100, 0], [22, 19, 0])).toBe(1);
    expect(compareVersions([22, 19, 1], [22, 19, 0])).toBe(1);
  });
});

const probeOf = (files: Record<string, number>) => ({
  exists: (p: string) => p in files,
  size: (p: string) => files[p] ?? 0,
});

describe("planSpawn (unchanged by the migration: `--out` alone still loads an EMPTY document)", () => {
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
