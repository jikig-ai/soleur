/**
 * #12011 PR-C task 6.7: the text registry must be readable in the DEPLOYED image, not only in the source tree.
 *
 * The production server is `esbuild --bundle` into dist/server/index.cjs and the Dockerfile copies only that directory
 * plus (since this PR) server/legal-acceptance/texts. A test that reads the source tree proves nothing, so this one
 * builds a real bundle with the production esbuild flags, lays it out like /app (bundle at dist/server, texts under
 * server/legal-acceptance/texts, cwd = the app root), runs it with node, and compares the hash with `sha256sum`.
 */
import { describe, expect, it, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { TEXTS_DIR, TEXTS_DIR_FROM_CWD, resolveTextsDir } from "@/server/legal-acceptance/canonical";

const APP = path.resolve(__dirname, "../..");
const FIX = path.join(__dirname, "fixtures/hash-fixture.md");
const EXPECTED = readFileSync(path.join(__dirname, "fixtures/hash-fixture.sha256"), "utf8").trim();
const ESBUILD = path.join(APP, "node_modules/.bin/esbuild");

let root: string;
let bundle: string;

const run = (cwd: string, ...args: string[]) =>
  spawnSync("node", [bundle, ...args], { cwd, encoding: "utf8", env: { ...process.env, NODE_OPTIONS: "" } });

beforeAll(() => {
  root = mkdtempSync(path.join(tmpdir(), "legal-image-"));
  // The probe is bundled exactly like the server (same flags as `build:server`), into dist/server like the image.
  const probe = path.join(root, "probe.ts");
  writeFileSync(
    probe,
    `import { getLegalText } from ${JSON.stringify(path.join(APP, "server/legal-acceptance/canonical.ts"))};\n` +
      `try { const e = getLegalText(process.argv[2]); console.log(JSON.stringify({ ok: true, hash: e.textHash, version: e.version })); }\n` +
      `catch (err) { console.log(JSON.stringify({ ok: false, code: err.code })); }\n`,
  );
  mkdirSync(path.join(root, "app/dist/server"), { recursive: true });
  bundle = path.join(root, "app/dist/server/index.cjs");
  const b = spawnSync(ESBUILD, [probe, "--bundle", "--platform=node", "--target=node22", `--outfile=${bundle}`, "--log-level=error"], {
    encoding: "utf8",
  });
  if (b.status !== 0) throw new Error(`esbuild failed: ${b.stderr.slice(0, 500)}`);
});
afterAll(() => rmSync(root, { recursive: true, force: true }));

describe("deployed resolution path (bundle at dist/server, texts copied to server/legal-acceptance/texts)", () => {
  it("negative control: with no texts directory in the image the bundle cannot load the key (the pre-PR-C state)", () => {
    const out = run(path.join(root, "app"), "hash-fixture");
    expect(JSON.parse(out.stdout)).toEqual({ ok: false, code: "unknown_key" });
  });

  it("the bundle loads a fixture text from <cwd>/server/legal-acceptance/texts and the hash equals sha256sum of the deployed file", () => {
    const dir = path.join(root, "app", TEXTS_DIR_FROM_CWD);
    mkdirSync(dir, { recursive: true });
    const deployed = path.join(dir, "hash-fixture.md");
    copyFileSync(FIX, deployed);

    const out = run(path.join(root, "app"), "hash-fixture");
    expect(out.status).toBe(0);
    expect(JSON.parse(out.stdout)).toEqual({ ok: true, hash: EXPECTED, version: "fixture-1" });

    const sh = spawnSync("sha256sum", [deployed], { encoding: "utf8" });
    expect(sh.stdout.split(" ")[0]).toBe(EXPECTED);
    // The bundle's own directory has no texts: the old __dirname-only resolution could not have found it.
    expect(existsSync(path.join(root, "app/dist/server/texts"))).toBe(false);
  });
});

describe("resolveTextsDir", () => {
  const e = (...present: string[]) => (p: string) => present.includes(p);
  it("prefers the directory next to the module", () => {
    expect(resolveTextsDir({ moduleDir: "/m", cwd: "/c", exists: e("/m/texts", "/c/server/legal-acceptance/texts") })).toBe("/m/texts");
  });
  it("falls back to <cwd>/server/legal-acceptance/texts when the module directory has none", () => {
    expect(resolveTextsDir({ moduleDir: "/app/dist/server", cwd: "/app", exists: e("/app/server/legal-acceptance/texts") })).toBe(
      "/app/server/legal-acceptance/texts",
    );
  });
  it("with no module directory (ESM bundle, no __dirname) it still uses the cwd path", () => {
    expect(resolveTextsDir({ moduleDir: undefined, cwd: "/app", exists: e("/app/server/legal-acceptance/texts") })).toBe(
      "/app/server/legal-acceptance/texts",
    );
  });
  it("when neither exists it returns the module-relative path so a missing directory still fails as unknown_key", () => {
    expect(resolveTextsDir({ moduleDir: "/m", cwd: "/c", exists: () => false })).toBe("/m/texts");
  });
  it("in the source tree the default resolves to the real directory", () => {
    expect(existsSync(TEXTS_DIR)).toBe(true);
    expect(TEXTS_DIR).toBe(path.join(APP, "server/legal-acceptance/texts"));
  });
});

describe("image build wiring", () => {
  const dockerfile = readFileSync(path.join(APP, "Dockerfile"), "utf8");
  const ignore = readFileSync(path.join(APP, ".dockerignore"), "utf8").split("\n");

  it("the runner stage copies the texts directory to the path the resolver reads (cwd is /app)", () => {
    const runner = dockerfile.slice(dockerfile.search(/^FROM\s+\S+\s+AS\s+runner\s*$/m));
    expect(runner).toMatch(/^COPY --from=builder \/app\/server\/legal-acceptance\/texts \.\/server\/legal-acceptance\/texts$/m);
    expect(runner).toMatch(/^WORKDIR \/app$/m);
    expect(TEXTS_DIR_FROM_CWD).toBe(path.join("server", "legal-acceptance", "texts"));
  });

  it("the build context keeps the registry files: a re-include follows the *.md exclusion", () => {
    const star = ignore.indexOf("*.md");
    const keep = ignore.indexOf("!server/legal-acceptance/texts/*.md");
    expect(star).toBeGreaterThan(-1);
    expect(keep).toBeGreaterThan(star);
    expect(ignore).not.toContain("server/");
    expect(ignore).not.toContain("server");
  });
});
