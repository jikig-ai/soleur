#!/usr/bin/env node
// CLI for the canonical model.likec4.json format (see c4-canonical.mjs).
// Plugin-only: never bundled, so it may use node:fs and process.argv.
//
//   node c4-canonical-cli.mjs <in>            canonical bytes on stdout, exit 0
//   node c4-canonical-cli.mjs --check <file>  prints "canonical" (exit 0) or
//                                             "not-canonical" (exit 1)
//   any error                                 message on stderr, nothing on stdout, exit 2
import { readFileSync } from "node:fs";
import { canonicalizeC4Model } from "./c4-canonical.mjs";

function main(argv) {
  const check = argv[0] === "--check";
  const file = check ? argv[1] : argv[0];
  if (!file || argv.length !== (check ? 2 : 1)) {
    throw new Error("usage: c4-canonical-cli.mjs [--check] <file>");
  }
  const text = readFileSync(file, "utf8");
  const canonical = canonicalizeC4Model(text);
  if (check) {
    const ok = canonical === text;
    process.stdout.write(ok ? "canonical\n" : "not-canonical\n");
    return ok ? 0 : 1;
  }
  process.stdout.write(canonical);
  return 0;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (err) {
  process.stderr.write(`c4-canonical-cli: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exitCode = 2;
}
