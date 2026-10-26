import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// #11143 source sentinels. They pin the shape of the adapter that the
// behavioural suites cannot see: how many places can emit `save`, whether any
// command bypasses formatReplCommand, and whether every sibling module the
// adapter imports is in copy_adapter.sh's install list.

const SCRIPTS = resolve(import.meta.dir, "../skills/pencil-setup/scripts");
const adapter = readFileSync(resolve(SCRIPTS, "pencil-mcp-adapter.mjs"), "utf8");
const copyScript = readFileSync(resolve(SCRIPTS, "copy_adapter.sh"), "utf8");

// strip // line comments and /* */ blocks so prose cannot satisfy or trip a scan
const code = adapter
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .split("\n")
  .map((l) => l.replace(/^\s*\/\/.*$/, ""))
  .join("\n");

describe("Guard 1 — one save chokepoint", () => {
  test("exactly one formatReplCommand(\"save\" emission, inside guardedSave", () => {
    const emissions = [...code.matchAll(/formatReplCommand\(\s*"save"/g)];
    expect(emissions.length).toBe(1);
    const at = emissions[0].index as number;
    const fnStart = code.lastIndexOf("async function guardedSave", at);
    expect(fnStart).toBeGreaterThan(-1);
    // no other top-level function starts between guardedSave and the emission
    const between = code.slice(fnStart + 10, at);
    expect(between).not.toMatch(/\n(async )?function /);
  });

  test("no string-literal enqueue( bypasses formatReplCommand", () => {
    expect(code).not.toMatch(/enqueue\(\s*["'`]/);
  });

  test("the legacy raw save() command is gone", () => {
    expect(code).not.toContain('"save()"');
  });
});

describe("Guard 3 — installed-adapter completeness", () => {
  const imported = [...code.matchAll(/await import\("\.\/([A-Za-z0-9_.-]+\.mjs)"\)/g)].map((m) => m[1]).sort();
  const listBlock = copyScript.match(/ADAPTER_FILES=\(([\s\S]*?)\n\)/);
  const listed = listBlock
    ? [...listBlock[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]).filter((f) => f.endsWith(".mjs"))
    : [];

  test("the parsed import set is the five known siblings", () => {
    expect(imported).toEqual(
      [
        "pencil-error-enrichment.mjs",
        "pencil-repl-surface.mjs",
        "pencil-response-classify.mjs",
        "pencil-save-gate.mjs",
        "sanitize-filename.mjs",
      ].sort()
    );
  });

  test("ADAPTER_FILES contains every imported sibling", () => {
    for (const f of imported) expect(listed).toContain(f);
  });

  test("copy_adapter.sh turns a missing source file into a hard error", () => {
    expect(copyScript).not.toMatch(/WARN: missing repo file/);
    expect(copyScript).toMatch(/ERROR: missing repo file/);
  });
});
