// pen-identity-tree.mjs — build the fake @pen.dev/cli package tree that the binary
// identity rule is tested against, under a caller-supplied (temporary) HOME.
//
// ONE builder feeds BOTH resolvers so they cannot disagree (Guard 2, mutation 4):
//   - check_deps.sh `detect_headless_cli` (test/check-deps-adapter-drift.test.sh), and
//   - the adapter's `findPenBinary()` (an integration test owned by the adapter work).
// Rows live in fixtures/pen-identity-cases.tsv: `layout <TAB> adapter <TAB> check_deps
// <TAB> legacy_warning <TAB> note`. Every layout named there MUST exist in LAYOUTS below;
// the shell test asserts that both ways (no row without a layout, no layout without a row).
//
// CLI:  node pen-identity-tree.mjs <home> <layout>      (prints the prefix directory)
//       node pen-identity-tree.mjs --layouts            (prints the layout names)
// API:  buildPenTree(home, layout, { version, engine }) -> { home, prefix, pkgDir, binPen, fakeBin }
//
// The tree it writes (layout `good`):
//   <home>/.local/share/pen-cli/node_modules/@pen.dev/cli/{package.json,dist/index.mjs,dist/other.mjs}
//   <home>/.local/share/pen-cli/node_modules/.bin/{pen,pencil} -> ../@pen.dev/cli/dist/index.mjs
// `dist/index.mjs` is a tiny fake engine: `status` prints `Status ● Active` and exits 0 only
// when PEN_CLI_KEY equals "valid-key", otherwise prints `Not authenticated` and exits 1; every
// call appends the NAMES (never values) of key-like env variables to <HOME>/engine-env.log, so a
// test can assert the credential reached the child under exactly one name.

import {
  chmodSync,
  copyFileSync,
  mkdirSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const PIN = "0.3.13";
export const PKG = "@pen.dev/cli";
export const VALID_KEY = "valid-key";

const FAKE_ENGINE = `#!/usr/bin/env node
import { appendFileSync } from "node:fs";
const names = Object.keys(process.env).filter((k) => /KEY/.test(k)).sort().join(",");
try { appendFileSync(\`\${process.env.HOME}/engine-env.log\`, \`ARGS=\${process.argv.slice(2).join(" ")} KEYS=\${names}\\n\`); } catch {}
if (process.argv[2] === "status") {
  if (process.env.PEN_CLI_KEY === ${JSON.stringify(VALID_KEY)}) {
    console.log("  Method       CLI Key (PEN_CLI_KEY)\\n  Status       \\u25cf Active");
    process.exit(0);
  }
  console.log("  Status       Not authenticated");
  process.exit(1);
}
process.exit(0);
`;

const BIN_DEFAULT = { pen: "dist/index.mjs", pencil: "dist/index.mjs" };

function put(path, content, mode) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  if (mode) chmodSync(path, mode);
}

function writePackage(pkgDir, { name = PKG, version = PIN, bin = BIN_DEFAULT, engine = FAKE_ENGINE } = {}) {
  put(join(pkgDir, "package.json"), JSON.stringify({ name, version, bin, engines: { node: ">=22.19.0" } }, null, 2));
  put(join(pkgDir, "dist/index.mjs"), engine, 0o755);
  put(join(pkgDir, "dist/other.mjs"), "// not the declared bin\n", 0o755);
}

function link(target, path) {
  mkdirSync(dirname(path), { recursive: true });
  symlinkSync(target, path);
}

/** The deprecated engine: ~/.local/node_modules/@pencil.dev/cli with .bin/pencil. */
function writeLegacy(home, version = "0.2.9") {
  const root = join(home, ".local/node_modules");
  const dir = join(root, "@pencil.dev/cli");
  put(
    join(dir, "package.json"),
    JSON.stringify({ name: "@pencil.dev/cli", version, bin: { pencil: "dist/index.cjs" } }, null, 2)
  );
  put(join(dir, "dist/index.cjs"), "// deprecated engine\n", 0o755);
  link("../@pencil.dev/cli/dist/index.cjs", join(root, ".bin/pencil"));
}

