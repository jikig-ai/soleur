// Acceptance for #8623, against the REAL pinned likec4 binary (no module mocks
// of child_process or fs — this proves real execution, or its absence).
//
// A tenant diagrams tree holding a sentinel-writing `likec4.config.mjs` must
// never execute it on the server render. Before the fix (main ca83c8edf0,
// renderC4Model(workspacePath) spawning likec4 with cwd = the workspace
// diagrams dir) the tracked-config, nested-config and symlinked-directory rows
// were all RED; the render now takes no workspace path, so those "untracked"
// rows are replaced by the structural test (c4-render-boundary.test.ts).
//
// Binary: $LIKEC4_BIN, else `likec4` on PATH. Absent → skip locally with the
// install command, but FAIL when LIKEC4_REQUIRED is set (CI's test-webplat sets
// it), so a missing binary can never read as a pass.
import { describe, it, expect, vi, beforeAll, afterEach } from "vitest";
import { spawnSync } from "node:child_process";
import {
  closeSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { readFileSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import {
  createFakeGitHub,
  FakeGitHubApiError,
  type FakeGitHub,
  type FakeTree,
} from "./helpers/fake-github-trees";

const INSTALL_HINT = "npm install -g likec4@1.50.0";

function resolveLikec4(): string | null {
  const fromEnv = process.env.LIKEC4_BIN;
  if (fromEnv) return existsSync(fromEnv) ? fromEnv : null;
  for (const dir of (process.env.PATH ?? "").split(delimiter)) {
    if (dir && existsSync(join(dir, "likec4"))) return join(dir, "likec4");
  }
  return null;
}

const BIN = resolveLikec4();
if (!BIN && process.env.LIKEC4_REQUIRED) {
  throw new Error(
    `LIKEC4_REQUIRED is set but no likec4 binary resolves (LIKEC4_BIN or PATH). Install it: ${INSTALL_HINT}`,
  );
}
if (!BIN) {
  console.warn(`[c4-render-tenant-config] likec4 not found — skipping. Install: ${INSTALL_HINT}`);
}

// #8696: the render runs inside bwrap. "Available" means bwrap can actually
// create the sandbox here (a runner can have the binary but block user
// namespaces), not that it is on PATH. CI's test-webplat installs it and sets
// C4_BWRAP_REQUIRED, so an unusable bwrap there FAILS instead of skipping.
const BWRAP_HINT =
  "apt-get install bubblewrap && sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu)";
const BWRAP_OK =
  spawnSync(
    "/usr/bin/bwrap",
    [
      "--unshare-user", "--unshare-pid", "--unshare-net", "--ro-bind", "/usr", "/usr",
      "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib64", "/lib64", "--", "/usr/bin/true",
    ],
    { stdio: "ignore", timeout: 15_000 },
  ).status === 0;
if (!BWRAP_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(`C4_BWRAP_REQUIRED is set but /usr/bin/bwrap cannot create a sandbox here. ${BWRAP_HINT}`);
}
if (!BWRAP_OK) {
  console.warn(`[c4-render-tenant-config] bwrap unusable — rendering unsandboxed; skipping the isolation rows. ${BWRAP_HINT}`);
}

const h = vi.hoisted(() => ({ fake: null as FakeGitHub | null }));
vi.mock("@/server/github-api", () => ({
  githubApiGet: (...a: [number, string, { signal?: AbortSignal }?]) => h.fake!.get(...a),
  githubApiPost: (...a: [number, string, { content: string; sha?: string }, string?]) =>
    h.fake!.post(...a),
  GitHubApiError: FakeGitHubApiError,
}));

const D = "knowledge-base/engineering/architecture/diagrams";
const MODEL_C4 = `specification {
  element actor
  element system
}
model {
  u = actor 'User'
  s = system 'System'
  u -> s 'uses'
}
views {
  view index {
    include *
  }
}
`;

/** Writes an absolute sentinel path baked into the file (the env allow-list
 *  strips custom variables, so the config cannot read one from env). */
function configThatWrites(sentinel: string): string {
  return (
    `import { writeFileSync } from "node:fs";\n` +
    `writeFileSync(${JSON.stringify(sentinel)}, "executed");\n` +
    `export default { name: "tenant" };\n`
  );
}

let dirs: string[] = [];
function tmp(prefix: string): string {
  const d = mkdtempSync(join(tmpdir(), prefix));
  dirs.push(d);
  return d;
}
function sentinelPath(): string {
  // Outside every directory the render creates or removes, so "absent" cannot
  // be satisfied by the render's own cleanup (harness row H4).
  return join(tmp("c4-sentinel-"), "SENTINEL");
}

type RenderMod = typeof import("@/server/c4-render");
type Render = RenderMod["renderC4Model"];
type StageMod = typeof import("@/server/c4-stage-sources");
let renderMod: RenderMod;
let renderC4Model: Render;
let stageMod: StageMod;
let stagingRoot: string;

beforeAll(async () => {
  if (!BIN) return;
  stagingRoot = tmp("c4-staging-root-");
  vi.stubEnv("LIKEC4_BIN", BIN);
  vi.stubEnv("C4_RENDER_STAGING_ROOT", stagingRoot);
  // Outside production only: without a usable bwrap, the acceptance rows still
  // exercise real likec4 on the direct path.
  if (!BWRAP_OK) vi.stubEnv("C4_RENDER_SANDBOX", "off");
  vi.resetModules();
  // LIKEC4_BIN is read at module load — import AFTER stubbing it.
  renderMod = await import("@/server/c4-render");
  renderC4Model = renderMod.renderC4Model;
  stageMod = await import("@/server/c4-stage-sources");
});

afterEach(() => {
  for (const d of dirs.filter((d) => d !== stagingRoot)) rmSync(d, { recursive: true, force: true });
  dirs = dirs.filter((d) => d === stagingRoot);
  h.fake = null;
});

function fixture(extra: Record<string, string> = {}): FakeTree {
  const t: FakeTree = { [`${D}/model.c4`]: { mode: "100644", content: MODEL_C4 } };
  for (const [p, c] of Object.entries(extra)) t[`${D}/${p}`] = { mode: "100644", content: c };
  return t;
}

/** The server's render, with the production stage function against the fake. */
function render(tree: FakeTree, opts: { skipConfigRefusal?: boolean; seen?: string[] } = {}) {
  h.fake = createFakeGitHub(tree);
  const commitSha = h.fake.firstCommit;
  return renderC4Model((destDir, signal) => {
    opts.seen?.push(destDir);
    const stage = opts.skipConfigRefusal
      ? stageMod.__stageSkippingConfigRefusalForTests
      : stageMod.stageCommittedC4Sources;
    return stage({
      installationId: 1,
      owner: "o",
      repo: "r",
      commitSha,
      destDir,
      signal,
      retryDelayMs: 1,
    });
  });
}

function elementIds(json: string): string[] {
  return Object.keys((JSON.parse(json) as { elements: Record<string, unknown> }).elements).sort();
}

/** Write a fixture map to disk, preserving its diagrams-relative layout. */
function writeTree(tree: FakeTree): string {
  const root = tmp("c4-inplace-");
  for (const [p, e] of Object.entries(tree)) {
    if (!p.startsWith(`${D}/`) || !("content" in e)) continue;
    const target = join(root, p.slice(D.length + 1));
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, e.content);
  }
  return root;
}

describe.skipIf(!BIN)("#8623 acceptance — a tenant likec4 config never executes on the server render", () => {
  it("H1 control: the SAME fixture run IN PLACE (server argv + env) executes the config", () => {
    const s = sentinelPath();
    const dir = writeTree(fixture({ "likec4.config.mjs": configThatWrites(s) }));
    const out = join(tmp("c4-out-"), "model.likec4.json");
    const env = Object.fromEntries(
      (["PATH", "LANG", "LC_ALL", "HOME", "TMPDIR"] as const)
        .map((k) => [k, process.env[k]] as const)
        .filter(([, v]) => v !== undefined),
    ) as NodeJS.ProcessEnv;
    const r = spawnSync(BIN!, ["export", "json", "-o", out, "."], {
      cwd: dir,
      env,
      stdio: ["ignore", "ignore", "pipe"],
      timeout: 60_000,
    });
    expect(r.status).toBe(0);
    // The fixture's config is live code — so its absence below is meaningful.
    expect(existsSync(s)).toBe(true);
  }, 90_000);

  it("a tracked likec4.config.mjs is refused and never executed", async () => {
    const s = sentinelPath();
    const res = await render(fixture({ "likec4.config.mjs": configThatWrites(s) }));
    expect(res).toMatchObject({ ok: false, reason: "unsafe_source", refusalClass: "likec4-config", path: "likec4.config.mjs" });
    expect(existsSync(s)).toBe(false);
  }, 90_000);

  it("a nested likec4.config.mjs is refused and never executed", async () => {
    const s = sentinelPath();
    const res = await render(fixture({ "sub/likec4.config.mjs": configThatWrites(s) }));
    expect(res).toMatchObject({ ok: false, reason: "unsafe_source", refusalClass: "likec4-config" });
    expect(existsSync(s)).toBe(false);
  }, 90_000);

  it("Guard row 3: with the refusal DISABLED the config is still not staged (the allowlist holds)", async () => {
    const s = sentinelPath();
    const res = await render(fixture({ "likec4.config.mjs": configThatWrites(s) }), { skipConfigRefusal: true });
    expect(res.ok).toBe(true);
    if (res.ok) expect(elementIds(res.json)).toEqual(["s", "u"]);
    expect(existsSync(s)).toBe(false);
  }, 90_000);

  it("a benign tree renders: ok, element ids exactly {u, s}, with a laid-out view (dispatch is real)", async () => {
    const res = await render(fixture());
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(elementIds(res.json)).toEqual(["s", "u"]);
      // --no-use-dot: wasm layout ran, so at least `index` exists (#8696).
      expect(Object.keys((JSON.parse(res.json) as { views: object }).views).length).toBeGreaterThanOrEqual(1);
    }
  }, 90_000);

  it("a config sitting in the staging ROOT is not executed (no walk-up), and the root is honoured", async () => {
    const s = sentinelPath();
    writeFileSync(join(stagingRoot, "likec4.config.mjs"), configThatWrites(s));
    const seen: string[] = [];
    try {
      const res = await render(fixture(), { seen });
      expect(res.ok).toBe(true);
      expect(existsSync(s)).toBe(false);
      expect(seen).toHaveLength(1);
      expect(seen[0].startsWith(`${stagingRoot}/`)).toBe(true);
    } finally {
      rmSync(join(stagingRoot, "likec4.config.mjs"), { force: true });
    }
  }, 90_000);
});

