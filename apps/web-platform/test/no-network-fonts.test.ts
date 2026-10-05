/**
 * Guard: no build-time network font fetch (merge-queue slow-failures work, Ref #9482).
 *
 * `next/font/google` resolves the font loader (a network fetch, suspected as the
 * transient cause, #8785) inside the compile of `app/layout.tsx`. When that fails the
 * first compile of the authenticated e2e dev server 5xx's, and every authenticated
 * test then fails one by one (64 reds in about 14 min instead of about 3). The font is
 * vendored under `assets/fonts/` and loaded through `next/font/local`; this suite keeps
 * it that way.
 *
 * Property: no source file under apps/web-platform imports `next/font/google` or
 * names fonts.googleapis.com / fonts.gstatic.com, the one required vendored asset
 * exists, starts with the WOFF2 magic and is non-empty, and `app/fonts.ts` points at
 * it. It does NOT prove the asset is untampered: its hash is recorded only in
 * assets/fonts/README.md (a truncated file fails `next build` and e2e).
 *
 * The scan reads raw text on purpose (no comment stripping): a comment that names the
 * host is also a hit, which keeps the rule trivially explainable.
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
import { dirname, extname, join, relative, resolve, sep } from "node:path";

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
  ".html",
  ".mdx",
]);
// Ignored by path SEGMENT, never by substring.
const IGNORED_SEGMENTS = new Set(["node_modules", ".next"]);
const REQUIRED_ASSETS = ["assets/fonts/inter-latin-wght.woff2"];
// 2,304 files measured on 2026-10-05 across SWEPT_EXTENSIONS under apps/web-platform.
const MIN_FILES = 1_500;

const FORBIDDEN =
  /next\/font\/google|fonts\.googleapis\.com|fonts\.gstatic\.com/;

type Enumerator = (root: string) => string[];

// An inherited GIT_DIR / GIT_INDEX_FILE (a hook environment) would point git at the
// caller's repository instead of `root`, so strip the whole GIT_ prefix.
const GIT_FREE_ENV = Object.fromEntries(
  Object.entries(process.env).filter(([k]) => !k.startsWith("GIT_")),
) as NodeJS.ProcessEnv;

function enumerateGit(root: string): string[] {
  return execFileSync(
    "git",
    ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    { cwd: root, maxBuffer: 64 * 1024 * 1024, env: GIT_FREE_ENV },
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
  return SWEPT_EXTENSIONS.has(extname(rel));
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
    } else if (readFileSync(full).subarray(0, 4).toString("latin1") !== "wOF2") {
      problems.push(`${asset}: vendored font is not a WOFF2 file`);
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

  describe("axes the first rows did not edit", () => {
    // One forbidden file per swept extension: dropping any extension from
    // SWEPT_EXTENSIONS must turn one of these red.
    for (const ext of [".ts", ".tsx", ".js", ".jsx", ".mjs", ".mts", ".cjs", ".css", ".scss", ".html", ".mdx"]) {
      it(`a forbidden reference in a ${ext} file is found`, () => {
        const root = tree({
          "app/fonts.ts": LOCAL_FONT,
          [`lib/x${ext}`]: "https://fonts.googleapis.com/css2?family=Inter\n",
          ...ASSET,
        });
        try {
          expect(() => sweep(root, enumerateWalk, FIXTURE_OPTS)).toThrow(
            new RegExp(`lib/x\\${ext}: network font reference`),
          );
        } finally {
          rmSync(root, { recursive: true, force: true });
        }
      });
    }

    // One row per alternative of FORBIDDEN, each ALONE.
    for (const [name, text] of [
      ["next/font/google", `import { Inter } from "next/font/google";`],
      ["fonts.googleapis.com", `@import url(https://fonts.googleapis.com/css2);`],
      ["fonts.gstatic.com", `src: url(https://fonts.gstatic.com/s/inter/v20/x.woff2);`],
    ] as const) {
      it(`the ${name} alternative alone is found`, () => {
        const root = tree({ "app/fonts.ts": LOCAL_FONT, "app/y.css": `${text}\n`, ...ASSET });
        try {
          expect(() => sweep(root, enumerateWalk, FIXTURE_OPTS)).toThrow(
            /app\/y\.css: network font reference/,
          );
        } finally {
          rmSync(root, { recursive: true, force: true });
        }
      });
    }

    // Every top-level directory the real tree sweeps must contribute: ignoring
    // a whole directory (server/, e2e/, hooks/, ...) must not hide behind the floor's headroom.
    it("each top-level source directory contributes scanned files in the real tree", () => {
      const tops = new Set(
        enumerateGit(APP_ROOT)
          .filter(isSwept)
          .map((rel) => rel.split(sep)[0])
          .filter((seg) => seg.length > 0),
      );
      for (const dir of ["app", "components", "lib", "server", "e2e", "test", "hooks", "scripts"]) {
        expect(tops.has(dir), `${dir}/ contributed no swept file`).toBe(true);
      }
    });

    it("a vendored font that is not a WOFF2 file fails", () => {
      const root = tree({
        "app/fonts.ts": LOCAL_FONT,
        "assets/fonts/inter-latin-wght.woff2": "not-a-font",
      });
      try {
        expect(() => sweep(root, enumerateWalk, FIXTURE_OPTS)).toThrow(
          /not a WOFF2 file/,
        );
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });

    it("an unreadable swept path throws instead of being skipped (only ENOENT is tolerated)", () => {
      const root = tree({ "app/fonts.ts": LOCAL_FONT, ...ASSET });
      mkdirSync(join(root, "app/dir.ts"));
      try {
        expect(() =>
          sweep(root, () => ["app/fonts.ts", "app/dir.ts"], FIXTURE_OPTS),
        ).toThrow(/EISDIR/);
        expect(
          sweep(root, () => ["app/fonts.ts", "app/gone.ts"], FIXTURE_OPTS),
        ).toBe(1);
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });

    it("enumerateGit lists untracked files and honours .gitignore (flags --others, --exclude-standard)", () => {
      const root = tree({
        ".gitignore": "gen/\n",
        "app/fonts.ts": LOCAL_FONT,
        "app/new-untracked.ts": `import { Inter } from "next/font/google";\n`,
        "gen/ignored.ts": `import { Inter } from "next/font/google";\n`,
        ...ASSET,
      });
      try {
        execFileSync("git", ["init", "-q"], { cwd: root, env: GIT_FREE_ENV });
        const listed = enumerateGit(root).sort();
        expect(listed).toContain("app/new-untracked.ts");
        expect(listed).not.toContain("gen/ignored.ts");
        // The git enumerator and the plain walk agree once ignore rules are applied.
        const walked = enumerateWalk(root).filter((r) => !r.startsWith(".git" + sep) && !r.startsWith("gen" + sep)).sort();
        expect(listed).toEqual(walked);
        expect(() => sweep(root, enumerateGit, FIXTURE_OPTS)).toThrow(
          /app\/new-untracked\.ts: network font reference/,
        );
      } finally {
        rmSync(root, { recursive: true, force: true });
      }
    });
  });

  it("app/fonts.ts loads the required vendored asset", () => {
    const src = readFileSync(join(APP_ROOT, "app/fonts.ts"), "utf8");
    const m = /src:\s*"([^"]+\.woff2)"/.exec(src);
    expect(m, "fonts.ts must load a .woff2 through next/font/local").not.toBeNull();
    const target = resolve(join(APP_ROOT, "app"), m![1]);
    expect(REQUIRED_ASSETS.map((a) => join(APP_ROOT, a))).toContain(target);
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
