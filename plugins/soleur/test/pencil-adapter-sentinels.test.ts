import { describe, test, expect } from "bun:test";
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

// #11143 source sentinels. They pin the shape of the adapter that the
// behavioural suites cannot see: how many places can emit `save`, whether any
// command bypasses formatReplCommand, and whether every sibling module the
// adapter imports is in copy_adapter.sh's install list.

const SCRIPTS = resolve(import.meta.dir, "../skills/pencil-setup/scripts");
const adapter = readFileSync(resolve(SCRIPTS, "pencil-mcp-adapter.mjs"), "utf8");
const copyScript = readFileSync(resolve(SCRIPTS, "copy_adapter.sh"), "utf8");

// strip // comments (whole-line and trailing) and /* */ blocks so prose cannot
// satisfy or trip a scan. A trailing comment needs leading whitespace, so a
// "://" inside a string is left alone.
const code = adapter
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .split("\n")
  .map((l) => l.replace(/^\s*\/\/.*$/, "").replace(/\s\/\/[^\n"'`]*$/, ""))
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

  test("no string-literal command reaches the queue or the process, in any quote style", () => {
    for (const sink of ["enqueue", "sendCommand", "send"]) {
      expect(code).not.toMatch(new RegExp(`\\b${sink}\\(\\s*["'\`]`));
    }
    expect(code).not.toMatch(/stdin\.write\(\s*["'`]/);
  });

  test("the word save appears as a string literal only at the three sanctioned sites", () => {
    // Catches a tool registered under the name `save` through a registerReadOnlyTool /
    // registerMutatingTool spelling, whose variable-name formatReplCommand(name, ...)
    // emission the literal-first-argument scan cannot see.
    const allowed = [
      /formatReplCommand\(\s*"save"/,
      /registerTool\(\s*"save"/,
      /guardedSave\(send,\s*"save"/,
    ];
    const offenders = code
      .split("\n")
      .filter((l) => /["'`]save(?:\(\))?["'`]/.test(l))
      .filter((l) => !allowed.some((a) => a.test(l)));
    expect(offenders).toEqual([]);
  });

  test("guardedSave is only ever called from inside an exclusive job (it receives that job's send)", () => {
    expect(code).not.toMatch(/guardedSave\((?!send\b)/);
    const calls = [...code.matchAll(/guardedSave\(send,/g)].length;
    expect(calls).toBeGreaterThanOrEqual(3); // definition + auto-save + explicit save
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

  test("copy_adapter.sh turns a missing source file into a hard error before copying anything", () => {
    const work = mkdtempSync(join(tmpdir(), "pencil-copy-it-"));
    try {
      const scripts = join(work, "scripts");
      cpSync(SCRIPTS, scripts, {
        recursive: true,
        filter: (src) => !src.includes("node_modules"),
      });
      rmSync(join(scripts, "pencil-save-gate.mjs"));
      const install = join(work, "install");
      const r = spawnSync("bash", [join(scripts, "copy_adapter.sh")], {
        env: { ...process.env, PENCIL_ADAPTER_INSTALL_DIR: install },
        encoding: "utf8",
      });
      expect(r.status).toBe(1);
      expect(r.stderr).toMatch(/ERROR: missing repo file .*pencil-save-gate\.mjs/);
      // validate-all-first: no mixed-version install is left behind
      expect(existsSync(install) ? readdirSync(install) : []).toEqual([]);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });
});