describe.skipIf(!BIN)("#8623 acceptance — inputs outside the working tree", () => {
  it("the config-name list matches the installed likec4 dist (a bump that adds a name reds here)", () => {
    // Walk up from the resolved binary to the likec4 package root.
    let dir = dirname(realpathSync(BIN!));
    for (let i = 0; i < 6 && !existsSync(join(dir, "dist", "_chunks", "src.mjs")); i++) dir = dirname(dir);
    const src = readFileSync(join(dir, "dist", "_chunks", "src.mjs"), "utf8");
    const declared = new Set(
      // The dist quotes these as template literals (backticks); accept either.
      [...src.matchAll(/[`"]((?:\.likec4rc)|(?:\.?likec4\.config\.(?:json|js|cjs|mjs|ts|cts|mts)))[`"]/g)].map((m) => m[1]),
    );
    expect(declared.size).toBeGreaterThanOrEqual(9);
    expect([...declared].sort()).toEqual([...stageMod.LIKEC4_CONFIG_NAMES].sort());
  });

  it("a module planted in the SERVER's $HOME/.node_modules is not executed by the render", async () => {
    const fakeHome = tmp("c4-fake-home-");
    const s = sentinelPath();
    for (const pkg of ["bufferutil", "fsevents"]) {
      mkdirSync(join(fakeHome, ".node_modules", pkg), { recursive: true });
      writeFileSync(
        join(fakeHome, ".node_modules", pkg, "index.js"),
        `require("node:fs").writeFileSync(${JSON.stringify(s)}, "executed");`,
      );
    }
    const prevHome = process.env.HOME;
    process.env.HOME = fakeHome;
    try {
      const res = await render(fixture());
      expect(res.ok).toBe(true);
      expect(existsSync(s)).toBe(false);
    } finally {
      process.env.HOME = prevHome;
    }
  }, 90_000);
});

// H4 (#8696 Guard 1): what the REAL sandbox lets a payload see. Every row runs
// the builder's argv with only `command` swapped, from the test's FULL env, and
// each negative is preceded by a positive control proving the thing exists and
// is readable OUTSIDE the sandbox (so "unreadable" cannot pass vacuously).
describe.skipIf(!BIN || !BWRAP_OK)("#8696 — the render sandbox, measured with real bwrap", () => {
  function sandboxArgs(stageDir: string, command: string[]): string[] {
    const nodeBin = realpathSync(process.execPath);
    const entry = realpathSync(BIN!);
    const extra: string[] = [];
    for (const p of [dirname(dirname(nodeBin)), dirname(dirname(entry))]) {
      if (p === "/usr" || p.startsWith("/usr/") || extra.some((e) => p === e || p.startsWith(`${e}/`))) continue;
      extra.push(p);
    }
    return renderMod.buildLikeC4SandboxArgv({ stageDir, nodeBin, extraRoBinds: extra, command });
  }
  function stage(): string {
    const d = mkdtempSync(join(stagingRoot, "c4-render-"));
    mkdirSync(join(d, "src"));
    mkdirSync(join(d, "out"), { mode: 0o700 });
    writeFileSync(join(d, "src", "model.c4"), MODEL_C4);
    dirs.push(d);
    return d;
  }
  function run(stageDir: string, command: string[], env: NodeJS.ProcessEnv) {
    return spawnSync("/usr/bin/bwrap", sandboxArgs(stageDir, command), {
      env,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe", "pipe"],
      timeout: 60_000,
    });
  }

  it("H4: files, /proc, env, writes, network and inherited fds are all out of reach", () => {
    const sentinelDir = tmp("c4-sandbox-sentinel-");
    const sentinel = join(sentinelDir, "SENTINEL");
    writeFileSync(sentinel, "tenant secret");
    const envToken = `sentinel-${process.pid}-${Date.now()}`;
    const thisFile = fileURLToPath(import.meta.url);
    // Positive controls, outside the sandbox.
    expect(readFileSync(sentinel, "utf8")).toBe("tenant secret");
    expect(readFileSync(thisFile, "utf8").length).toBeGreaterThan(0);
    const env = { ...process.env, C4_SANDBOX_SENTINEL: envToken };
    const fd = openSync(sentinel, "r");
    try {
      const ino = statSync(sentinel).ino;
      const payload = `
const fs = require("node:fs");
const net = require("node:net");
const out = {};
const can = (f) => { try { f(); return true; } catch { return false; } };
out.sentinel = can(() => fs.readFileSync(${JSON.stringify(sentinel)}));
out.repoFile = can(() => fs.readFileSync(${JSON.stringify(thisFile)}));
out.proc = fs.existsSync("/proc");
out.parentEnviron = can(() => fs.readFileSync("/proc/${process.pid}/environ"));
out.envToken = process.env.C4_SANDBOX_SENTINEL ?? null;
out.envKeys = Object.keys(process.env).sort();
out.pwd = process.env.PWD ?? null;
out.writeSources = can(() => fs.writeFileSync("/c4-sources/x", "x"));
out.writeRoot = can(() => fs.writeFileSync("/x", "x"));
out.writeDev = can(() => fs.writeFileSync("/dev/x", "x"));
out.inos = [];
for (let n = 3; n < 256; n++) { try { out.inos.push(fs.fstatSync(n).ino); } catch {} }
const s = net.connect({ host: "1.1.1.1", port: 80 });
s.on("connect", () => { out.net = "connected"; console.log(JSON.stringify(out)); s.destroy(); });
s.on("error", (e) => { out.net = e.code; console.log(JSON.stringify(out)); });
`;
      const r = run(stage(), [realpathSync(process.execPath), "-e", payload], env);
      expect(r.status, r.stderr).toBe(0);
      const seen = JSON.parse(r.stdout.trim().split("\n").pop()!) as Record<string, unknown>;
      expect(seen).toMatchObject({
        sentinel: false,
        repoFile: false,
        proc: false,
        parentEnviron: false,
        envToken: null,
        writeSources: false,
        writeRoot: false,
        writeDev: false,
      });
      // --clearenv + the four --setenv, plus the PWD bwrap itself sets on --chdir.
      expect(seen.envKeys).toEqual(["HOME", "LANG", "PATH", "PWD", "TMPDIR"]);
      expect(seen.pwd).toBe("/c4-sources");
      expect(seen.net).not.toBe("connected");
      expect(seen.inos as number[]).not.toContain(ino);
    } finally {
      closeSync(fd);
    }
  }, 90_000);

  it("H4: the sandboxed child runs with no_new_privs", () => {
    const r = run(stage(), ["/usr/bin/setpriv", "-d"], process.env);
    expect(r.status, r.stderr).toBe(0);
    expect(r.stdout).toMatch(/no_new_privs:\s*1/i);
  }, 60_000);

  it("H4: a child that plants /c4-out/model.likec4.json as a symlink gets io_error from the host read", async () => {
    const sentinel = join(tmp("c4-sandbox-sentinel-"), "other-tenant-model.json");
    writeFileSync(sentinel, JSON.stringify({ elements: { STOLEN: {} }, views: { index: {} } }));
    const d = stage();
    const plant = `require("node:fs").symlinkSync(${JSON.stringify(sentinel)}, "/c4-out/model.likec4.json")`;
    const r = run(d, [realpathSync(process.execPath), "-e", plant], process.env);
    expect(r.status, r.stderr).toBe(0);
    // The plant landed on the host side of the bind…
    expect(existsSync(join(d, "out", "model.likec4.json"))).toBe(true);
    // …and the host refuses it rather than following it.
    expect(await renderMod.readRenderOutput(join(d, "out"))).toEqual({ ok: false, why: "symlink" });
  }, 60_000);
});

// H2: a missing binary with LIKEC4_REQUIRED set must FAIL the suite, not skip.
// Runs this file as a child vitest; the child skips this row (no recursion).
describe.skipIf(!!process.env.C4_ACCEPTANCE_CHILD)("#8623 acceptance — harness", () => {
  it("H2: LIKEC4_REQUIRED without a resolvable binary fails the suite", () => {
    const appRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
    const r = spawnSync(
      join(appRoot, "node_modules", ".bin", "vitest"),
      ["run", "test/c4-render-tenant-config.test.ts"],
      {
        cwd: appRoot,
        env: {
          ...process.env,
          LIKEC4_BIN: "/nonexistent/likec4",
          LIKEC4_REQUIRED: "1",
          C4_ACCEPTANCE_CHILD: "1",
        },
        encoding: "utf8",
        timeout: 120_000,
      },
    );
    expect(r.status).toBe(1);
    expect(`${r.stdout}${r.stderr}`).toContain("LIKEC4_REQUIRED is set but no likec4 binary resolves");
  }, 150_000);
});
