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
  existsSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
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

type Render = typeof import("@/server/c4-render").renderC4Model;
type StageMod = typeof import("@/server/c4-stage-sources");
let renderC4Model: Render;
let stageMod: StageMod;
let stagingRoot: string;

beforeAll(async () => {
  if (!BIN) return;
  stagingRoot = tmp("c4-staging-root-");
  vi.stubEnv("LIKEC4_BIN", BIN);
  vi.stubEnv("C4_RENDER_STAGING_ROOT", stagingRoot);
  vi.resetModules();
  // LIKEC4_BIN is read at module load — import AFTER stubbing it.
  renderC4Model = (await import("@/server/c4-render")).renderC4Model;
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

  it("a benign tree renders: ok, element ids exactly {u, s} (dispatch is real)", async () => {
    const res = await render(fixture());
    expect(res.ok).toBe(true);
    if (res.ok) expect(elementIds(res.json)).toEqual(["s", "u"]);
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
