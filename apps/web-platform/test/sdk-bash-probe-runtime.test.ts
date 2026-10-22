// Runtime Bash synthetic (ADR-079 "Addendum — 2026-10-22 (#10455 b)"): the pure pieces of sdk-bash-probe.mjs that the runtime mode adds.
// The deploy smoke (SMOKE=1 alone) is pinned by sdk-bash-probe-parity.test.ts and must not move; this suite pins what the
// RUNNING-container synthetic changes: the selector comes from the host (which asked the dispatcher's own resolver), the
// coverage claim names THAT selector, and nothing is created outside the probe's scratch dirs.
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import * as probe from "../infra/lib/sdk-bash-probe.mjs";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PROBE_PATH = join(APP_ROOT, "infra", "lib", "sdk-bash-probe.mjs");
const probeSrc = readFileSync(PROBE_PATH, "utf8");

describe("runtimeSelectorPath", () => {
  it("maps exactly the two artifact names to the pinned paths", () => {
    expect(probe.runtimeSelectorPath("base")).toBe(probe.SMOKE_SELECTOR_PATHS.base);
    expect(probe.runtimeSelectorPath("unixdeny")).toBe(probe.SMOKE_SELECTOR_PATHS.unixdeny);
  });

  it("refuses everything else, including path-shaped and prototype-shaped values", () => {
    for (const bad of ["", "BASE", " base", "base\n", "../../etc/passwd", "/app/infra/other.bpf", "__proto__", "constructor", undefined, null]) {
      expect(probe.runtimeSelectorPath(bad as unknown as string), String(bad)).toBeNull();
    }
  });
});

describe("smokeCoverage names the selector it was asked to verify", () => {
  const base = probe.SMOKE_SELECTOR_PATHS.base;
  const unixdeny = probe.SMOKE_SELECTOR_PATHS.unixdeny;

  it("the deploy-smoke call shape (no expectedPath) is unchanged: only the pinned unixdeny path is full", () => {
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: unixdeny })).toBe(probe.SMOKE_COVERAGE_FULL);
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: base })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
  });

  it("with an expectedPath, full only when the artifact in use IS that path and shim and filter hold", () => {
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: base, expectedPath: base })).toBe(probe.SMOKE_COVERAGE_FULL);
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: unixdeny, expectedPath: unixdeny })).toBe(probe.SMOKE_COVERAGE_FULL);
    // the other direction: asking for base but running unixdeny (or the reverse) is not the tuple that was asked for
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: unixdeny, expectedPath: base })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: base, expectedPath: unixdeny })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
    expect(probe.smokeCoverage({ shim: false, filter: true, bpfPath: base, expectedPath: base })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
    expect(probe.smokeCoverage({ shim: true, filter: false, bpfPath: base, expectedPath: base })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
  });
});

describe("runtimeMaskedDirs: observe, never create", () => {
  const uid = 1001;
  const home = "/home/soleur";
  const all = probe.maskedDirs(uid, home);

  it("keeps the masks that exist and counts the ones that do not, calling nothing but the injected predicate", () => {
    const seen: string[] = [];
    const exists = (p: string) => {
      seen.push(p);
      return p === all[0];
    };
    const r = probe.runtimeMaskedDirs(uid, home, exists);
    expect(r.present).toEqual([all[0]]);
    expect(r.missing).toBe(2);
    expect(seen).toEqual(all);
  });

  it("all present: nothing missing; none present: all missing", () => {
    expect(probe.runtimeMaskedDirs(uid, home, () => true)).toEqual({ present: all, missing: 0 });
    expect(probe.runtimeMaskedDirs(uid, home, () => false)).toEqual({ present: [], missing: 3 });
  });
});

describe("smokeSandboxConfig with an explicit mask list", () => {
  const args = { workspace: "/tmp/ws", uid: 1001, home: "/home/soleur" };

  it("default (no masked) is byte-identical to the deploy-smoke config", () => {
    expect(probe.smokeSandboxConfig(args)).toEqual(probe.smokeSandboxConfig({ ...args, masked: probe.maskedDirs(1001, "/home/soleur") }));
  });

  it("a shorter mask list removes exactly the dropped entries and nothing else", () => {
    const full = probe.smokeSandboxConfig(args).filesystem.denyRead;
    const kept = probe.maskedDirs(1001, "/home/soleur").slice(0, 1);
    const cut = probe.smokeSandboxConfig({ ...args, masked: kept }).filesystem.denyRead;
    expect(cut).toEqual(full.filter((d: string) => !probe.maskedDirs(1001, "/home/soleur").slice(1).includes(d)));
  });
});

