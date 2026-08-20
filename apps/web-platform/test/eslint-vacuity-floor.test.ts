import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Behavioural guard for scripts/eslint-vacuity-floor.mjs — the anti-vacuity floor the
 * `lint-webplat` CI job runs after `npm run lint`.
 *
 * The sibling suite (eslint-config.test.ts) asserts this script EXISTS, contains
 * `process.exit(1)`, and reads MIN_FILES_SCANNED from the guard file. All three are
 * source greps: they pin the script's TEXT, not its behaviour, and nothing drove the
 * failing direction. A script that computed the floor correctly and then never compared
 * would satisfy every one of them — which is the defect class this whole PR exists to
 * close, one file over.
 *
 * So this drives the real script, both directions, against a sandbox it fully controls.
 * The script resolves APP_ROOT from its own location (`dirname(import.meta.url)/..`),
 * which is what makes a sandbox possible: copy it into `<tmp>/scripts/` and it reads
 * `<tmp>/package.json`, `<tmp>/test/eslint-config.test.ts` and `<tmp>/node_modules/.bin/eslint`.
 */
const APP_ROOT = resolve(__dirname, "..");
const REAL_SCRIPT = resolve(APP_ROOT, "scripts/eslint-vacuity-floor.mjs");
const REAL_ESLINT = resolve(APP_ROOT, "node_modules/.bin/eslint");

/** A self-contained app root: real script, real eslint, synthetic sources. */
function sandbox(opts: { floor: number; config: string; sources: Record<string, string> }) {
  const dir = mkdtempSync(join(tmpdir(), "eslint-floor-"));
  mkdirSync(join(dir, "scripts"), { recursive: true });
  mkdirSync(join(dir, "test"), { recursive: true });
  mkdirSync(join(dir, "node_modules"), { recursive: true });
  // Symlink the real eslint rather than reinstalling a toolchain.
  mkdirSync(join(dir, "node_modules/.bin"), { recursive: true });
  symlinkSync(REAL_ESLINT, join(dir, "node_modules/.bin/eslint"));
  writeFileSync(join(dir, "scripts/eslint-vacuity-floor.mjs"), readFileSync(REAL_SCRIPT, "utf8"));
  writeFileSync(
    join(dir, "package.json"),
    JSON.stringify({ name: "sandbox", scripts: { lint: "eslint ." } }, null, 2),
  );
  // The floor's only source of truth, in the shape the script's regex requires.
  writeFileSync(
    join(dir, "test/eslint-config.test.ts"),
    `const MIN_FILES_SCANNED = ${opts.floor};\nvoid MIN_FILES_SCANNED;\n`,
  );
  writeFileSync(join(dir, "eslint.config.mjs"), opts.config);
  for (const [rel, body] of Object.entries(opts.sources)) {
    const p = join(dir, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, body);
  }
  return dir;
}

function runFloor(dir: string): { status: number; out: string } {
  try {
    const out = execFileSync(process.execPath, ["scripts/eslint-vacuity-floor.mjs"], {
      cwd: dir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 120_000,
    });
    return { status: 0, out };
  } catch (err) {
    const e = err as { status?: number; stdout?: string; stderr?: string };
    return { status: e.status ?? 1, out: `${e.stdout ?? ""}${e.stderr ?? ""}` };
  }
}

const REAL_CONFIG = 'export default [{ files: ["**/*.ts"], rules: {} }];\n';
const THREE_FILES = { "a.ts": "export const a = 1;\n", "b.ts": "export const b = 2;\n", "c.ts": "export const c = 3;\n" };

describe("eslint-vacuity-floor.mjs — the CI job's anti-vacuity floor", () => {
  it("exits 0 and reports the count when the scan clears the floor", () => {
    expect.assertions(2);
    const dir = sandbox({ floor: 2, config: REAL_CONFIG, sources: THREE_FILES });
    try {
      const { status, out } = runFloor(dir);
      expect(status).toBe(0);
      expect(out).toMatch(/eslint scanned \d+ files \(floor 2\)/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 180_000);

  it("exits 1 and emits ::error:: when a vacuous config scans below the floor", () => {
    expect.assertions(3);
    // `export default []` is the measured real-world vacuity: it linted 11 of 2019 files
    // in this repo and exited 0, which is why this floor exists at all.
    const dir = sandbox({ floor: 99, config: "export default [];\n", sources: THREE_FILES });
    try {
      const { status, out } = runFloor(dir);
      expect(status).toBe(1);
      expect(out).toMatch(/::error::/);
      expect(out).toMatch(/below the anti-vacuity floor of 99/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 180_000);

  it("fails CLOSED when the floor constant cannot be read", () => {
    expect.assertions(2);
    const dir = sandbox({ floor: 2, config: REAL_CONFIG, sources: THREE_FILES });
    try {
      // A rename or refactor that makes MIN_FILES_SCANNED unreadable must STOP the job,
      // not fall back to a default — a floor that silently defaults is decoration.
      writeFileSync(join(dir, "test/eslint-config.test.ts"), "const SOMETHING_ELSE = 2;\n");
      const { status, out } = runFloor(dir);
      expect(status).not.toBe(0);
      expect(out).toMatch(/expected exactly one MIN_FILES_SCANNED assignment/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 180_000);

  it("derives its argv from the lint script rather than hardcoding `.`", () => {
    expect.assertions(2);
    const dir = sandbox({ floor: 1, config: REAL_CONFIG, sources: THREE_FILES });
    try {
      // Narrow the lint script to one file. A hardcoded `eslint .` would still scan 3
      // and clear the floor; deriving the argv means it scans 1 and reports that.
      writeFileSync(
        join(dir, "package.json"),
        JSON.stringify({ name: "sandbox", scripts: { lint: "eslint a.ts" } }, null, 2),
      );
      const { status, out } = runFloor(dir);
      expect(status).toBe(0);
      expect(out).toMatch(/eslint scanned 1 files \(floor 1\), argv: a\.ts -f json/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }, 180_000);
});
