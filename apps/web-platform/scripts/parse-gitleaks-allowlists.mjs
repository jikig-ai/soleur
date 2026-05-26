#!/usr/bin/env node
// Extract the union of `paths = [...]` regex literals from a .gitleaks.toml
// file and emit a deduped JSON array on stdout.
//
// Used by:
//   - apps/web-platform/scripts/rename-guard.sh    (#3160) — uses output as PCRE
//   - apps/web-platform/scripts/allowlist-diff.sh  (#3323) — uses output as set
//
// Output contract: each emitted string is BOTH a deduplication key AND a PCRE
// regex. If gitleaks ever introduces a non-regex glob syntax (or path metadata
// like description/commits) and the dual-contract breaks, fork into two parsers
// rather than parameterize one with a `--shape=glob` flag.
//
// Why no @iarna/toml dep: mirrors the no-dep convention of
// lint-fixture-content.mjs. The .gitleaks.toml today uses ONLY triple-quoted
// (`'''…'''`) literals inside `paths = [...]` arrays — both top-level
// `[allowlist]` and per-rule `[[rules.allowlists]]`. Empirical baseline at
// plan time: 14 unique paths.
//
// Walker shape: a string-aware character-by-character pass over each
// `paths = [ … ]` body so brackets inside `'''…'''` literals (e.g.
// character-class regexes like `[A-Z]+`) don't terminate the array body
// prematurely. A naive `\[([\s\S]*?)\]` regex truncates at the first inner
// `]`; T7 in the harness pins this behavior.
//
// Schema lock: gitleaks v8.24.2 syntax. v8.25+ adds top-level `[[allowlists]]`
// with `targetRules = […]`; the parser exits 4 + warns when it encounters
// that shape so the operator updates this script alongside the gitleaks bump.
//
// Edge cases NOT handled (intentional scope-out — switch to @iarna/toml if
// .gitleaks.toml ever uses these):
//   - nested arrays                  paths = [['a', 'b']]
//   - double-quoted "…" literals     paths = ["foo"]    (only ''' is read)
//
// Exit codes:
//   0 — success, JSON array on stdout
//   2 — input file missing
//   3 — TOML appears malformed (allowlist section header present but the
//       `paths = [...]` body has an unclosed bracket)
//   4 — v8.25+ `[[allowlists]]` shape detected (parser must be updated)

import fs from "node:fs";
import path from "node:path";

const inputPath = process.argv[2] ?? ".gitleaks.toml";

if (!fs.existsSync(inputPath)) {
  process.stderr.write(`error: file not found: ${inputPath}\n`);
  process.exit(2);
}

const src = fs.readFileSync(path.resolve(inputPath), "utf8");

// v8.25+ schema guard. Top-level `[[allowlists]]` is the new umbrella block;
// the parser does not understand `targetRules` semantics, so refuse rather
// than silently emit an incomplete path list.
if (/^\[\[allowlists\]\]/m.test(src)) {
  process.stderr.write(
    "error: detected v8.25+ `[[allowlists]]` block (with potential `targetRules` semantics). " +
      "This parser is locked to gitleaks v8.24.2 syntax (per-rule `[[rules.allowlists]]` only). " +
      "Update parse-gitleaks-allowlists.mjs alongside the gitleaks version bump.\n",
  );
  process.exit(4);
}

const hasAllowlistSection = /^\[allowlist\]|^\s*\[\[rules\.allowlists\]\]/m.test(src);

const literalRe = /'''([\s\S]*?)'''/g;
const startRe = /paths\s*=\s*\[/g;

// Find each `paths = [` start, then walk character-by-character tracking
// triple-quote string state until the matching closing `]` is hit.
// Returns the body string (between `[` and matching `]`) or null on
// unclosed-bracket failure.
function findArrayBody(text, startIdx) {
  let i = startIdx;
  while (i < text.length) {
    // Inside `'''…'''`? skip to the closing triple quote.
    if (text.startsWith("'''", i)) {
      const close = text.indexOf("'''", i + 3);
      if (close === -1) return null;
      i = close + 3;
      continue;
    }
    if (text[i] === "]") return text.slice(startIdx, i);
    i++;
  }
  return null;
}

const paths = new Set();
let arrayCount = 0;
let malformed = false;

let startMatch;
while ((startMatch = startRe.exec(src)) !== null) {
  const bodyStart = startMatch.index + startMatch[0].length;
  const body = findArrayBody(src, bodyStart);
  if (body === null) {
    malformed = true;
    continue;
  }
  arrayCount++;
  let lit;
  literalRe.lastIndex = 0;
  while ((lit = literalRe.exec(body)) !== null) {
    paths.add(lit[1]);
  }
}

if (malformed && arrayCount === 0) {
  process.stderr.write(
    "error: malformed TOML — `paths = [...]` array has no matching closing bracket.\n",
  );
  process.exit(3);
}
if (hasAllowlistSection && arrayCount === 0) {
  process.stderr.write(
    "error: malformed TOML — found allowlist section header but no parseable `paths = [...]` array.\n",
  );
  process.exit(3);
}

process.stdout.write(JSON.stringify([...paths]) + "\n");
