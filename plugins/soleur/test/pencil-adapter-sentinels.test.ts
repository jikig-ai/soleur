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
const gate = readFileSync(resolve(SCRIPTS, "pencil-save-gate.mjs"), "utf8");
const copyScript = readFileSync(resolve(SCRIPTS, "copy_adapter.sh"), "utf8");

// strip // comments (whole-line and trailing) and /* */ blocks so prose cannot
// satisfy or trip a scan. A trailing comment needs leading whitespace, so a
// "://" inside a string is left alone.
const stripComments = (src: string) =>
  src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((l) => l.replace(/^\s*\/\/.*$/, "").replace(/\s\/\/[^\n"'`]*$/, ""))
    .join("\n");
const code = stripComments(adapter);
const gateCode = stripComments(gate);

// A scan over an empty or truncated string passes vacuously: every scan below
// starts from these.
describe("the scans read real source", () => {
  test("adapter and gate are non-trivial after comment stripping", () => {
    expect(code.length).toBeGreaterThan(8000);
    expect(gateCode.length).toBeGreaterThan(3000);
    expect(code).toMatch(/async function guardedSave/);
    expect(gateCode).toMatch(/export async function runGuardedSave/);
  });
});

const count2 = (src: string, re: RegExp) => [...src.matchAll(re)].length;

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
      /logRefusal\(saved,\s*"save"\)/,
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

describe("Guard 1 — one emission, no raw save() literal anywhere else", () => {
  test("no `save()` REPL string is built by hand in the adapter or the gate (the surface module owns it)", () => {
    for (const src of [code, gateCode]) {
      expect(src).not.toMatch(/["'`]save\(\)["'`]/);
      expect(src).not.toMatch(/buildSaveCommand\(/); // the one emission goes through formatReplCommand("save", ...)
    }
  });

  test("the save command is emitted inside guardedSave's `send` dep and nowhere in the gate", () => {
    expect(gateCode).not.toMatch(/formatReplCommand/);
    const emission = code.match(/send:\s*async \(\) => send\(formatReplCommand\("save", \{\}\)\)/g) ?? [];
    expect(emission.length).toBe(1);
  });

  test("runGuardedSave is called from guardedSave only, and passes every guard hook", () => {
    const calls = [...code.matchAll(/runGuardedSave\(/g)];
    expect(calls.length).toBe(1);
    const fn = code.slice(code.indexOf("async function guardedSave"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    for (const hook of ["readDisk", "probeMemory", "readFresh", "getBaseline", "isRefusalPending", "send", "isConfirmed", "readAfterSave", "adoptBaseline"]) {
      expect(body).toMatch(new RegExp(`\\b${hook}\\b`));
    }
  });

  test("decideStale is called exactly once, inside runGuardedSave, after the memory probe and before the emission", () => {
    const calls = [...gateCode.matchAll(/\bdecideStale\(/g)].map((m) => m.index as number);
    // the definition `export function decideStale(` plus exactly one call
    expect(calls.length).toBe(2);
    const fnStart = gateCode.indexOf("export async function runGuardedSave");
    expect(fnStart).toBeGreaterThan(-1);
    const call = calls.find((i) => i > fnStart) as number;
    expect(call).toBeGreaterThan(fnStart);
    const probe = gateCode.indexOf("await probeMemory()", fnStart);
    const sendAt = gateCode.indexOf("await send()", fnStart);
    expect(probe).toBeGreaterThan(fnStart);
    expect(sendAt).toBeGreaterThan(call);
    expect(call).toBeGreaterThan(probe);
    expect(code).not.toMatch(/\bdecideStale\(/); // the adapter never decides on its own
  });
});

describe("Guard 1 — baseline sites (#11168)", () => {
  const count = (src: string, re: RegExp) => [...src.matchAll(re)].length;

  test("one capture, one commit, one adopt in the adapter; none in the gate", () => {
    expect(count(code, /\.capture\(/g)).toBe(1);
    expect(count(code, /\.commit\(/g)).toBe(1);
    expect(count(code, /\.adopt\(/g)).toBe(1);
    for (const re of [/\.capture\(/, /\.commit\(/, /\.adopt\(/, /\.clear\(/]) expect(gateCode).not.toMatch(re);
  });

  test("capture precedes nodeSpawn in spawn(), and commit follows the prompt wait", () => {
    const spawnAt = code.indexOf("async spawn(");
    expect(spawnAt).toBeGreaterThan(-1);
    const cap = code.indexOf(".capture(", spawnAt);
    const spawnCall = code.indexOf("nodeSpawn(", spawnAt);
    const prompt = code.indexOf("await this.waitForPrompt(", spawnAt);
    const commit = code.indexOf(".commit(", spawnAt);
    expect(cap).toBeGreaterThan(spawnAt);
    expect(cap).toBeLessThan(spawnCall);
    expect(commit).toBeGreaterThan(prompt);
  });

  test("clearTarget clears the baseline", () => {
    const fn = code.slice(code.indexOf("clearTarget()"));
    expect(fn.slice(0, fn.indexOf("\n  }\n"))).toMatch(/\.clear\(\)/);
  });

  test("SaveBaseline has #-private fields only: nothing outside the class can write the state", () => {
    const start = code.indexOf("class SaveBaseline");
    expect(start).toBeGreaterThan(-1);
    const body = code.slice(start, code.indexOf("\n}\n", start));
    expect(body).toMatch(/#state/);
    expect(body).not.toMatch(/\bthis\.(?!#)[A-Za-z_]+\s*=/);
    expect(code.slice(0, start) + code.slice(start + body.length)).not.toMatch(/\.#state/);
  });

  test("refusalPending is set in one place and cleared in one place", () => {
    expect(count(code, /^\s*refusalPending\s*=\s*true;/gm)).toBe(1);
    expect(count(code, /^\s*refusalPending\s*=\s*false;/gm)).toBe(1);
  });
});

describe("Observability — one logRefusal helper behind both save call sites", () => {
  test("logRefusal is defined once and called from the auto-save and the explicit save tool", () => {
    expect(count2(code, /function logRefusal\(/g)).toBe(1);
    const calls = [...code.matchAll(/\blogRefusal\(saved,\s*"([a-z-]+)"\)/g)].map((m) => m[1]).sort();
    expect(calls).toEqual(["auto-save", "save"]);
  });

  test("no other stderr write carries a REFUSED save line", () => {
    const writes = code.split("\n").filter((l) => /REFUSED save/.test(l));
    expect(writes.length).toBe(1);
    expect(writes[0]).toMatch(/\[reason=\$\{/);
  });

  test("every refusal state has its stderr marker", () => {
    for (const marker of [
      "refusalPending=true",
      "refusalPending=false",
      "respawn: refusalPending still armed, baseline not recaptured",
      "save unconfirmed: reply did not match the expected Saved line; baseline=unknown",
      "WARN post-save read failed",
    ]) {
      expect(adapter).toContain(marker);
    }
  });

  test("the success-side lines are pinned so a migration cannot drop them", () => {
    expect(adapter).toContain("[pencil-adapter] MCP server started on stdio");
    expect(adapter).toMatch(/Opened \$\{[A-Za-z.]+\} \(\$\{[^}]*\} top-level node\(s\) loaded\)/);
  });
});

describe("Credential and engine identity", () => {
  test("the key is resolved once into a const and both names are deleted from process.env", () => {
    expect(code).toMatch(/const API_KEY\b/);
    expect(code).toMatch(/delete process\.env\.PEN_CLI_KEY/);
    expect(code).toMatch(/delete process\.env\.PENCIL_CLI_KEY/);
    expect(code.match(/process\.env\.(PEN|PENCIL)_CLI_KEY/g)!.length).toBeLessThanOrEqual(8);
  });

  test("the child env carries PEN_CLI_KEY only, from the const", () => {
    const fn = code.slice(code.indexOf("function buildPencilEnv"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    expect(body).toMatch(/env\.PEN_CLI_KEY\s*=\s*API_KEY/);
    expect(body).not.toMatch(/PENCIL_CLI_KEY/);
  });

  test("the adapter's version pin equals the lockfile prefix's pin", () => {
    const pin = /const PEN_CLI_PIN = "([0-9.]+)"/.exec(code)?.[1];
    const prefix = JSON.parse(readFileSync(resolve(SCRIPTS, "pen-cli/package.json"), "utf8"));
    expect(pin).toBeDefined();
    expect(prefix.dependencies["@pen.dev/cli"]).toBe(pin);
  });

  test("the binary is resolved only inside ~/.local/share/pen-cli: no PATH walk, no pencil name", () => {
    const fn = code.slice(code.indexOf("function findPenBinary"));
    const body = fn.slice(0, fn.indexOf("\n}\n"));
    expect(body).toContain('"pen-cli"');
    expect(body).not.toMatch(/process\.env\.PATH/);
    expect(body).not.toMatch(/["'`]pencil["'`]/);
    expect(body).toMatch(/realpathSync/);
  });

  test("the child is spawned with the realpath'd binary, a private cwd and a filtered PATH", () => {
    expect(code).toMatch(/nodeSpawn\(process\.execPath,\s*\[binary,/);
    expect(code).toMatch(/cwd:\s*childCwd\(\)/);
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
