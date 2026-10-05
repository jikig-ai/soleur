/**
 * Guard: no build-time network font fetch (merge-queue slow-failures work, Ref #9482).
 *
 * `next/font/google` fetches the font from fonts.gstatic.com inside the compile of
 * `app/layout.tsx`. When that fetch fails the first compile of the authenticated e2e
 * dev server 5xx's, and every authenticated test then fails one by one (64 reds in
 * about 14 min instead of about 3). The font is vendored under `assets/fonts/` and
 * loaded through `next/font/local`; this suite keeps it that way.
 *
 * Property: no source file under apps/web-platform imports `next/font/google` or
 * names fonts.googleapis.com / fonts.gstatic.com, and every vendored font asset exists
 * and is non-empty. It does NOT prove the asset is untampered: its hash is recorded
 * only in assets/fonts/README.md (a truncated file fails `next build` and e2e).
 *
 * The sweep is parameterised on an enumerator so the mutation rows below run against a
 * synthesized temp tree (a temp dir is not a repository). Production enumerates with
 * `git ls-files --cached --others --exclude-standard`, so an untracked new file is
 * swept too.
 */
import { describe, expect, it } from "vitest";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, join, relative, sep } from "node:path";

const APP_ROOT = join(__dirname, "..");
const SELF = "test/no-network-fonts.test.ts";

const SWEPT_EXTENSIONS = new Set([
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".mts",
  ".cjs",
  ".css",
  ".scss",
]);
// Ignored by path SEGMENT, never by substring.
const IGNORED_SEGMENTS = new Set(["node_modules", ".next"]);
const REQUIRED_ASSETS = ["assets/fonts/inter-latin-wght.woff2"];
// 2,304 files measured on 2026-10-05 across SWEPT_EXTENSIONS under apps/web-platform.
const MIN_FILES = 1_500;

const FORBIDDEN =
  /next\/font\/google|fonts\.googleapis\.com|fonts\.gstatic\.com/;

type Enumerator = (root: string) => string[];

function enumerateGit(root: string): string[] {
  return execFileSync(
    "git",
    ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    { cwd: root, maxBuffer: 64 * 1024 * 1024 },
  )
    .toString("utf8")
    .split("\0")
    .filter(Boolean);
}

function enumerateWalk(root: string): string[] {
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else out.push(relative(root, full));
    }
  };
  walk(root);
  return out;
}

function isSwept(rel: string): boolean {
  if (rel === SELF) return false;
  if (rel.split(sep).some((seg) => IGNORED_SEGMENTS.has(seg))) return false;
  const base = basename(rel);
  return SWEPT_EXTENSIONS.has(extname(rel)) || base.startsWith("next.config.");
}

interface SweepOptions {
  minFiles: number;
  requiredAssets: string[];
  pattern?: RegExp;
}

/** Throws with a message naming every violation; returns the swept file count. */
function sweep(root: string, enumerate: Enumerator, opts: SweepOptions): number {
  const pattern = opts.pattern ?? FORBIDDEN;
  const problems: string[] = [];
  let scanned = 0;
  for (const rel of enumerate(root).filter(isSwept)) {
    let text: string;
    try {
      text = readFileSync(join(root, rel), "utf8");
    } catch (err) {
      // Tracked-but-deleted file: git still lists it, the working tree does not.
      if ((err as NodeJS.ErrnoException).code === "ENOENT") continue;
      throw err;
    }
    scanned += 1;
    if (pattern.test(text)) problems.push(`${rel}: network font reference`);
  }
  for (const asset of opts.requiredAssets) {
    const full = join(root, asset);
    if (!existsSync(full) || statSync(full).size === 0) {
      problems.push(`${asset}: vendored font missing or empty`);
    }
  }
  if (scanned < opts.minFiles) {
    problems.push(
      `sweep examined too few files: ${scanned} files scanned, floor ${opts.minFiles}`,
    );
  }
  if (problems.length > 0) {
    throw new Error(`${problems.join("\n")}\n(${scanned} files scanned)`);
  }
  return scanned;
}

function tree(files: Record<string, string>): string {
  const root = mkdtempSync(join(tmpdir(), "no-network-fonts-"));
  for (const [rel, content] of Object.entries(files)) {
    mkdirSync(dirname(join(root, rel)), { recursive: true });
    writeFileSync(join(root, rel), content);
  }
  return root;
}

