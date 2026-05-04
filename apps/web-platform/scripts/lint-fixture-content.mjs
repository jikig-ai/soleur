#!/usr/bin/env node
// lint-fixture-content.mjs — secret-scanning floor companion linter (#3121).
//
// Catches semi-sensitive shapes that gitleaks misses or that we don't want
// in fixtures even when allowlisted by path:
//   - Real-looking emails (anything not @example.com / @example.org / *.test / fixtures.local)
//   - Supabase prod-shape project refs ([a-z0-9]{20}.supabase.co)
//   - Supabase prod-shape UUIDs (against an allowlist of known synthesized values)
//
// Waiver: line containing `# gitleaks:allow # issue:#NNN <reason>` (or the `//` form)
// is exempt; waivers without an issue:#NNN AND a non-empty reason are rejected.
//
// Invocation: lefthook passes staged file paths via {staged_files}.
//   node apps/web-platform/scripts/lint-fixture-content.mjs <file> [<file> ...]
//
// Exits 1 with `file:line:reason` on first match. Exits 0 if no matches.

import { readFileSync } from "node:fs";

const REAL_EMAIL = /\b([A-Z0-9._%+-]+)@([A-Z0-9.-]+\.[A-Z]{2,})\b/gi;
const ALLOWED_EMAIL_HOSTS = /^(example\.com|example\.org|.+\.test|fixtures\.local|test\.local)$/i;

// Synthesized UUIDs we actively use in fixtures — extend as new ones land.
const ALLOWED_UUIDS = new Set([
  "00000000-0000-0000-0000-000000000000",
  "11111111-1111-1111-1111-111111111111",
  "deadbeef-dead-beef-dead-beefdeadbeef",
]);
const UUID_RE = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

const SUPABASE_REF_RE = /\b([a-z0-9]{20})\.supabase\.co\b/g;

const WAIVER_RE = /(?:#|\/\/)\s*gitleaks:allow\b(.*)$/;
const WAIVER_TRAILER_RE = /issue:#\d+\s+\S{3,}/;

// Heuristic: NUL byte in the first 8 KiB → treat as binary and skip.
function looksBinary(buf) {
  const slice = buf.subarray(0, Math.min(buf.length, 8192));
  for (let i = 0; i < slice.length; i++) {
    if (slice[i] === 0) return true;
  }
  return false;
}

function lintLine(line) {
  // Honor + validate waivers FIRST so a malformed waiver fails noisily.
  const waiver = WAIVER_RE.exec(line);
  if (waiver) {
    if (!WAIVER_TRAILER_RE.test(waiver[1] ?? "")) {
      return ["waiver missing 'issue:#NNN <reason>' trailer (reason must be ≥3 chars)"];
    }
    return null;
  }

  const reasons = [];

  for (const match of line.matchAll(REAL_EMAIL)) {
    const host = match[2];
    if (!ALLOWED_EMAIL_HOSTS.test(host)) {
      reasons.push(
        `real-looking email '${match[0]}' (use @example.com / @test.local / @fixtures.local)`,
      );
    }
  }

  for (const match of line.matchAll(UUID_RE)) {
    const uuid = match[0].toLowerCase();
    if (!ALLOWED_UUIDS.has(uuid)) {
      reasons.push(
        `prod-shape UUID '${uuid}' (use a value from ALLOWED_UUIDS or add via PR)`,
      );
    }
  }

  for (const match of line.matchAll(SUPABASE_REF_RE)) {
    reasons.push(`Supabase prod-shape project ref '${match[0]}'`);
  }

  return reasons.length > 0 ? reasons : null;
}

function lintFile(path) {
  // Single-syscall read avoids the TOCTOU race window between stat() and
  // readFileSync() (CodeQL js/file-system-race). ENOENT/EISDIR/EACCES are
  // treated as "skip silently" to match the prior behavior of skipping
  // deleted-in-same-stage files and accidentally-passed directories.
  let buf;
  try {
    buf = readFileSync(path);
  } catch (err) {
    if (err && (err.code === "ENOENT" || err.code === "EISDIR" || err.code === "EACCES")) return [];
    throw err;
  }
  if (looksBinary(buf)) return [];

  const content = buf.toString("utf8");
  const findings = [];
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const reasons = lintLine(lines[i]);
    if (reasons) {
      for (const reason of reasons) {
        findings.push({ path, line: i + 1, reason });
      }
    }
  }
  return findings;
}

const files = process.argv.slice(2).filter(Boolean);
if (files.length === 0) process.exit(0);

let exitCode = 0;
for (const path of files) {
  const findings = lintFile(path);
  for (const f of findings) {
    process.stderr.write(`${f.path}:${f.line}: ${f.reason}\n`);
    exitCode = 1;
  }
}
process.exit(exitCode);