// layout name -> (ctx) => void. ctx: { home, prefix, pkgDir, bin, opts }
export const LAYOUTS = {
  // correct install
  good({ pkgDir, bin, opts }) {
    writePackage(pkgDir, opts);
    link("../@pen.dev/cli/dist/index.mjs", join(bin, "pen"));
    link("../@pen.dev/cli/dist/index.mjs", join(bin, "pencil"));
  },
  // correct install whose version is not the pin: accepted, with a warning
  "version-differs"(ctx) {
    LAYOUTS.good({ ...ctx, opts: { ...ctx.opts, version: "0.3.12" } });
  },
  // correct install plus a leftover deprecated engine: accepted, with a leftover-package warning
  "good-plus-legacy"(ctx) {
    LAYOUTS.good(ctx);
    writeLegacy(ctx.home);
  },
  // only the deprecated engine: the headless tier must not be selected, a warning is printed
  "legacy-only"({ home }) {
    writeLegacy(home);
  },
  // package.json name is not @pen.dev/cli
  "name-mismatch"({ pkgDir, bin, opts }) {
    writePackage(pkgDir, { ...opts, name: "@evil/cli" });
    link("../@pen.dev/cli/dist/index.mjs", join(bin, "pen"));
  },
  // package declares no `pen` bin (only `pencil`): never fall back to the pencil name
  "declared-bin-missing"({ pkgDir, bin, opts }) {
    writePackage(pkgDir, { ...opts, bin: { pencil: "dist/index.mjs" } });
    link("../@pen.dev/cli/dist/index.mjs", join(bin, "pen"));
  },
  // link target sits under a sibling directory whose name merely starts with the package path
  "bin-sibling-prefix"({ prefix, pkgDir, bin, opts }) {
    writePackage(pkgDir, opts);
    put(join(prefix, "node_modules/@pen.dev/cli-evil/dist/index.mjs"), "// evil\n", 0o755);
    link("../@pen.dev/cli-evil/dist/index.mjs", join(bin, "pen"));
  },
  // link target is another file inside the package, not the declared bin.pen target
  "bin-other-file"({ pkgDir, bin, opts }) {
    writePackage(pkgDir, opts);
    link("../@pen.dev/cli/dist/other.mjs", join(bin, "pen"));
  },
  // .bin/pen is a regular copy, not a link to the declared target
  "bin-regular-file"({ pkgDir, bin, opts }) {
    writePackage(pkgDir, opts);
    put(join(bin, "pen"), FAKE_ENGINE, 0o755);
  },
  // the declared bin.pen path itself escapes the package directory and .bin/pen follows it
  "declared-bin-escapes"({ prefix, pkgDir, bin, opts }) {
    writePackage(pkgDir, { ...opts, bin: { pen: "../cli-evil/dist/index.mjs" } });
    put(join(prefix, "node_modules/@pen.dev/cli-evil/dist/index.mjs"), "// evil\n", 0o755);
    link("../@pen.dev/cli-evil/dist/index.mjs", join(bin, "pen"));
  },
  // only .bin/pencil exists in the new package: the pencil name is never accepted
  "pencil-bin-only"({ pkgDir, bin, opts }) {
    writePackage(pkgDir, opts);
    link("../@pen.dev/cli/dist/index.mjs", join(bin, "pencil"));
  },
  // the package is present but there is no .bin entry at all
  "bin-missing"({ pkgDir, opts }) {
    writePackage(pkgDir, opts);
  },
  // .bin/pen points at the deprecated engine while a valid new package.json exists
  "bin-points-at-legacy"({ home, pkgDir, bin, opts }) {
    writePackage(pkgDir, opts);
    writeLegacy(home);
    link("../../../../node_modules/@pencil.dev/cli/dist/index.cjs", join(bin, "pen"));
  },
  // nothing installed; a foreign `pen` is on PATH (<home>/fakebin is prepended by the runner)
  "path-pen-only"({ home }) {
    put(join(home, "fakebin/pen"), "#!/bin/sh\necho foreign pen\n", 0o755);
  },
};

export function buildPenTree(home, layout, opts = {}) {
  const build = LAYOUTS[layout];
  if (!build) throw new Error(`unknown pen identity layout: ${layout}`);
  const prefix = join(home, ".local/share/pen-cli");
  const pkgDir = join(prefix, "node_modules/@pen.dev/cli");
  const bin = join(prefix, "node_modules/.bin");
  mkdirSync(join(home, ".local"), { recursive: true });
  build({ home, prefix, pkgDir, bin, opts });
  return { home, prefix, pkgDir, binPen: join(bin, "pen"), fakeBin: join(home, "fakebin") };
}

/** Copy the repo's committed lockfile pair next to a prefix (what check_deps.sh installs from). */
export function copyLockPair(fromDir, prefix) {
  mkdirSync(prefix, { recursive: true });
  for (const f of ["package.json", "package-lock.json"]) copyFileSync(join(fromDir, f), join(prefix, f));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const [a, b] = process.argv.slice(2);
  if (a === "--layouts") {
    console.log(Object.keys(LAYOUTS).join("\n"));
  } else if (a && b) {
    console.log(buildPenTree(a, b).prefix);
  } else {
    console.error("usage: pen-identity-tree.mjs <home> <layout> | --layouts");
    process.exit(2);
  }
}
