// Runtime Bash synthetic (ADR-079 "Addendum — 2026-10-22 (#10455 b)"): the pure pieces of sdk-bash-probe.mjs that the runtime mode adds.
// The deploy smoke (SMOKE=1 alone) is pinned by sdk-bash-probe-parity.test.ts and must not move; this suite pins what the
// RUNNING-container synthetic changes: the selector comes from the host (which asked the dispatcher's own resolver), the
// coverage claim names THAT selector, and the only directories it creates outside its scratch dirs are the closed
// production masked set (precreateDirs), through ensureMaskedDirs and under the PID-1 uid and HOME guards (ADR-079 addendum 2026-10-23).
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { closeSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";

import * as probe from "../infra/lib/sdk-bash-probe.mjs";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PROBE_PATH = join(APP_ROOT, "infra", "lib", "sdk-bash-probe.mjs");
const probeSrc = readFileSync(PROBE_PATH, "utf8");
const SYNTHETIC_PATH = join(APP_ROOT, "infra", "web-bash-synthetic.sh");
const RUNBOOK_PATH = join(APP_ROOT, "..", "..", "knowledge-base", "engineering", "operations", "runbooks", "canary-probe-set.md");

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

describe("precreateDirs: the closed set the runtime probe may create", () => {
  it("is maskedDirs plus the session tmp root (4 dirs), and runtimeMaskedDirs is gone", () => {
    expect(probe.SESSION_TMP_ROOT).toBe("/tmp/.cs");
    expect(probe.precreateDirs(1001, "/home/soleur")).toEqual(["/tmp/cc-socks", "/tmp/cc-socks-1001", "/home/soleur/.claude/projects", "/tmp/.cs"]);
    expect((probe as Record<string, unknown>).runtimeMaskedDirs).toBeUndefined();
  });
});

// ---- ensureMaskedDirs (Guard 3): I/O injected, an in-memory filesystem -----------------------------------------------------------
type Ent = { dir?: boolean; link?: boolean; uid: number };
function fakeFs(initial: Record<string, Ent>, opts: { mkdirFails?: Set<string>; mkdirNoop?: Set<string>; lstatErr?: Record<string, string>; me?: number } = {}) {
  const me = opts.me ?? 1001;
  const ents: Record<string, Ent> = { ...initial };
  const mkdirCalls: Array<[string, unknown]> = [];
  const lstatCalls: string[] = [];
  const err = (code: string) => Object.assign(new Error(code), { code });
  return {
    ents,
    mkdirCalls,
    lstatCalls,
    lstat: (p: string) => {
      lstatCalls.push(p);
      if (opts.lstatErr?.[p]) throw err(opts.lstatErr[p]);
      const e = ents[p];
      if (!e) throw err("ENOENT");
      return { isDirectory: () => e.dir === true && e.link !== true, isSymbolicLink: () => e.link === true, uid: e.uid };
    },
    mkdir: (p: string, o: unknown) => {
      mkdirCalls.push([p, o]);
      if (opts.mkdirFails?.has(p)) throw err("EACCES");
      if (opts.mkdirNoop?.has(p)) return;
      ents[p] = { dir: true, uid: me };
    },
  };
}

describe("ensureMaskedDirs: create only what is absent, only as PID 1's uid, with production's own mkdir call", () => {
  const uid = 1001;
  const home = "/home/soleur";
  const dirs = probe.precreateDirs(uid, home);
  const homeDirs = [`${home}/.claude/projects`];
  const okPid1 = { uid, euid: uid, env: { homeMatches: true, divergent: false } };
  const run = (fs: ReturnType<typeof fakeFs>, ...rest: [unknown?]) =>
    probe.ensureMaskedDirs({ dirs, homeDirs, uid, pid1: rest.length ? rest[0] : okPid1, lstat: fs.lstat, mkdir: fs.mkdir });

  it("a cold container: all four are created with mkdir(dir, { recursive: true, mode: 0o700 }) and nothing else", () => {
    const fs = fakeFs({});
    const r = run(fs);
    expect(r).toEqual({ created: 4, failed: [], note: null });
    expect(fs.mkdirCalls).toEqual(dirs.map((d) => [d, { recursive: true, mode: 0o700 }]));
  });

  it("two runs in a row: the second creates nothing and does not call mkdir at all", () => {
    const fs = fakeFs({});
    run(fs);
    fs.mkdirCalls.length = 0;
    expect(run(fs)).toEqual({ created: 0, failed: [], note: null });
    expect(fs.mkdirCalls).toEqual([]);
  });

  it("an existing 0755 directory owned by the probe uid is fine and untouched (mode is not asserted)", () => {
    const fs = fakeFs({ [dirs[0]]: { dir: true, uid } });
    const r = run(fs);
    expect(r.failed).toEqual([]);
    expect(r.created).toBe(3);
    expect(fs.mkdirCalls.map((c) => c[0])).not.toContain(dirs[0]);
  });

  it("a foreign-owned directory and a symlink are failed, and are never replaced or re-created", () => {
    const fs = fakeFs({ [dirs[0]]: { dir: true, uid: 0 }, [dirs[1]]: { dir: true, link: true, uid } });
    const r = run(fs);
    expect(r.failed).toEqual([dirs[0], dirs[1]]);
    expect(r.created).toBe(2);
    expect(fs.mkdirCalls.map((c) => c[0])).toEqual([dirs[2], dirs[3]]);
  });

  it("a regular file in the way is failed and left alone", () => {
    const fs = fakeFs({ [dirs[3]]: { dir: false, uid } });
    expect(run(fs).failed).toEqual([dirs[3]]);
    expect(fs.mkdirCalls.map((c) => c[0])).not.toContain(dirs[3]);
  });

  it("a mkdir error fails THAT dir and the loop carries on to the rest", () => {
    const fs = fakeFs({}, { mkdirFails: new Set([dirs[0]]) });
    const r = run(fs);
    expect(r.failed).toEqual([dirs[0]]);
    expect(r.created).toBe(3);
    expect(fs.mkdirCalls.map((c) => c[0])).toEqual(dirs);
  });

  it("a mkdir that returns without producing the directory is failed, and is not counted as created", () => {
    const fs = fakeFs({}, { mkdirNoop: new Set([dirs[2]]) });
    const r = run(fs);
    expect(r.failed).toEqual([dirs[2]]);
    expect(r.created).toBe(3);
  });

  it("an lstat error other than ENOENT is not 'absent': nothing is created and the dir is failed", () => {
    const fs = fakeFs({}, { lstatErr: { [dirs[1]]: "EACCES" } });
    const r = run(fs);
    expect(r.failed).toEqual([dirs[1]]);
    expect(fs.mkdirCalls.map((c) => c[0])).not.toContain(dirs[1]);
  });

  describe("PID-1 uid guard: all creation stops", () => {
    it("uid_mismatch: the probe uid differs from PID 1's real uid", () => {
      const fs = fakeFs({ [dirs[0]]: { dir: true, uid } });
      const r = run(fs, { uid: 0, euid: 0, env: okPid1.env });
      expect(fs.mkdirCalls).toEqual([]);
      expect(r).toEqual({ created: 0, failed: [dirs[1], dirs[2], dirs[3]], note: "uid_mismatch" });
    });

    it("uid_mismatch on the EFFECTIVE uid alone (a setuid/seteuid PID 1): real matches, effective does not, and the reverse", () => {
      for (const pid1 of [{ uid, euid: 0, env: okPid1.env }, { uid: 0, euid: uid, env: okPid1.env }, { uid, env: okPid1.env }]) {
        const fs = fakeFs({});
        const r = run(fs, pid1);
        expect(fs.mkdirCalls, JSON.stringify(pid1)).toEqual([]);
        expect(r, JSON.stringify(pid1)).toEqual({ created: 0, failed: dirs, note: "uid_mismatch" });
      }
    });

    it("uid_mismatch when the PROBE's own effective uid differs from PID 1's (real matches): nothing is created; euid defaults to uid", () => {
      for (const probeEuid of [0, 1002]) {
        const fs = fakeFs({});
        const r = probe.ensureMaskedDirs({ dirs, homeDirs, uid, euid: probeEuid, pid1: okPid1, lstat: fs.lstat, mkdir: fs.mkdir });
        expect(fs.mkdirCalls, String(probeEuid)).toEqual([]);
        expect(r, String(probeEuid)).toEqual({ created: 0, failed: dirs, note: "uid_mismatch" });
      }
      // both pairs equal and non-trivially split (real 1001, effective 0 on both sides): the guard passes (the ownership check judges the result)
      const fs = fakeFs({});
      const same = probe.ensureMaskedDirs({ dirs, homeDirs, uid, euid: 0, pid1: { uid, euid: 0, env: okPid1.env }, lstat: fs.lstat, mkdir: fs.mkdir });
      expect(same.note).toBeNull();
      expect(fs.mkdirCalls.length).toBe(4);
      // omitted euid behaves as euid === uid
      const fs2 = fakeFs({});
      expect(probe.ensureMaskedDirs({ dirs, homeDirs, uid, pid1: okPid1, lstat: fs2.lstat, mkdir: fs2.mkdir })).toEqual({ created: 4, failed: [], note: null });
    });

    it("pid1_unreadable: PID 1's uid could not be read (undefined, never 'assume equal')", () => {
      for (const pid1 of [{ uid: undefined, env: okPid1.env }, { env: okPid1.env }, undefined, null]) {
        const fs = fakeFs({});
        const r = run(fs, pid1);
        expect(fs.mkdirCalls, String(pid1)).toEqual([]);
        expect(r.note, String(pid1)).toBe("pid1_unreadable");
        expect(r.failed.length, String(pid1)).toBe(4);
      }
    });

    it("uid_mismatch outranks every other note, and pid1_unreadable outranks the env ones", () => {
      expect(run(fakeFs({}), { uid: 0, euid: 0, env: null }).note).toBe("uid_mismatch");
      expect(run(fakeFs({}), { uid: undefined, euid: undefined, env: null }).note).toBe("pid1_unreadable");
    });
  });

  describe("HOME guard: refuse ONLY the HOME-derived dir, still create the other three", () => {
    it("pid1_env_unreadable: /proc/1/environ could not be read", () => {
      const fs = fakeFs({});
      const r = run(fs, { uid, euid: uid, env: null });
      expect(r).toEqual({ created: 3, failed: [dirs[2]], note: "pid1_env_unreadable" });
      expect(fs.mkdirCalls.map((c) => c[0])).toEqual([dirs[0], dirs[1], dirs[3]]);
    });

    it("home_mismatch: PID 1's HOME is not the probe's HOME", () => {
      const fs = fakeFs({});
      const r = run(fs, { uid, euid: uid, env: { homeMatches: false, divergent: false } });
      expect(r).toEqual({ created: 3, failed: [dirs[2]], note: "home_mismatch" });
      expect(fs.mkdirCalls.map((c) => c[0])).not.toContain(dirs[2]);
    });

    it("a refused HOME-derived dir that already exists as a real directory is simply present (nothing to create)", () => {
      const fs = fakeFs({ [dirs[2]]: { dir: true, uid } });
      expect(run(fs, { uid, euid: uid, env: { homeMatches: false, divergent: false } })).toEqual({ created: 3, failed: [], note: "home_mismatch" });
    });

    it("home_mismatch outranks env_divergence", () => {
      expect(run(fakeFs({}), { uid, euid: uid, env: { homeMatches: false, divergent: true } }).note).toBe("home_mismatch");
    });
  });

  it("env_divergence is informational: all four are created, none counted missing", () => {
    const fs = fakeFs({});
    expect(run(fs, { uid, euid: uid, env: { homeMatches: true, divergent: true } })).toEqual({ created: 4, failed: [], note: "env_divergence" });
  });

  it("works against the REAL filesystem: creates 0700 dirs as this uid, and a symlink-to-directory is failed, never followed or replaced", () => {
    const root = realpathSync(mkdtempSync(join(tmpdir(), "ensure-masks-")));
    try {
      const me = process.getuid!();
      const a = join(root, "a", "nested");
      const target = join(root, "target");
      const link = join(root, "link");
      mkdirSync(target);
      symlinkSync(target, link);
      const r = probe.ensureMaskedDirs({ dirs: [a, link], homeDirs: [], uid: me, pid1: { uid: me, euid: me, env: { homeMatches: true, divergent: false } }, lstat: lstatSync, mkdir: mkdirSync });
      expect(r).toEqual({ created: 1, failed: [link], note: null });
      expect(statSync(a).mode & 0o777).toBe(0o700 & ~process.umask());
      expect(lstatSync(link).isSymbolicLink()).toBe(true);
      expect(readdirSync(target)).toEqual([]);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});

describe("maskFields: the result-JSON fields, and nothing else", () => {
  it("maps the ensureMaskedDirs result to masks_missing / masks_created / masks_note", () => {
    expect(probe.maskFields({ created: 3, failed: ["/a"], note: "home_mismatch" })).toEqual({ masks_missing: 1, masks_created: 3, masks_note: "home_mismatch" });
    expect(probe.maskFields({ created: 0, failed: [], note: null })).toEqual({ masks_missing: 0, masks_created: 0, masks_note: null });
  });
});

// ---- PID 1 reads: narrow, capped, and no value ever leaves the parser ------------------------------------------------------------------
describe("parsePid1Uids: the REAL and EFFECTIVE uid are the first two Uid: fields of /proc/1/status", () => {
  it("reads the first two fields, not the saved/fs ones", () => {
    expect(probe.parsePid1Uids("Name:\tnode\nUmask:\t0022\nUid:\t1001\t0\t7\t8\nGid:\t1001\t1001\t1001\t1001\n")).toEqual({ uid: 1001, euid: 0 });
    expect(probe.parsePid1Uids("Uid:\t0\t1001\t1001\t1001\n")).toEqual({ uid: 0, euid: 1001 });
    expect(probe.parsePid1Uids("Uid:\t1001\t1001\t1001\t1001\n")).toEqual({ uid: 1001, euid: 1001 });
  });
  it("anything unparseable (including a missing effective field) is undefined", () => {
    for (const t of ["", "Name:\tnode\n", "Uid:\n", "Uid:\t5\n", "Uid:\tabc\t1\t1\t1\n", "Uid:\t1\tabc\t1\t1\n", "Uid:\t-1\t1\t1\t1\n", "XUid:\t5\t5\t5\t5\n", undefined, null]) {
      expect(probe.parsePid1Uids(t as unknown as string), String(t)).toBeUndefined();
    }
    expect((probe as Record<string, unknown>).parsePid1Uid).toBeUndefined();
  });
});

describe("parsePid1Environ: only five names are looked at, and only booleans come out", () => {
  const SECRET = "sentinel-secret-9f8e7d6c5b4a";
  const env = (...e: string[]) => Buffer.from(`${e.join("\0")}\0`, "latin1");
  const HOME = "/home/soleur";

  it("HOME equality and 'any of the four other bases is an absolute path'", () => {
    expect(probe.parsePid1Environ(env("PATH=/usr/bin", `HOME=${HOME}`, `API_KEY=${SECRET}`), HOME)).toEqual({ homeMatches: true, divergent: false });
    for (const n of ["CLAUDE_CONFIG_DIR", "XDG_RUNTIME_DIR", "CLAUDE_CODE_TMPDIR", "TMPDIR"]) {
      expect(probe.parsePid1Environ(env(`HOME=${HOME}`, `${n}=/some/abs`), HOME), n).toEqual({ homeMatches: true, divergent: true });
      expect(probe.parsePid1Environ(env(`HOME=${HOME}`, `${n}=relative`), HOME), `${n} relative`).toEqual({ homeMatches: true, divergent: false });
      expect(probe.parsePid1Environ(env(`HOME=${HOME}`, `${n}=`), HOME), `${n} empty`).toEqual({ homeMatches: true, divergent: false });
    }
  });

  it("HOME differing, absent, relative, or only a look-alike name is not a match", () => {
    expect(probe.parsePid1Environ(env("HOME=/root"), HOME)?.homeMatches).toBe(false);
    expect(probe.parsePid1Environ(env("HOME=/home/soleur/"), HOME)?.homeMatches).toBe(false);
    expect(probe.parsePid1Environ(env("PATH=/x"), HOME)?.homeMatches).toBe(false);
    expect(probe.parsePid1Environ(env("XHOME=/home/soleur", "HOMEX=/home/soleur"), HOME)?.homeMatches).toBe(false);
    expect(probe.parsePid1Environ(env("HOME=relative"), "relative")?.homeMatches).toBe(false);
    expect(probe.parsePid1Environ(env("XTMPDIR=/a", "TMPDIR_X=/a"), HOME)?.divergent).toBe(false);
  });

  it("an entry that merely STARTS with the secret-carrying names is not a hit, and a secret value never appears in the result", () => {
    const r = probe.parsePid1Environ(env(`HOME=${HOME}`, `DOPPLER_TOKEN=${SECRET}`, `TMPDIR=/t`), HOME);
    expect(JSON.stringify(r)).not.toContain(SECRET);
    expect(Object.keys(r as object).sort()).toEqual(["divergent", "homeMatches"]);
  });

  it("a read that hit the cap is unreadable (null), without parsing a partial entry", () => {
    expect(probe.PID1_ENV_CAP).toBe(256 * 1024);
    const big = Buffer.alloc(probe.PID1_ENV_CAP + 1, 0x41);
    expect(probe.parsePid1Environ(big, HOME)).toBeNull();
    const atCap = Buffer.concat([Buffer.from(`HOME=${HOME}\0`), Buffer.alloc(probe.PID1_ENV_CAP - HOME.length - 6, 0)]);
    expect(atCap.length).toBe(probe.PID1_ENV_CAP);
    expect(probe.parsePid1Environ(atCap, HOME)).toEqual({ homeMatches: true, divergent: false });
  });

  it("not a buffer, or an empty one, is unreadable", () => {
    for (const b of [undefined, null, "HOME=/home/soleur", Buffer.alloc(0)]) expect(probe.parsePid1Environ(b as unknown as Buffer, HOME), String(b)).toBeNull();
  });
});

describe("readPid1: injected readers, bounded, scrubbed, and silent", () => {
  const SECRET = "sentinel-secret-1a2b3c4d5e6f";
  const HOME = "/home/soleur";

  it("returns {uid, env} from the injected readers and asks for at most cap+1 bytes of environ", () => {
    const asked: number[] = [];
    const r = probe.readPid1(HOME, {
      readStatus: () => "Uid:\t1001\t1001\t1001\t1001\n",
      readEnviron: (cap: number) => {
        asked.push(cap);
        return Buffer.from(`HOME=${HOME}\0TMPDIR=/x\0`);
      },
    });
    expect(r).toEqual({ uid: 1001, euid: 1001, env: { homeMatches: true, divergent: true } });
    expect(asked).toEqual([probe.PID1_ENV_CAP + 1]);
  });

  it("an unreadable status or environ (a throwing reader) degrades to undefined / null, never throws", () => {
    const boom = () => {
      throw Object.assign(new Error("EACCES"), { code: "EACCES" });
    };
    expect(probe.readPid1(HOME, { readStatus: boom, readEnviron: boom })).toEqual({ uid: undefined, euid: undefined, env: null });
  });

  it("zero-fills the environ buffer it read before returning", () => {
    const buf = Buffer.from(`HOME=${HOME}\0SECRET=${SECRET}\0`);
    probe.readPid1(HOME, { readStatus: () => "Uid:\t1\t1\t1\t1\n", readEnviron: () => buf });
    expect(buf.every((b) => b === 0)).toBe(true);
  });

  it("SENTINEL: a secret seeded in a fake PID-1 environ never reaches stdout, stderr, the console or the result JSON", () => {
    const writes: string[] = [];
    const spies = [
      vi.spyOn(process.stdout, "write").mockImplementation((c: unknown) => (writes.push(String(c)), true)),
      vi.spyOn(process.stderr, "write").mockImplementation((c: unknown) => (writes.push(String(c)), true)),
      vi.spyOn(console, "log").mockImplementation((...a: unknown[]) => void writes.push(a.map(String).join(" "))),
      vi.spyOn(console, "error").mockImplementation((...a: unknown[]) => void writes.push(a.map(String).join(" "))),
      vi.spyOn(console, "warn").mockImplementation((...a: unknown[]) => void writes.push(a.map(String).join(" "))),
    ];
    let json = "";
    try {
      const pid1 = probe.readPid1(HOME, {
        readStatus: () => "Uid:\t1001\t1001\t1001\t1001\n",
        readEnviron: () => Buffer.from(`PATH=/usr/bin\0HOME=/root\0ANTHROPIC_API_KEY=${SECRET}\0TMPDIR=/t\0DOPPLER_TOKEN=${SECRET}\0`),
      });
      const fs = fakeFs({});
      const r = probe.ensureMaskedDirs({ dirs: probe.precreateDirs(1001, HOME), homeDirs: [`${HOME}/.claude/projects`], uid: 1001, pid1, lstat: fs.lstat, mkdir: fs.mkdir });
      json = JSON.stringify({ pid1, r, fields: probe.maskFields(r) });
    } finally {
      for (const s of spies) s.mockRestore();
    }
    expect(json).not.toContain(SECRET);
    expect(json).not.toContain("/root");
    expect(writes.join("\n")).not.toContain(SECRET);
    expect(writes.join("\n")).not.toContain("/root");
  });
});

// ---- The REAL readers, against files (the production seams the injected-fake tests above cannot see) -----------------------------------
describe("readProcCapped / readPid1 against real files", () => {
  const HOME = "/home/soleur";
  const CAP = probe.PID1_ENV_CAP;
  const tmps: string[] = [];
  const scratch = () => {
    const d = realpathSync(mkdtempSync(join(tmpdir(), "pid1-fixture-")));
    tmps.push(d);
    return d;
  };
  afterEach(() => {
    for (const d of tmps.splice(0)) rmSync(d, { recursive: true, force: true });
  });
  const status = (d: string, line = "Uid:\t1001\t1001\t1001\t1001") => {
    const f = join(d, "status");
    writeFileSync(f, `Name:\tnode\n${line}\nGid:\t1001\t1001\t1001\t1001\n`);
    return f;
  };
  const environFile = (d: string, entries: string[], pad = 0) => {
    const f = join(d, "environ");
    writeFileSync(f, Buffer.concat([Buffer.from(`${entries.join("\0")}\0`), Buffer.alloc(pad, 0)]));
    return f;
  };

  it("NUL-separated entries bigger than 64 KiB, HOME and TMPDIR at the END: both are seen (the returned view is exactly the bytes read)", () => {
    const d = scratch();
    const filler = Array.from({ length: 3000 }, (_, i) => `PAD${i}=${"x".repeat(60)}`);
    const f = environFile(d, [...filler, `HOME=${HOME}`, "TMPDIR=/t"]);
    expect(statSync(f).size).toBeGreaterThan(64 * 1024);
    expect(probe.readPid1(HOME, { statusPath: status(d), environPath: f })).toEqual({ uid: 1001, euid: 1001, env: { homeMatches: true, divergent: true } });
    expect(probe.readProcCapped(f, CAP + 1).length).toBe(statSync(f).size);
  });

  it("reads the whole file across SEVERAL reads (a FIFO delivers it in chunks): an early stop would miss TMPDIR", () => {
    const d = scratch();
    const fifo = join(d, "environ.fifo");
    execFileSync("mkfifo", [fifo]);
    const writer = spawn("sh", ["-c", `{ printf 'HOME=${HOME}\\0'; sleep 0.4; printf 'TMPDIR=/t\\0'; } > "$1"`, "sh", fifo], { stdio: "ignore" });
    try {
      expect(probe.readPid1(HOME, { statusPath: status(d), environPath: fifo }).env).toEqual({ homeMatches: true, divergent: true });
    } finally {
      writer.kill();
    }
  });

  it("the cap: a file of exactly PID1_ENV_CAP bytes is parsed, one byte more (or far more) is unreadable", () => {
    const d = scratch();
    const entry = `HOME=${HOME}`;
    const atCap = environFile(d, [entry], CAP - entry.length - 1);
    expect(statSync(atCap).size).toBe(CAP);
    expect(probe.readPid1(HOME, { statusPath: status(d), environPath: atCap }).env).toEqual({ homeMatches: true, divergent: false });
    const over = join(d, "over");
    writeFileSync(over, Buffer.concat([Buffer.from(`${entry}\0`), Buffer.alloc(CAP - entry.length, 0)]));
    expect(statSync(over).size).toBe(CAP + 1);
    expect(probe.readPid1(HOME, { statusPath: status(d), environPath: over }).env).toBeNull();
    const far = join(d, "far");
    writeFileSync(far, Buffer.concat([Buffer.from(`${entry}\0`), Buffer.alloc(3 * CAP, 0)]));
    expect(probe.readPid1(HOME, { statusPath: status(d), environPath: far }).env).toBeNull();
  });

  it("readProcCapped returns exactly the bytes read, never the whole allocation, and never more than the cap", () => {
    const d = scratch();
    const f = join(d, "f");
    writeFileSync(f, "0123456789");
    expect(probe.readProcCapped(f, 4).toString()).toBe("0123");
    expect(probe.readProcCapped(f, 64).toString()).toBe("0123456789");
    writeFileSync(f, "");
    expect(probe.readProcCapped(f, 64).length).toBe(0);
  });

  it("the cap is reached across chunks of 60, 3 and 1 bytes: all 64 are returned (an early stop at cap-1 would drop the last byte)", () => {
    const d = scratch();
    const f = join(d, "f");
    writeFileSync(f, "x");
    const sizes = [60, 3, 1];
    let calls = 0;
    const chunked = ((_fd: number, buf: Buffer, off: number, len: number) => {
      const n = Math.min(sizes[calls++] ?? 0, len);
      buf.fill(0x41 + calls, off, off + n);
      return n;
    }) as unknown as typeof import("node:fs").readSync;
    const out = probe.readProcCapped(f, 64, chunked);
    expect(out.length).toBe(64);
    expect(out[63]).toBe(0x41 + 3);
    expect(calls).toBe(3);
  });

  it("a FIFO that delivers exactly CAP bytes in several chunks is returned whole (no off-by-one at the cap)", () => {
    const d = scratch();
    const fifo = join(d, "cap.fifo");
    execFileSync("mkfifo", [fifo]);
    // 40 + 23 + 1 bytes with a pause between writes: three separate reads, the last one a single byte.
    const writer = spawn("sh", ["-c", `{ printf '%040d' 0; sleep 0.3; printf '%023d' 0; sleep 0.3; printf 'Z'; } > "$1"`, "sh", fifo], { stdio: "ignore" });
    try {
      const out = probe.readProcCapped(fifo, 64);
      expect(out.length).toBe(64);
      expect(out.toString().endsWith("Z")).toBe(true);
    } finally {
      writer.kill();
    }
  });

  it("the descriptor is closed exactly once on a normal return and on a throw (injected close sees the fd the open returned)", () => {
    const d = scratch();
    const f = join(d, "f");
    writeFileSync(f, "0123456789");
    const closed: number[] = [];
    const close = ((fd: number) => { closed.push(fd); }) as unknown as typeof import("node:fs").closeSync;
    probe.readProcCapped(f, 4, undefined, close);
    expect(closed.length).toBe(1);
    expect(closed[0]).toBeGreaterThan(2);
    const boom = (() => { throw new Error("EIO"); }) as unknown as typeof import("node:fs").readSync;
    expect(() => probe.readProcCapped(f, 4, boom, close)).toThrow("EIO");
    expect(closed.length).toBe(2);
    // the injected close never closed the real fds: close them so the suite does not leak
    for (const fd of closed) closeSync(fd);
  });

  it("an allocation that throws never opens the file (no descriptor leak, and not even an ENOENT from the open)", () => {
    const d = scratch();
    const fdCount = () => readdirSync("/proc/self/fd").length;
    const f = join(d, "f");
    writeFileSync(f, "x");
    const before = fdCount();
    expect(() => probe.readProcCapped(f, 2 ** 53)).toThrow(/range|size|allocation|memory/i);
    expect(() => probe.readProcCapped(join(d, "does-not-exist"), 2 ** 53)).toThrow(/range|size|allocation|memory/i);
    expect(fdCount()).toBe(before);
  });

  it("a read that throws part-way leaves the allocated buffer zero-filled (no half-read environment survives) and the error propagates", () => {
    const d = scratch();
    const f = join(d, "f");
    writeFileSync(f, "SECRET=very-secret-value");
    let seen: Buffer | undefined;
    let calls = 0;
    const flaky = ((_fd: number, buf: Buffer, off: number, len: number) => {
      seen = buf;
      if (++calls === 1) return buf.write("SECRET=very-sec", off, len);
      throw Object.assign(new Error("EIO"), { code: "EIO" });
    }) as unknown as typeof import("node:fs").readSync;
    expect(() => probe.readProcCapped(f, 64, flaky)).toThrow("EIO");
    expect(calls).toBe(2);
    expect(seen).toBeDefined();
    expect(seen!.every((b) => b === 0)).toBe(true);
  });

  it("the status file: real AND effective uid are both read; a missing or garbled file degrades to undefined / null", () => {
    const d = scratch();
    const env = environFile(d, [`HOME=${HOME}`]);
    expect(probe.readPid1(HOME, { statusPath: status(d, "Uid:\t1001\t0\t0\t0"), environPath: env })).toMatchObject({ uid: 1001, euid: 0 });
    expect(probe.readPid1(HOME, { statusPath: join(d, "nope"), environPath: join(d, "nope2") })).toEqual({ uid: undefined, euid: undefined, env: null });
    expect(probe.readPid1(HOME, { statusPath: status(d, "Uid:\tgarbage"), environPath: env })).toMatchObject({ uid: undefined, euid: undefined });
  });
});

// ---- runtimeMasks: runSmoke's runtime step, end to end against FIXTURE /proc files (the real readers, an in-memory filesystem) ----------------
describe("runtimeMasks: the step runSmoke calls, driven through readPid1's real readers", () => {
  const uid = 1001;
  const home = "/home/soleur";
  const tmps: string[] = [];
  afterEach(() => {
    for (const d of tmps.splice(0)) rmSync(d, { recursive: true, force: true });
  });
  const fixture = (statusUid: string, environ: string[] | null) => {
    const d = realpathSync(mkdtempSync(join(tmpdir(), "rtmasks-fixture-")));
    tmps.push(d);
    writeFileSync(join(d, "status"), `Name:\tnode\nUid:\t${statusUid}\nGid:\t1001\t1001\t1001\t1001\n`);
    if (environ) writeFileSync(join(d, "environ"), `${environ.join("\0")}\0`);
    return { statusPath: join(d, "status"), environPath: join(d, "environ") };
  };
  const runtime = probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: "base" }, uid, home });
  const drive = (io: Record<string, unknown>, fs: ReturnType<typeof fakeFs>, over: { uid?: number; euid?: number; home?: string } = {}) =>
    probe.runtimeMasks({ plan: runtime, home: over.home ?? home, uid: over.uid ?? uid, euid: over.euid ?? over.uid ?? uid, io: { ...io, lstat: fs.lstat, mkdir: fs.mkdir } });

  it("a PID 1 with the probe's uid and HOME: all four closed-set dirs are created, nothing is refused, and the result-JSON fields say so", () => {
    const fs = fakeFs({});
    const r = drive(fixture("1001\t1001\t1001\t1001", [`HOME=${home}`, "PATH=/usr/bin"]), fs);
    expect(r).toEqual({ created: 4, failed: [], note: null });
    expect(fs.mkdirCalls.map((c) => c[0])).toEqual(probe.precreateDirs(uid, home));
    expect(probe.maskFields(r!)).toEqual({ masks_missing: 0, masks_created: 4, masks_note: null });
  });

  it("a PID 1 whose HOME is different: ONLY the transcript dir is refused (home_mismatch), the other three are created", () => {
    const fs = fakeFs({});
    const r = drive(fixture("1001\t1001\t1001\t1001", ["HOME=/root"]), fs);
    expect(r).toEqual({ created: 3, failed: [`${home}/.claude/projects`], note: "home_mismatch" });
    expect(fs.mkdirCalls.map((c) => c[0])).not.toContain(`${home}/.claude/projects`);
    expect(probe.maskFields(r!)).toEqual({ masks_missing: 1, masks_created: 3, masks_note: "home_mismatch" });
  });

  it("an unreadable /proc/1/environ: pid1_env_unreadable, the transcript dir refused, the other three created", () => {
    const fs = fakeFs({});
    const r = drive(fixture("1001\t1001\t1001\t1001", null), fs);
    expect(r).toEqual({ created: 3, failed: [`${home}/.claude/projects`], note: "pid1_env_unreadable" });
  });

  it("an unreadable /proc/1/status: pid1_unreadable and NOTHING is created", () => {
    const fs = fakeFs({});
    const io = fixture("1001\t1001\t1001\t1001", [`HOME=${home}`]);
    const r = drive({ ...io, statusPath: `${io.statusPath}.missing` }, fs);
    expect(r!.note).toBe("pid1_unreadable");
    expect(fs.mkdirCalls).toEqual([]);
  });

  it("PID 1 under another real or effective uid than the probe's real or effective uid: uid_mismatch, nothing is created (all four combinations)", () => {
    const cases: Array<[string, { uid?: number; euid?: number }]> = [
      ["0\t0\t0\t0", {}],                          // PID 1 is root, the probe is 1001
      ["1001\t0\t0\t0", {}],                       // PID 1's effective uid differs
      ["1001\t1001\t1001\t1001", { euid: 0 }],     // the probe's effective uid differs (a setuid probe)
      ["1001\t1001\t1001\t1001", { uid: 0, euid: 1001 }], // the probe's real uid differs
    ];
    for (const [status, over] of cases) {
      const fs = fakeFs({});
      const r = drive(fixture(status, [`HOME=${home}`]), fs, over);
      expect(r!.note, status + JSON.stringify(over)).toBe("uid_mismatch");
      expect(fs.mkdirCalls, status + JSON.stringify(over)).toEqual([]);
    }
  });

  it("a deploy-mode plan is a no-op returning null: PID 1 is not even read, nothing is created", () => {
    const deploy = probe.planSmoke({ env: {}, uid, home });
    const fs = fakeFs({});
    const touched: string[] = [];
    const r = probe.runtimeMasks({
      plan: deploy, home, uid, euid: uid,
      io: { lstat: fs.lstat, mkdir: fs.mkdir, readStatus: () => { touched.push("status"); return ""; }, readEnviron: () => { touched.push("environ"); return Buffer.alloc(0); } },
    });
    expect(r).toBeNull();
    expect(touched).toEqual([]);
    expect(fs.mkdirCalls).toEqual([]);
  });

  it("euid defaults to uid, and the closed set is created only through the injected mkdir with production's options", () => {
    const fs = fakeFs({});
    const io = fixture("1001\t1001\t1001\t1001", [`HOME=${home}`]);
    const r = probe.runtimeMasks({ plan: runtime, home, uid, io: { ...io, lstat: fs.lstat, mkdir: fs.mkdir } });
    expect(r!.created).toBe(4);
    expect(fs.mkdirCalls.every((c) => JSON.stringify(c[1]) === JSON.stringify({ recursive: true, mode: 0o700 }))).toBe(true);
  });
});

// ---- applyRuntimeMasks: what runSmoke hands to ensureMaskedDirs (homeDirs and dirs reach it) --------------------------------------------
describe("applyRuntimeMasks: the closed set and the HOME-derived dir reach ensureMaskedDirs", () => {
  const uid = 1001;
  const home = "/home/soleur";
  const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: "base" }, uid, home });
  const apply = (fs: ReturnType<typeof fakeFs>, pid1: unknown) =>
    probe.applyRuntimeMasks({ plan, home, uid, pid1, lstat: fs.lstat, mkdir: fs.mkdir });
  const pid1 = (homeMatches: boolean) => ({ uid, euid: uid, env: { homeMatches, divergent: false } });

  it("a matching PID-1 HOME: all four are created, /tmp/.cs included (the plan's `precreate` set, not its `masked` one)", () => {
    const fs = fakeFs({});
    expect(apply(fs, pid1(true))).toEqual({ created: 4, failed: [], note: null });
    expect(fs.mkdirCalls.map((c) => c[0])).toEqual(["/tmp/cc-socks", "/tmp/cc-socks-1001", `${home}/.claude/projects`, "/tmp/.cs"]);
    expect(probe.transcriptDir(home)).toBe(`${home}/.claude/projects`);
  });

  it("a foreign PID-1 HOME: ONLY the transcript dir is refused, the two /tmp/cc-socks* dirs and /tmp/.cs are still created", () => {
    const fs = fakeFs({});
    expect(apply(fs, pid1(false))).toEqual({ created: 3, failed: [`${home}/.claude/projects`], note: "home_mismatch" });
    expect(fs.mkdirCalls.map((c) => c[0])).toEqual(["/tmp/cc-socks", "/tmp/cc-socks-1001", "/tmp/.cs"]);
  });

  it("PID 1's environ unreadable: same refusal, and a uid mismatch creates nothing at all", () => {
    const fs = fakeFs({});
    expect(apply(fs, { uid, euid: uid, env: null })).toMatchObject({ created: 3, note: "pid1_env_unreadable" });
    expect(fs.mkdirCalls.map((c) => c[0])).not.toContain(`${home}/.claude/projects`);
    const fs2 = fakeFs({});
    expect(apply(fs2, { uid: 0, euid: 0, env: { homeMatches: true, divergent: false } }).note).toBe("uid_mismatch");
    expect(fs2.mkdirCalls).toEqual([]);
  });

  it("the deploy plan has no precreate set, so nothing is created through this path", () => {
    const deploy = probe.planSmoke({ env: {}, uid, home });
    const fs = fakeFs({});
    expect(probe.applyRuntimeMasks({ plan: deploy, home, uid, pid1: pid1(true), lstat: fs.lstat, mkdir: fs.mkdir })).toEqual({ created: 0, failed: [], note: null });
    expect(fs.mkdirCalls).toEqual([]);
  });
});

