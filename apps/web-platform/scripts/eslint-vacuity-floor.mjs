#!/usr/bin/env node
// Anti-vacuity floor for the `lint-webplat` CI job (#1327).
//
// `npm run lint` exits 0 on a config that selected almost nothing: `export default []`
// linted 11 of 2019 files and reported success. Without this, the job's green meant only
// "eslint did not error", and its whole anti-vacuity story lived in a different job.
//
// Lives in a file rather than inline in ci.yml for three reasons: a `node -e '...'` block
// inside single-quoted YAML cannot contain an apostrophe (a comment would silently break
// the workflow), an inline block cannot be exercised by the guard suite, and a real file
// can be read by the assertion in test/eslint-config.test.ts that pins this job's shape.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const APP_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/**
 * The floor, read from the guard suite that owns it rather than hand-copied here.
 * Fails CLOSED: a rename or refactor that makes the constant unreadable stops the job
 * rather than silently falling back to a default, which is the shape that turns a floor
 * into decoration.
 */
function minFilesScanned() {
  const src = readFileSync(resolve(APP_ROOT, "test/eslint-config.test.ts"), "utf8");
  const m = [...src.matchAll(/^const MIN_FILES_SCANNED = (\d+);$/gm)];
  if (m.length !== 1) {
    throw new Error(
      `expected exactly one MIN_FILES_SCANNED assignment in test/eslint-config.test.ts, found ${m.length}. ` +
        `The floor this job enforces is defined there; a shadowing or renamed constant makes it ambiguous.`,
    );
  }
  return Number(m[0][1]);
}

/** The arguments the `lint` script itself carries — never a hardcoded `.`. */
function lintScriptArgs() {
  const pkg = JSON.parse(readFileSync(resolve(APP_ROOT, "package.json"), "utf8"));
  return (pkg.scripts?.lint ?? "").trim().split(/\s+/).filter(Boolean).slice(1);
}

function main() {
  const floor = minFilesScanned();
  const args = [...lintScriptArgs(), "-f", "json"];
  let stdout = "";
  try {
    stdout = execFileSync(resolve(APP_ROOT, "node_modules/.bin/eslint"), args, {
      cwd: APP_ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 256 * 1024 * 1024,
      timeout: 300_000,
    });
  } catch (err) {
    // eslint exits non-zero on error-severity findings and still emits a report. Keep it
    // — the count is what this step measures. A genuinely broken run has no parseable
    // report and falls through to the throw below, naming its own cause.
    stdout = err.stdout ?? "";
    if (!stdout) {
      throw new Error(
        `eslint produced no report (code=${err.code ?? "?"} signal=${err.signal ?? "?"} status=${err.status ?? "?"}). ` +
          `stderr:\n${(err.stderr ?? "").toString().trim() || "(empty)"}`,
      );
    }
  }
  const scanned = JSON.parse(stdout).length;
  console.log(`eslint scanned ${scanned} files (floor ${floor}), argv: ${args.join(" ")}`);
  if (scanned < floor) {
    console.log(
      `::error::eslint scanned ${scanned} files, below the anti-vacuity floor of ${floor}. ` +
        `The ESLint step above passed without linting the codebase.`,
    );
    process.exit(1);
  }
}

main();