describe("planSmoke: every mode decision of runSmoke, as one pure value", () => {
  const uid = 1001;
  const home = "/home/soleur";
  const all = probe.maskedDirs(uid, home);
  const never = () => {
    throw new Error("deploy mode must not look at the filesystem");
  };

  it("deploy mode (SDK_BASH_PROBE_RUNTIME unset): the pinned unixdeny artifact, every masked dir applied AND created, a stray selector env ignored", () => {
    const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_SELECTOR: "base" }, uid, home, exists: never });
    expect(plan).toEqual({
      runtime: false,
      selectorName: "unixdeny",
      selectedPath: probe.SMOKE_SELECTOR_PATHS.unixdeny,
      masked: all,
      masksMissing: 0,
      mkdir: all,
    });
  });

  it("runtime mode honours the selector NAME and expects exactly that artifact", () => {
    for (const name of ["base", "unixdeny"] as const) {
      const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: name }, uid, home, exists: () => true });
      expect(plan.runtime).toBe(true);
      expect(plan.selectorName).toBe(name);
      expect(plan.selectedPath).toBe(probe.SMOKE_SELECTOR_PATHS[name]);
    }
  });

  it("runtime mode never creates a directory, whatever exists: masks the ones that exist and counts the rest", () => {
    const env = { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: "base" };
    const none = probe.planSmoke({ env, uid, home, exists: () => false });
    expect(none).toMatchObject({ masked: [], masksMissing: 3, mkdir: [] });
    const some = probe.planSmoke({ env, uid, home, exists: (d: string) => d === all[1] });
    expect(some).toMatchObject({ masked: [all[1]], masksMissing: 2, mkdir: [] });
    const every = probe.planSmoke({ env, uid, home, exists: () => true });
    expect(every).toMatchObject({ masked: all, masksMissing: 0, mkdir: [] });
  });

  it("runtime mode with an unknown or missing selector has no artifact (the caller reports selector_invalid)", () => {
    for (const sel of [undefined, "", "BASE", "../x", "__proto__", "/app/infra/other.bpf"]) {
      const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: sel }, uid, home, exists: () => true });
      expect(plan.selectedPath, String(sel)).toBeNull();
      expect(plan.mkdir, String(sel)).toEqual([]);
    }
  });

  it("only the exact string \"1\" turns runtime mode on", () => {
    for (const v of ["", "0", "true", "yes", "11"]) {
      expect(probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: v }, uid, home, exists: never }).runtime, v).toBe(false);
    }
  });
});