const LOCAL_FONT = `import localFont from "next/font/local";\nexport const sans = localFont({ src: "./x.woff2" });\n`;
const FIXTURE_OPTS: SweepOptions = {
  minFiles: 1,
  requiredAssets: ["assets/fonts/inter-latin-wght.woff2"],
};
const ASSET = { "assets/fonts/inter-latin-wght.woff2": "wOF2-fixture" };

describe("no build-time network font fetch", () => {
  it("the real tree is clean and the sweep is not vacuous", () => {
    const scanned = sweep(APP_ROOT, enumerateGit, {
      minFiles: MIN_FILES,
      requiredAssets: REQUIRED_ASSETS,
    });
    console.log(`scanned ${scanned} files`);
    expect(scanned).toBeGreaterThanOrEqual(MIN_FILES);
  });

  describe("mutation rows (synthesized tree)", () => {
    const cases: Array<[string, Record<string, string>, RegExp]> = [
      [
        "1: next/font/google import in app/fonts.ts",
        {
          "app/fonts.ts": `import { Inter } from "next/font/google";\n`,
          ...ASSET,
        },
        /app\/fonts\.ts: network font reference/,
      ],
      [
        "2: second member after a compliant first",
        {
          "app/fonts.ts": LOCAL_FONT,
          "components/x.tsx": `import { Roboto } from "next/font/google";\n`,
          ...ASSET,
        },
        /components\/x\.tsx: network font reference/,
      ],
      [
        "3: css @import of fonts.googleapis.com",
        {
          "app/fonts.ts": LOCAL_FONT,
          "app/globals.css": `@import url(https://fonts.googleapis.com/css2?family=Inter);\n`,
          ...ASSET,
        },
        /app\/globals\.css: network font reference/,
      ],
      [
        "4: vendored font emptied",
        {
          "app/fonts.ts": LOCAL_FONT,
          "assets/fonts/inter-latin-wght.woff2": "",
        },
        /vendored font missing or empty/,
      ],
      [
        "4b: vendored font absent",
        { "app/fonts.ts": LOCAL_FONT },
        /vendored font missing or empty/,
      ],
      [
        "6: forbidden import in a .mts file",
        {
          "app/fonts.ts": LOCAL_FONT,
          "lib/x.mts": `import { Inter } from "next/font/google";\n`,
          ...ASSET,
        },
        /lib\/x\.mts: network font reference/,
      ],
      [
        "6b: forbidden import in a .cjs file",
        {
          "app/fonts.ts": LOCAL_FONT,
          "lib/x.cjs": `require("next/font/google");\n`,
          ...ASSET,
        },
        /lib\/x\.cjs: network font reference/,
      ],
    ];
    for (const [name, files, message] of cases) {
      it(`row ${name} turns the sweep red`, () => {
        const root = tree(files);
        try {
          expect(() => sweep(root, enumerateWalk, FIXTURE_OPTS)).toThrow(
            message,
          );
        } finally {
          rmSync(root, { recursive: true, force: true });
        }
      });
    }

    it("row 5: an empty tree fails on its own message, not a git-state error", () => {
      const root = mkdtempSync(join(tmpdir(), "no-network-fonts-empty-"));
      try {
        expect(() =>
          sweep(root, enumerateWalk, { minFiles: 1, requiredAssets: [] }),
        ).toThrow(/0 files scanned/);
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });
  });

  describe("harness rows", () => {
    it("RED: a weakened detection regex lets row 1 through (so the row-1 assertion is not vacuous)", () => {
      const root = tree({
        "app/fonts.ts": `import { Inter } from "next/font/google";\n`,
        ...ASSET,
      });
      try {
        const weakened = /fonts\.googleapis\.com|fonts\.gstatic\.com/;
        expect(() =>
          sweep(root, enumerateWalk, { ...FIXTURE_OPTS, pattern: weakened }),
        ).not.toThrow();
        expect(() => sweep(root, enumerateWalk, FIXTURE_OPTS)).toThrow();
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });

    it("must-PASS non-canonical: local font imports plus a markdown mention are clean", () => {
      const root = tree({
        "app/fonts.ts": LOCAL_FONT,
        "app/other-fonts.ts": LOCAL_FONT,
        "docs/notes.md": "Inter used to load from fonts.gstatic.com.\n",
        "node_modules/pkg/index.js": `require("next/font/google");\n`,
        ...ASSET,
      });
      try {
        expect(sweep(root, enumerateWalk, FIXTURE_OPTS)).toBe(2);
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });
  });
});
