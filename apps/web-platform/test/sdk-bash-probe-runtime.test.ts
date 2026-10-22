// Runtime Bash synthetic (ADR-079 addendum 2026-10-20): the pure pieces of sdk-bash-probe.mjs that the runtime mode adds.
// The deploy smoke (SMOKE=1 alone) is pinned by sdk-bash-probe-parity.test.ts and must not move; this suite pins what the
// RUNNING-container synthetic changes: the selector comes from the host (which asked the dispatcher's own resolver), the
// coverage claim names THAT selector, and nothing is created outside the probe's scratch dirs.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import * as probe from "../infra/lib/sdk-bash-probe.mjs";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const probeSrc = readFileSync(join(APP_ROOT, "infra", "lib", "sdk-bash-probe.mjs"), "utf8");

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

describe("the runtime branch creates nothing outside the probe's scratch dirs", () => {
  // The deploy smoke creates the masked dirs (a canary container has none). The synthetic runs in the PRODUCTION container,
  // where those paths belong to real sessions: the runtime branch must not mkdir them.
  const runSmoke = probeSrc.slice(probeSrc.indexOf("async function runSmoke()"));

  it("the masked-dir mkdir loop is unreachable in runtime mode", () => {
    const loop = runSmoke.indexOf("for (const d of maskedDirs(uid, home)) mkdirSync(");
    expect(loop).toBeGreaterThan(-1);
    const guardLine = runSmoke.lastIndexOf("if (!runtime)", loop);
    expect(guardLine, "the deploy-mode mkdir loop must sit under `if (!runtime)`").toBeGreaterThan(-1);
    expect(loop - guardLine).toBeLessThan(120);
  });

  it("every mkdirSync/mkdtempSync in the smoke path is a scratch dir or the guarded loop", () => {
    const sites = runSmoke.split("\n").filter((l) => /mkdirSync\(|mkdtempSync\(/.test(l) && !l.trim().startsWith("//"));
    for (const l of sites) {
      expect(l, l).toMatch(/mkdtempSync\(`\$\{tmp\}\/sdk-bash-probe-(cfg-)?`\)|for \(const d of maskedDirs\(uid, home\)\) mkdirSync\(/);
    }
    expect(sites.length).toBe(3);
  });

  it("runtime mode reports its selector and the missing-mask count in the result line", () => {
    expect(runSmoke).toContain("masks_missing");
    expect(runSmoke).toContain("selector");
  });
});