describe("runSmoke is wired to planSmoke, not to its own copy of the decisions", () => {
  const runSmoke = probeSrc.slice(probeSrc.indexOf("async function runSmoke()"));
  const code = runSmoke.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");

  it("creates masked dirs only from plan.mkdir, and applies plan.masked", () => {
    expect(code.match(/mkdirSync\(/g)?.length).toBe(1);
    expect(code).toContain("for (const d of plan.mkdir) mkdirSync(d, { recursive: true, mode: 0o700 });");
    expect(code).toContain("const { runtime, selectorName, selectedPath, masked, masksMissing } = plan;");
    expect(code).toContain("smokeSandboxConfig({ workspace: ws, uid, home, masked })");
  });

  it("every other filesystem write in the smoke path is a scratch dir the probe made, or the day-old sweep of its own leftovers", () => {
    const mk = code.split("\n").filter((l) => /mkdtempSync\(/.test(l));
    expect(mk.map((l) => l.trim())).toEqual([
      "const ws = mkdtempSync(`${tmp}/sdk-bash-probe-`);",
      "const cfg = mkdtempSync(`${tmp}/sdk-bash-probe-cfg-`);",
    ]);
    const rm = code.split("\n").filter((l) => /rmSync\(/.test(l));
    expect(rm.map((l) => l.trim().replace(/\s+/g, " "))).toEqual([
      "try { rmSync(d, { recursive: true, force: true }); } catch { /* best-effort */ }",
      "try { rmSync(d, { recursive: true, force: true }); } catch { /* best-effort scratch cleanup */ }",
    ]);
  });

  it("the scratch is removed on every exit path: an exit handler (covers every infra() exit) and a SIGTERM handler that exits", () => {
    expect(code).toContain('process.on("exit", cleanup);');
    expect(code).toContain('process.on("SIGTERM", () => process.exit(143));');
  });

  it("runtime mode hands the SDK child a temp base inside the scratch config dir (never the shared /tmp/claude-<uid>)", () => {
    expect(code).toContain("...(runtime ? scratchEnv(cfg) : { CLAUDE_CONFIG_DIR: cfg }),");
    expect(code).toContain('if (runtime && !cliTmpBaseOk(cfg, uid)) infra("cli_tmp_path_too_long");');
  });
});

describe("scratchEnv / cliTmpBaseOk: the SDK child's temp base is the probe's scratch dir", () => {
  it("CLAUDE_CONFIG_DIR, CLAUDE_CODE_TMPDIR and TMPDIR all point at the scratch config dir", () => {
    expect(probe.scratchEnv("/tmp/sdk-bash-probe-cfg-AbC123")).toEqual({
      CLAUDE_CONFIG_DIR: "/tmp/sdk-bash-probe-cfg-AbC123",
      CLAUDE_CODE_TMPDIR: "/tmp/sdk-bash-probe-cfg-AbC123",
      TMPDIR: "/tmp/sdk-bash-probe-cfg-AbC123",
    });
  });

  it("the CLI falls back to the SHARED dir when its per-uid dir exceeds 44 bytes: a real mkdtemp path under /tmp must fit", () => {
    // `${tmp}/sdk-bash-probe-cfg-` + the 6 random characters mkdtemp adds, then `/claude-<uid>`
    expect(probe.cliTmpBaseOk("/tmp/sdk-bash-probe-cfg-AbC123", 1001)).toBe(true);
    expect(probe.cliTmpBaseOk("/tmp/sdk-bash-probe-cfg-AbC123", 65534)).toBe(true);
    expect(probe.cliTmpBaseOk("/var/tmp/some/long/prefix/sdk-bash-probe-cfg-AbC123", 1001)).toBe(false);
    expect(Buffer.byteLength("/tmp/sdk-bash-probe-cfg-AbC123/claude-1001")).toBeLessThanOrEqual(44);
  });
});

describe("staleScratchDirs: sweep only the probe's own day-old leftovers", () => {
  const NOW = 1_700_000_000_000;
  const DAY = 24 * 3600 * 1000;
  const entries: Record<string, { dir: boolean; uid: number; age: number }> = {
    "sdk-bash-probe-old": { dir: true, uid: 1001, age: 2 * DAY },
    "sdk-bash-probe-cfg-old": { dir: true, uid: 1001, age: 3 * DAY },
    "sdk-bash-probe-fresh": { dir: true, uid: 1001, age: 1000 },
    "sdk-bash-probe-otheruser": { dir: true, uid: 0, age: 5 * DAY },
    "sdk-bash-probe-afile": { dir: false, uid: 1001, age: 5 * DAY },
    "claude-1001": { dir: true, uid: 1001, age: 9 * DAY },
    "cc-socks": { dir: true, uid: 1001, age: 9 * DAY },
  };
  const deps = {
    readdir: () => Object.keys(entries),
    lstat: (p: string) => {
      const e = entries[p.split("/").pop() as string];
      return { isDirectory: () => e.dir, uid: e.uid, mtimeMs: NOW - e.age };
    },
  };

  it("removes day-old sdk-bash-probe-* directories of this uid, and nothing else (not a fresh run, another user's, a file, or any other /tmp entry)", () => {
    expect(probe.staleScratchDirs("/tmp", NOW, 1001, deps).sort()).toEqual(["/tmp/sdk-bash-probe-cfg-old", "/tmp/sdk-bash-probe-old"]);
  });

  it("an unreadable tmp dir sweeps nothing", () => {
    expect(probe.staleScratchDirs("/tmp", NOW, 1001, { readdir: () => { throw new Error("EACCES"); }, lstat: deps.lstat })).toEqual([]);
  });
});

describe("runSmoke executed as a process (the early exits need no SDK, no docker, no network)", () => {
  const nonce = "0123456789abcdef0123456789abcdef";
  const run = (env: Record<string, string>) => {
    const r = spawnSync(process.execPath, [PROBE_PATH], { env: { PATH: process.env.PATH ?? "", NODE_ENV: "production", HOME: "/home/soleur", SMOKE: "1", NONCE: nonce, ...env }, encoding: "utf8", timeout: 20000 });
    const line = r.stdout.split("\n").find((l) => l.startsWith("SDK_BASH_RESULT "));
    return { rc: r.status, result: line ? JSON.parse(line.slice("SDK_BASH_RESULT ".length)) : null, stdout: r.stdout };
  };

  it("runtime mode with a selector that is not base|unixdeny: smoke_infra_error selector_invalid, rc 0, nothing dispatched", () => {
    for (const sel of ["bogus", "", "BASE", "../../etc/passwd"]) {
      const { rc, result, stdout } = run({ SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: sel });
      expect(rc, sel).toBe(0);
      expect(result, sel).toMatchObject({ verdict: "smoke_infra_error", reason: "selector_invalid" });
      expect(stdout, sel).not.toContain("SDK_BASH_DISPATCHED");
    }
  });

  it("deploy mode ignores SDK_BASH_PROBE_SELECTOR entirely: the same bogus selector gets past the selector check (it stops later, at the missing SDK)", () => {
    const { result } = run({ SDK_BASH_PROBE_SELECTOR: "bogus", APP: "/nonexistent-app-root" });
    expect(result.reason).toMatch(/^sdk_module_unavailable/);
  });

  it("a malformed nonce and a relative HOME are refused first, in both modes", () => {
    expect(run({ NONCE: "XYZ" }).result).toMatchObject({ verdict: "smoke_infra_error", reason: "nonce_missing_or_malformed" });
    expect(run({ HOME: "relative" }).result).toMatchObject({ verdict: "smoke_infra_error", reason: "home_not_absolute" });
  });

  it("runtime mode leaves no scratch behind on an early exit (nothing is created before the SDK loads)", () => {
    const before = execFileSync("ls", ["/tmp"], { encoding: "utf8" }).split("\n").filter((n) => n.startsWith("sdk-bash-probe-")).length;
    run({ SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: "bogus" });
    const after = execFileSync("ls", ["/tmp"], { encoding: "utf8" }).split("\n").filter((n) => n.startsWith("sdk-bash-probe-")).length;
    expect(after).toBe(before);
  });
});