// ---- Parity: the masks_note enum and the masks_created bound are copied by hand into three more places -----------------------------------
describe("masks_note / masks_created: one closed set, derived from the probe, equal in every copy", () => {
  const codeOf = (text: string) => text.split("\n").filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*") && !l.trim().startsWith("/**")).join("\n");
  const ensureFn = codeOf(probeSrc.slice(probeSrc.indexOf("export function ensureMaskedDirs("), probeSrc.indexOf("export function applyRuntimeMasks(")));
  const probeNotes = [...new Set([...ensureFn.matchAll(/\bnote = "([a-z0-9_]+)"/g)].map((m) => m[1]))].sort();
  const synth = readFileSync(SYNTHETIC_PATH, "utf8");

  it("the probe's set is the five documented notes (floor: an empty derivation must not pass)", () => {
    expect(probeNotes).toEqual(["env_divergence", "home_mismatch", "pid1_env_unreadable", "pid1_unreadable", "uid_mismatch"]);
  });

  it("the probe's exported MASKS_NOTES constant equals the notes ensureMaskedDirs can assign (a new note must be added to both)", () => {
    expect([...probe.MASKS_NOTES].sort()).toEqual(probeNotes);
    expect(Object.isFrozen(probe.MASKS_NOTES)).toBe(true);
  });

  it("web-bash-synthetic.sh's `case` alternatives are exactly the probe's notes", () => {
    const m = /case "\$_n" in ([a-z0-9_|]+)\) MNOTE="\$_n" ;;/.exec(synth);
    expect(m, "the masks_note case line was not found").not.toBeNull();
    expect(m![1].split("|").sort()).toEqual(probeNotes);
  });

  it("the runbook's masks_note decode table has exactly one row per note (the `-` row aside)", () => {
    const lines = readFileSync(RUNBOOK_PATH, "utf8").split("\n");
    const head = lines.findIndex((l) => /^\| `masks_note` \|/.test(l));
    expect(head, "the masks_note table header was not found").toBeGreaterThanOrEqual(0);
    const keys: string[] = [];
    for (const l of lines.slice(head + 2)) {
      if (!l.startsWith("|")) break;
      const k = /^\| `([^`]+)` \|/.exec(l)?.[1];
      if (k && k !== "-") keys.push(k);
    }
    expect(keys.sort()).toEqual(probeNotes);
  });

  it("the synthetic's masks_created / masks_missing digit bound equals the size of the probe's closed set", () => {
    const bound = (name: string) => {
      const m = new RegExp(`case "\\$${name}" in \\[0-(\\d)\\]\\) `).exec(synth);
      expect(m, `the ${name} digit case was not found`).not.toBeNull();
      return Number(m![1]);
    };
    const n = probe.precreateDirs(1, "/h").length;
    expect(bound("_c")).toBe(n);
    expect(bound("_m")).toBe(n);
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

  it("deploy mode (SDK_BASH_PROBE_RUNTIME unset): the pinned unixdeny artifact, every masked dir applied AND created, a stray selector env ignored", () => {
    const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_SELECTOR: "base" }, uid, home });
    expect(plan).toEqual({
      runtime: false,
      selectorName: "unixdeny",
      selectedPath: probe.SMOKE_SELECTOR_PATHS.unixdeny,
      masked: all,
      mkdir: all,
      precreate: [],
    });
  });

  it("runtime mode honours the selector NAME and expects exactly that artifact", () => {
    for (const name of ["base", "unixdeny"] as const) {
      const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: name }, uid, home });
      expect(plan.runtime).toBe(true);
      expect(plan.selectorName).toBe(name);
      expect(plan.selectedPath).toBe(probe.SMOKE_SELECTOR_PATHS[name]);
    }
  });

  it("runtime mode applies every masked dir like production and hands the creation to ensureMaskedDirs: plan.mkdir is always empty, precreate is the closed 4-dir set", () => {
    const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: "base" }, uid, home });
    expect(plan).toMatchObject({ masked: all, mkdir: [], precreate: probe.precreateDirs(uid, home) });
    expect(plan.precreate).toHaveLength(4);
    expect((plan as Record<string, unknown>).masksMissing).toBeUndefined();
  });

  it("runtime mode with an unknown or missing selector has no artifact (the caller reports selector_invalid)", () => {
    for (const sel of [undefined, "", "BASE", "../x", "__proto__", "/app/infra/other.bpf"]) {
      const plan = probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: "1", SDK_BASH_PROBE_SELECTOR: sel }, uid, home });
      expect(plan.selectedPath, String(sel)).toBeNull();
      expect(plan.mkdir, String(sel)).toEqual([]);
      expect(plan.precreate, String(sel)).toEqual([]);
    }
  });

  it("only the exact string \"1\" turns runtime mode on", () => {
    for (const v of ["", "0", "true", "yes", "11"]) {
      expect(probe.planSmoke({ env: { SDK_BASH_PROBE_RUNTIME: v }, uid, home }).runtime, v).toBe(false);
    }
  });
});

describe("runSmoke is wired to planSmoke, not to its own copy of the decisions", () => {
  const runSmoke = probeSrc.slice(probeSrc.indexOf("async function runSmoke()"));
  const code = runSmoke.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");

  it("runtimeMasks (-> applyRuntimeMasks -> ensureMaskedDirs) is the ONLY runtime creation site: one top-level call before the sandbox is built, fed the real uid, euid and HOME; the deploy loop is the only direct mkdirSync", () => {
    expect(code.match(/runtimeMasks\(/g)?.length).toBe(1);
    expect(code).not.toMatch(/applyRuntimeMasks\(|\bensureMaskedDirs\(|\breadPid1\(/);
    // The bindings the call takes are the process's own, not a stand-in: a runSmoke that read geteuid for `uid`, defaulted HOME, or hard-coded a
    // uid would create dirs for the wrong owner (the behaviour of runtimeMasks itself is driven above, with these as inputs).
    expect(code).toContain("  const home = process.env.HOME;\n");
    expect(code).toContain("  const uid = process.getuid();\n  const euid = process.geteuid();\n");
    // A STATEMENT of runSmoke's own body (two-space indent, no guard, no callback, no io override): not behind an env test, a timer or a ternary.
    const call = /^ {2}const masksResult = runtimeMasks\(\{ plan, home, uid, euid \}\);$/m.exec(code);
    expect(call, "the runtimeMasks call is not an unconditional top-level statement with exactly { plan, home, uid, euid }").not.toBeNull();
    // ... and it runs BEFORE the sandbox config is built and the SDK query starts (a deferred creation would race the namespace build).
    expect(call!.index).toBeLessThan(code.indexOf("const sandbox = smokeSandboxConfig("));
    expect(call!.index).toBeLessThan(code.indexOf("const q = query("));
    expect(code.match(/mkdirSync\(/g)?.length).toBe(1);
    expect(code).toContain("for (const d of plan.mkdir) mkdirSync(d, { recursive: true, mode: 0o700 });");
    expect(code).toContain("const { runtime, selectorName, selectedPath, masked } = plan;");
    expect(code).toContain("smokeSandboxConfig({ workspace: ws, uid, home, masked })");
    // The result fields ride only in runtime mode, from THIS result.
    expect(code).toContain("emit(runtime ? { ...v, selector: selectorName, ...maskFields(masksResult) } : v);");
    // runtimeMasks itself: the deploy guard, the real readers and the real fs defaults, the euid pass-through.
    const fn = probeSrc.slice(probeSrc.indexOf("export function runtimeMasks("), probeSrc.indexOf("/** The runtime result-JSON fields"));
    expect(fn).toContain("if (!plan.runtime) return null;");
    expect(fn).toContain("pid1: readPid1(home, io), lstat: io.lstat ?? lstatSync, mkdir: io.mkdir ?? mkdirSync");
    expect(fn.match(/applyRuntimeMasks\(/g)?.length).toBe(1);
  });

  it("ensureMaskedDirs itself: one mkdir call with production's exact options, lstat only, no chmod/chown/replace anywhere in the file", () => {
    const fn = probeSrc.slice(probeSrc.indexOf("export function ensureMaskedDirs("), probeSrc.indexOf("export function applyRuntimeMasks("));
    const fnCode = fn.split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
    expect(fnCode.match(/\bmkdir\(/g)?.length).toBe(1);
    expect(fnCode).toContain("mkdir(dir, { recursive: true, mode: 0o700 })");
    expect(fnCode).toMatch(/\blstat\(/);
    const apply = probeSrc.slice(probeSrc.indexOf("export function applyRuntimeMasks("), probeSrc.indexOf("export function maskFields("));
    expect(apply).toContain("ensureMaskedDirs({ dirs: plan.precreate, homeDirs: [transcriptDir(home)], uid, euid, pid1, lstat, mkdir })");
    expect(fnCode).not.toMatch(/\bstat\(|statSync|\bchmod|\bchown|\brename|\bunlink|\brm\b|rmSync|symlink/);
    const all = probeSrc.split("\n").filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*") && !l.trim().startsWith("/**")).join("\n");
    expect(all).not.toMatch(/\b(chmod|fchmod|chown|lchown|fchown)\w*\(/);
  });

  it("PID 1 is read in exactly one place, narrowly: status and environ paths each appear once in code, and the environ read is capped", () => {
    const all = probeSrc.split("\n").filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*") && !l.trim().startsWith("/**")).join("\n");
    expect(all.match(/\/proc\/1\/status/g)?.length).toBe(1);
    expect(all.match(/\/proc\/1\/environ/g)?.length).toBe(1);
    expect(all).toContain("PID1_ENV_CAP");
    // no value from the environ is turned into a string except through the five-name parser
    expect(all).not.toMatch(/environ[^\n]*(console|process\.std)/);
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
